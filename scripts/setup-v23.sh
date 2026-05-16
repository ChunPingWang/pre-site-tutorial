#!/usr/bin/env bash
# v2.3 全棧 Bootstrap：從 Kind 叢集空白狀態到所有 v2.3 功能就緒
#
# 前提（需在本機手動安裝）：
#   docker, kind, kubectl, helm, kubeseal (~/.local/bin/kubeseal), envsubst
#
# 用法：
#   bash scripts/setup-v23.sh             # 完整安裝（含 PetClinic image build）
#   bash scripts/setup-v23.sh --skip-build  # 跳過 image build（image 已存在時）

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKIP_BUILD=false
[[ "${1:-}" == "--skip-build" ]] && SKIP_BUILD=true

# ── 顏色輸出 ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
step() { echo -e "\n${CYAN}━━ $* ━━${RESET}"; }
ok()   { echo -e "${GREEN}  ✅ $*${RESET}"; }

# ── 前提檢查 ────────────────────────────────────────────────────────────────
step "前提檢查"
MISSING=()
for cmd in docker kind kubectl helm envsubst; do
  command -v "${cmd}" &>/dev/null || MISSING+=("${cmd}")
done
command -v kubeseal &>/dev/null || MISSING+=("kubeseal (~/.local/bin/kubeseal)")
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "錯誤：以下工具未安裝：${MISSING[*]}" >&2
  echo "詳見 README §7.1 先決條件" >&2
  exit 1
fi
ok "所有工具就緒"

# ── Step 1: Kind 叢集 + 本地 registry ───────────────────────────────────────
step "Step 1/9: Kind 叢集 + 本地 registry（冪等）"
bash "${ROOT}/presit-bdd-demo/poc/kind/up.sh"
ok "Kind presit 叢集就緒"

# ── Step 2: nginx-ingress（NodePort 30080）──────────────────────────────────
step "Step 2/9: nginx-ingress"
if ! kubectl get deployment ingress-nginx-controller -n ingress-nginx &>/dev/null; then
  kubectl apply -f \
    https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/kind/deploy.yaml
  kubectl wait -n ingress-nginx \
    --for=condition=Available deployment/ingress-nginx-controller --timeout=120s
fi
ok "nginx-ingress 就緒（NodePort :30080）"

# ── Step 3: ArgoCD ──────────────────────────────────────────────────────────
step "Step 3/9: ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.1/manifests/install.yaml
  kubectl wait -n argocd --for=condition=Available deployment --all --timeout=300s
fi
ok "ArgoCD 就緒"

# ── Step 4: PetClinic image build + push ────────────────────────────────────
step "Step 4/9: PetClinic image build + push"
if [[ "${SKIP_BUILD}" == "false" ]]; then
  (cd "${ROOT}/petclinic-src" && ./mvnw -B package -DskipTests -q 2>&1 | tail -3)
  for svc in customers-service vets-service visits-service api-gateway; do
    docker build -q -t "localhost:5000/petclinic-${svc}:v2.2" \
      "${ROOT}/petclinic-src/spring-petclinic-${svc}"
    docker push "localhost:5000/petclinic-${svc}:v2.2" > /dev/null
  done
  # BDD runner image
  (cd "${ROOT}/presit-bdd-demo/poc-v2.2" && \
    docker build -q -t localhost:5000/presit-bdd-runner:v2.2 . && \
    docker push localhost:5000/presit-bdd-runner:v2.2 > /dev/null)
  ok "所有 image build + push 完成"
else
  ok "跳過 image build（--skip-build）"
fi

# ── Step 5: Sealed Secrets controller + SealedSecrets ───────────────────────
step "Step 5/9: Sealed Secrets"
bash "${ROOT}/scripts/setup-sealed-secrets.sh"
ok "Sealed Secrets controller 就緒，SealedSecrets 已套用"

# ── Step 6: 基礎 namespace manifests（pre-sit / sit）────────────────────────
step "Step 6/9: pre-sit 與 sit namespace 基礎資源"
# pre-sit BDD RBAC（一次性 setup，Jenkins pipeline 不管這個）
kubectl apply -f "${ROOT}/manifests/pre-sit/25-presit-sa.yaml"
ok "pre-sit RBAC 就緒"

# ── Step 7: ArgoCD（insecure mode + Applications + ApplicationSet + Ingress）─
step "Step 7/9: ArgoCD Applications + ApplicationSet + Ingress"
kubectl apply -f "${ROOT}/manifests/argocd/00-argocd-params-cm.yaml"
kubectl apply -f "${ROOT}/manifests/argocd/app-pre-sit.yaml"
kubectl apply -f "${ROOT}/manifests/argocd/app-sit.yaml"
kubectl apply -f "${ROOT}/manifests/argocd/appset-sit-users.yaml"
kubectl apply -f "${ROOT}/manifests/argocd/10-ingress.yaml"
kubectl rollout restart deployment argocd-server -n argocd > /dev/null
kubectl rollout status deployment argocd-server -n argocd --timeout=60s > /dev/null

echo "  等待 petclinic-sit sync（最多 180s）..."
DEADLINE=$(($(date +%s) + 180))
until kubectl get application petclinic-sit -n argocd \
    -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q Synced; do
  [ $(date +%s) -ge ${DEADLINE} ] && echo "TIMEOUT: petclinic-sit sync" && break
  sleep 10
done
ok "ArgoCD Applications + ApplicationSet 套用完成"

# ── Step 8: Argo Workflows（Pre-SIT Pipeline Orchestrator）──────────────────
step "Step 8/9: Argo Workflows"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo > /dev/null
helm upgrade --install argo-workflows argo/argo-workflows \
  --namespace argo --create-namespace \
  -f "${ROOT}/manifests/argo-workflows/10-install-values.yaml" \
  --wait --timeout 5m
kubectl apply -f "${ROOT}/manifests/argo-workflows/05-rbac.yaml"
kubectl apply -f "${ROOT}/manifests/argo-workflows/20-workflow-template.yaml"
kubectl apply -f "${ROOT}/manifests/argo-workflows/30-ingress.yaml"
ok "Argo Workflows 就緒（http://argo.local:30080）"

# ── Step 9: Observability（Prometheus + Grafana + Loki）─────────────────────
step "Step 9/9: Observability"
# Kind 需要提高 inotify 限制，否則 Promtail DaemonSet 會 CrashLoop
docker exec presit-control-plane sysctl -w \
  fs.inotify.max_user_instances=512 \
  fs.inotify.max_user_watches=524288 > /dev/null
bash "${ROOT}/scripts/setup-monitoring.sh"
kubectl apply -f "${ROOT}/manifests/monitoring/30-ingress.yaml"
ok "Prometheus + Grafana + Loki 就緒（http://grafana.local:30080）"

# ── 完成：列出所有服務存取資訊 ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ v2.3 全棧安裝完成！"
echo ""
echo "  所有服務統一走 nginx-ingress（port :30080）"
echo "    SIT PetClinic  http://sit.local:30080/"
echo "    Argo Workflows http://argo.local:30080/         無需登入"
echo "    Grafana        http://grafana.local:30080/       admin / presit-admin"
echo "    ArgoCD         http://argocd.local:30080/"
echo ""
echo "  /etc/hosts（一次加入）:"
echo "    sudo tee -a /etc/hosts <<'EOF'"
echo "    127.0.0.1 sit.local argo.local grafana.local argocd.local"
echo "    EOF"
echo ""
echo "  下一步："
echo "    1. 觸發 Pre-SIT Pipeline（Argo Workflows）："
echo "         kubectl create -f - <<EOF"
echo "         apiVersion: argoproj.io/v1alpha1"
echo "         kind: Workflow"
echo "         metadata:"
echo "           generateName: presit-pipeline-"
echo "           namespace: argo"
echo "         spec:"
echo "           workflowTemplateRef:"
echo "             name: presit-pipeline"
echo "         EOF"
echo ""
echo "    2. 建立個人 SIT namespace："
echo "         scripts/create-sit-user.sh --gitops <your-name>"
echo "         echo '127.0.0.1 <your-name>-sit.local' | sudo tee -a /etc/hosts"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
