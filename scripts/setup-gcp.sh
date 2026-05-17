#!/usr/bin/env bash
# GCP Bootstrap：從零到 v2.3 全棧（GKE + Artifact Registry + nip.io）
#
# 前提（需在本機手動安裝）：
#   gcloud, kubectl, helm, docker, envsubst
#   已執行: gcloud auth login && gcloud auth application-default login
#
# 用法：
#   bash scripts/setup-gcp.sh                         # 完整安裝
#   bash scripts/setup-gcp.sh --skip-build            # 跳過 image build（GAR 已有 image）
#   bash scripts/setup-gcp.sh --project my-project    # 指定 GCP Project
#   bash scripts/setup-gcp.sh --region asia-east1     # 指定 Region（預設：asia-east1）
#   bash scripts/setup-gcp.sh --with-monitoring       # 加裝 Prometheus + Grafana + Loki

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKIP_BUILD=false
WITH_MONITORING=false

# ── 參數解析 ─────────────────────────────────────────────────────────────────
PROJECT_ID="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${GCP_REGION:-asia-east1}"
ZONE="${GCP_ZONE:-${REGION}-b}"
CLUSTER_NAME="presit"
NODE_MACHINE="e2-standard-4"
NODE_COUNT=2
GAR_REPO="presit"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)         PROJECT_ID="$2";  shift 2 ;;
    --region)          REGION="$2"; ZONE="${REGION}-b"; shift 2 ;;
    --zone)            ZONE="$2"; shift 2 ;;
    --skip-build)      SKIP_BUILD=true; shift ;;
    --with-monitoring) WITH_MONITORING=true; shift ;;
    *) echo "未知參數: $1" >&2; exit 1 ;;
  esac
done

[[ -z "${PROJECT_ID}" ]] && {
  echo "錯誤：未設定 GCP Project。" >&2
  echo "請執行: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
}

REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/${GAR_REPO}"

# ── 顏色輸出 ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'
step()  { echo -e "\n${CYAN}━━ $* ━━${RESET}"; }
ok()    { echo -e "${GREEN}  ✅ $*${RESET}"; }
info()  { echo -e "${YELLOW}  ℹ  $*${RESET}"; }

# ── 套用 manifest（替換 registry + hostname）────────────────────────────────
# 呼叫前必須已設定 DOMAIN 變數。
apply_gcp() {
  sed \
    -e "s|localhost:5000/|${REGISTRY}/|g" \
    -e "s|\(host: [a-zA-Z0-9._-]*\)\.local|\1.${DOMAIN}|g" \
    "$@" | kubectl apply -f -
}

# ── Step 0: 前提工具檢查 ──────────────────────────────────────────────────────
step "前提檢查"
MISSING=()
for cmd in gcloud kubectl helm docker envsubst; do
  command -v "${cmd}" &>/dev/null || MISSING+=("${cmd}")
done
[[ ${#MISSING[@]} -gt 0 ]] && {
  echo "錯誤：以下工具未安裝：${MISSING[*]}" >&2; exit 1
}
ok "工具就緒（PROJECT=${PROJECT_ID}, REGION=${REGION}, ZONE=${ZONE}）"

# ── Step 1: GCP API + Artifact Registry ──────────────────────────────────────
step "Step 1/9: 啟用 GCP API + 建立 Artifact Registry"
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  --project="${PROJECT_ID}" --quiet

gcloud artifacts repositories create "${GAR_REPO}" \
  --repository-format=docker \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --quiet 2>/dev/null \
  || info "GAR repository '${GAR_REPO}' 已存在"

gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# 授權 GKE 節點 SA 拉取 GAR image（節點建立後套用亦可）
PROJECT_NUM=$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')
NODE_SA="${PROJECT_NUM}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${NODE_SA}" \
  --role="roles/artifactregistry.reader" \
  --quiet
ok "Artifact Registry 就緒：${REGISTRY}"

# ── Step 2: GKE Standard Zonal 叢集 ──────────────────────────────────────────
step "Step 2/9: GKE Standard Zonal 叢集（Spot 節點）"
if gcloud container clusters describe "${CLUSTER_NAME}" \
    --zone="${ZONE}" --project="${PROJECT_ID}" &>/dev/null; then
  info "叢集 '${CLUSTER_NAME}' 已存在，跳過建立"
else
  # 建立叢集（僅保留系統節點池，稍後替換為 Spot 池）
  gcloud container clusters create "${CLUSTER_NAME}" \
    --zone="${ZONE}" \
    --project="${PROJECT_ID}" \
    --machine-type="${NODE_MACHINE}" \
    --num-nodes=1 \
    --release-channel=regular \
    --quiet

  # 建立 Spot 節點池
  gcloud container node-pools create spot-pool \
    --cluster="${CLUSTER_NAME}" \
    --zone="${ZONE}" \
    --project="${PROJECT_ID}" \
    --machine-type="${NODE_MACHINE}" \
    --num-nodes="${NODE_COUNT}" \
    --spot \
    --quiet

  # 移除預設非 Spot 節點池以節省費用
  gcloud container node-pools delete default-pool \
    --cluster="${CLUSTER_NAME}" \
    --zone="${ZONE}" \
    --project="${PROJECT_ID}" \
    --quiet
fi

gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --zone="${ZONE}" --project="${PROJECT_ID}" --quiet
ok "GKE 叢集 '${CLUSTER_NAME}' (${ZONE}) 就緒，kubectl context 已切換"

# ── Step 3: Image build + push 到 GAR ────────────────────────────────────────
step "Step 3/9: PetClinic image build + push 到 Artifact Registry"
if [[ "${SKIP_BUILD}" == "false" ]]; then
  (cd "${ROOT}/petclinic-src" && ./mvnw -B package -DskipTests -q 2>&1 | tail -3)

  for svc in customers-service vets-service visits-service api-gateway; do
    docker build -q -t "${REGISTRY}/petclinic-${svc}:v2.2" \
      "${ROOT}/petclinic-src/spring-petclinic-${svc}"
    docker push "${REGISTRY}/petclinic-${svc}:v2.2"
  done

  # BDD runner image
  (cd "${ROOT}/presit-bdd-demo/poc-v2.2" && \
    docker build -q -t "${REGISTRY}/presit-bdd-runner:v2.2" . && \
    docker push "${REGISTRY}/presit-bdd-runner:v2.2")

  # presit-editor image
  (cd "${ROOT}/presit-editor" && \
    docker build -q -t "${REGISTRY}/presit-editor:v1" . && \
    docker push "${REGISTRY}/presit-editor:v1")

  ok "所有 image build + push 完成"
else
  ok "跳過 image build（--skip-build）"
fi

# ── Step 4: nginx-ingress（LoadBalancer）+ nip.io domain ─────────────────────
step "Step 4/9: nginx-ingress（LoadBalancer）→ nip.io domain"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update ingress-nginx > /dev/null

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --wait --timeout=5m

echo "  等待 LoadBalancer 取得外部 IP（最多 5 分鐘）..."
EXTERNAL_IP=""
for i in $(seq 1 30); do
  EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "${EXTERNAL_IP}" ]] && break
  sleep 10
done
[[ -z "${EXTERNAL_IP}" ]] && {
  echo "錯誤：無法取得 LoadBalancer IP" >&2; exit 1
}

DOMAIN="${EXTERNAL_IP}.nip.io"
ok "nginx-ingress 就緒，服務網域：*.${DOMAIN}"

# ── Step 5: ArgoCD ────────────────────────────────────────────────────────────
step "Step 5/9: ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.1/manifests/install.yaml
  kubectl wait -n argocd --for=condition=Available deployment --all --timeout=300s
fi
kubectl apply -f "${ROOT}/manifests/argocd/00-argocd-params-cm.yaml"
apply_gcp "${ROOT}/manifests/argocd/10-ingress.yaml"
kubectl rollout restart deployment argocd-server -n argocd > /dev/null
kubectl rollout status deployment argocd-server -n argocd --timeout=60s > /dev/null
ok "ArgoCD 就緒（http://argocd.${DOMAIN}/）"

# ── Step 6: Sealed Secrets + DB 認證 ─────────────────────────────────────────
step "Step 6/9: Sealed Secrets controller + 資料庫認證"
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets 2>/dev/null || true
helm repo update sealed-secrets > /dev/null | tail -1

helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --values "${ROOT}/manifests/sealed-secrets/values.yaml" \
  --wait

kubectl rollout status deployment/sealed-secrets-controller -n kube-system --timeout=60s

# GCP 叢集的 Sealed Secrets 憑證與本機 Kind 叢集不同，
# 舊的封存 SealedSecret 無法在新叢集解密。
# 教學用途：直接建立 Secret（生產環境請用 kubeseal 重新封存）。
info "GCP 新叢集：直接建立 DB Secret（demo 預設值 petclinic/petclinic）"
info "生產環境請用：kubeseal --fetch-cert 取得新憑證後重新封存"
for NS in pre-sit sit; do
  kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic petclinic-db-credentials \
    --namespace="${NS}" \
    --from-literal=POSTGRES_USER=petclinic \
    --from-literal=POSTGRES_PASSWORD=petclinic \
    --dry-run=client -o yaml | kubectl apply -f -
done
ok "Sealed Secrets controller 就緒，DB Secret 已建立"

# ── Step 7: 基礎 namespace 資源（pre-sit + sit）────────────────────────────────
step "Step 7/9: Pre-SIT + SIT 基礎資源"

# pre-sit（跳過 06-sealed-db-credentials.yaml，已在 Step 6 建立）
kubectl apply -f "${ROOT}/manifests/pre-sit/05-config.yaml"
kubectl apply -f "${ROOT}/manifests/pre-sit/10-postgres.yaml"
apply_gcp    "${ROOT}/manifests/pre-sit/20-petclinic-services.yaml"
kubectl apply -f "${ROOT}/manifests/pre-sit/25-presit-sa.yaml"
apply_gcp    "${ROOT}/manifests/pre-sit/30-bdd-jobs.yaml"
kubectl apply -f "${ROOT}/manifests/pre-sit/40-ui-screenshot.yaml"

# sit（跳過 06-sealed-db-credentials.yaml）
kubectl apply -f "${ROOT}/manifests/sit/00-namespace.yaml"
kubectl apply -f "${ROOT}/manifests/sit/05-config.yaml"
kubectl apply -f "${ROOT}/manifests/sit/10-postgres.yaml"
apply_gcp    "${ROOT}/manifests/sit/20-petclinic-services.yaml"
apply_gcp    "${ROOT}/manifests/sit/30-ingress.yaml"

echo "  等待 pre-sit 服務就緒（最多 5 分鐘）..."
kubectl wait -n pre-sit --for=condition=Available deployment --all --timeout=300s
ok "Pre-SIT + SIT 基礎資源就緒"

# ── Step 8: Argo Workflows ────────────────────────────────────────────────────
step "Step 8/9: Argo Workflows"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo > /dev/null

helm upgrade --install argo-workflows argo/argo-workflows \
  --namespace argo --create-namespace \
  -f "${ROOT}/manifests/argo-workflows/10-install-values.yaml" \
  --wait --timeout=5m

kubectl apply -f "${ROOT}/manifests/argo-workflows/05-rbac.yaml"
apply_gcp    "${ROOT}/manifests/argo-workflows/20-workflow-template.yaml"
apply_gcp    "${ROOT}/manifests/argo-workflows/30-ingress.yaml"
ok "Argo Workflows 就緒（http://argo.${DOMAIN}/）"

# ── Step 9: presit-editor ─────────────────────────────────────────────────────
step "Step 9/9: Pre-SIT Gherkin Editor"
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  info "GITHUB_TOKEN 未設定 — Editor git push 功能將停用"
  info "設定後重跑：export GITHUB_TOKEN=ghp_... && bash scripts/setup-gcp.sh --skip-build"
  GITHUB_TOKEN="not-configured"
fi

kubectl create secret generic presit-editor-git \
  --namespace pre-sit \
  --from-literal=GITHUB_TOKEN="${GITHUB_TOKEN}" \
  --from-literal=GIT_USER="presit-editor" \
  --from-literal=GIT_EMAIL="presit-editor@presit.local" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${ROOT}/manifests/presit-editor/05-rbac.yaml"
apply_gcp    "${ROOT}/manifests/presit-editor/10-deployment.yaml"
kubectl apply -f "${ROOT}/manifests/presit-editor/15-service.yaml"
apply_gcp    "${ROOT}/manifests/presit-editor/20-ingress.yaml"
ok "Pre-SIT Editor 就緒（http://presit-editor.${DOMAIN}/）"

# ── Step Optional: 監控（--with-monitoring）──────────────────────────────────
if [[ "${WITH_MONITORING}" == "true" ]]; then
  step "Step Optional: Observability（Prometheus + Grafana + Loki）"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
  helm repo update prometheus-community grafana > /dev/null

  kubectl apply -f "${ROOT}/manifests/monitoring/00-namespace.yaml"

  helm upgrade --install kube-prometheus \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values "${ROOT}/manifests/monitoring/values-kube-prometheus.yaml" \
    --set grafana.sidecar.dashboards.enabled=true \
    --set grafana.sidecar.dashboards.label=grafana_dashboard \
    --timeout=10m --wait

  helm upgrade --install loki \
    grafana/loki-stack \
    --namespace monitoring \
    --values "${ROOT}/manifests/monitoring/values-loki.yaml" \
    --timeout=5m --wait

  kubectl apply -f "${ROOT}/manifests/monitoring/10-servicemonitors.yaml"
  kubectl apply -f "${ROOT}/manifests/monitoring/20-dashboards.yaml"
  apply_gcp    "${ROOT}/manifests/monitoring/30-ingress.yaml"
  ok "Prometheus + Grafana + Loki 就緒（http://grafana.${DOMAIN}/）"
fi

# ── 完成總覽 ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ GCP v2.3 全棧安裝完成！"
echo ""
echo "  GKE 叢集:  ${CLUSTER_NAME} (${ZONE})"
echo "  GAR:       ${REGISTRY}"
echo "  服務網域:  *.${DOMAIN}"
echo ""
echo "  服務入口（nginx-ingress LoadBalancer，port 80）："
echo "    SIT PetClinic    http://sit.${DOMAIN}/"
echo "    Argo Workflows   http://argo.${DOMAIN}/         無需登入"
echo "    ArgoCD           http://argocd.${DOMAIN}/"
echo "    Pre-SIT Editor   http://presit-editor.${DOMAIN}/"
if [[ "${WITH_MONITORING}" == "true" ]]; then
echo "    Grafana          http://grafana.${DOMAIN}/       admin / presit-admin"
fi
echo ""
echo "  ArgoCD 初始密碼："
echo "    kubectl -n argocd get secret argocd-initial-admin-secret \\"
echo "            -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "  執行 Pre-SIT Pipeline："
echo "    kubectl create -f - <<EOF"
echo "    apiVersion: argoproj.io/v1alpha1"
echo "    kind: Workflow"
echo "    metadata:"
echo "      generateName: presit-pipeline-"
echo "      namespace: argo"
echo "    spec:"
echo "      workflowTemplateRef:"
echo "        name: presit-pipeline"
echo "    EOF"
echo ""
echo "  月費估算（${REGION}）："
echo "    e2-standard-4 × ${NODE_COUNT} Spot:    ~\$40"
echo "    Network LoadBalancer:         ~\$18"
echo "    Artifact Registry:            <\$5"
if [[ "${WITH_MONITORING}" == "true" ]]; then
echo "    監控 PD 儲存:                 ~\$5"
fi
echo "    合計:                         ~\$63/月"
echo ""
echo "  清除資源（停止計費）："
echo "    gcloud container clusters delete ${CLUSTER_NAME} \\"
echo "      --zone=${ZONE} --project=${PROJECT_ID} --quiet"
echo "    gcloud artifacts repositories delete ${GAR_REPO} \\"
echo "      --location=${REGION} --project=${PROJECT_ID} --quiet"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
