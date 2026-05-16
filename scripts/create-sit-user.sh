#!/usr/bin/env bash
# 為指定使用者建立獨立的 SIT namespace (sit-<username>)
#
# 用法:
#   ./create-sit-user.sh <username> [image-tag]
#       直接 kubectl apply — 快速，不需 ArgoCD
#
#   ./create-sit-user.sh --gitops <username> [image-tag]
#       生成 Kustomize overlay 到 manifests/sit-users/<username>/，
#       commit + push 後由 ArgoCD ApplicationSet 自動 sync
#
# 前提:
#   - Kind 叢集已啟動，kubeseal 已安裝（~/.local/bin/kubeseal）
#   - Sealed Secrets controller 已部署（scripts/setup-sealed-secrets.sh）
#   - nginx-ingress 已部署（NodePort 30080）
#   - [gitops 模式] ApplicationSet 已套用（manifests/argocd/appset-sit-users.yaml）

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMPL="${ROOT}/manifests/sit-user-template"

# ── 參數解析 ────────────────────────────────────────────────────────────────
GITOPS=false
if [[ "${1:-}" == "--gitops" ]]; then
  GITOPS=true
  shift
fi

USERNAME="${1:-}"
IMAGE_TAG="${2:-v2.2}"

if [[ -z "${USERNAME}" ]]; then
  echo "用法: $0 [--gitops] <username> [image-tag]" >&2
  exit 1
fi
if ! [[ "${USERNAME}" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
  echo "錯誤: username 只允許小寫英數字與連字號，且不能以連字號開頭/結尾" >&2
  exit 1
fi

export USERNAME
export NS="sit-${USERNAME}"
export IMAGE_TAG

# ── 共用：檢查 kubeseal ──────────────────────────────────────────────────────
for cmd in kubectl kubeseal; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "錯誤: 找不到 ${cmd}" >&2
    exit 1
  fi
done

if ! kubectl get deployment sealed-secrets-controller -n kube-system &>/dev/null; then
  echo "錯誤: Sealed Secrets controller 未就緒，請先執行 scripts/setup-sealed-secrets.sh" >&2
  exit 1
fi

# ── 共用：讀取 credentials ──────────────────────────────────────────────────
POSTGRES_USER=$(kubectl get secret petclinic-db-credentials -n sit \
  -o jsonpath='{.data.POSTGRES_USER}' 2>/dev/null | base64 -d || echo "petclinic")
POSTGRES_PASSWORD=$(kubectl get secret petclinic-db-credentials -n sit \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d || echo "petclinic")

# ════════════════════════════════════════════════════════════════════════════
# GitOps 模式：生成 Kustomize overlay + commit + push
# ════════════════════════════════════════════════════════════════════════════
if [[ "${GITOPS}" == "true" ]]; then
  if ! command -v envsubst &>/dev/null; then
    echo "錯誤: 找不到 envsubst" >&2; exit 1
  fi
  if ! command -v git &>/dev/null; then
    echo "錯誤: 找不到 git" >&2; exit 1
  fi

  OVERLAY_DIR="${ROOT}/manifests/sit-users/${USERNAME}"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  [GitOps] 建立 Kustomize overlay: ${OVERLAY_DIR}"
  echo "  Image tag: ${IMAGE_TAG}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  mkdir -p "${OVERLAY_DIR}"

  # ── Namespace resource（含 sit-user label）──────────────────────────────
  cat > "${OVERLAY_DIR}/00-namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS}
  labels:
    env: sit
    purpose: exploratory-testing
    managed-by: argocd-appset
    sit-user: ${USERNAME}
EOF

  # ── SealedSecret（namespace-scoped 重新封存）────────────────────────────
  echo "[1/3] 封存 DB credentials → ${OVERLAY_DIR}/06-sealed-db-credentials.yaml"
  kubectl create secret generic petclinic-db-credentials \
    -n "${NS}" \
    --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
    --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    --dry-run=client -o yaml \
  | kubeseal \
      --controller-name=sealed-secrets-controller \
      --controller-namespace=kube-system \
      --format yaml \
  > "${OVERLAY_DIR}/06-sealed-db-credentials.yaml"
  echo "  ✅ SealedSecret 已寫入 git tree"

  # ── Kustomize overlay kustomization.yaml ────────────────────────────────
  echo "[2/3] 生成 kustomization.yaml"
  cat > "${OVERLAY_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# overlay 指向共用 base
resources:
- ../../sit-user-base
- 00-namespace.yaml
- 06-sealed-db-credentials.yaml

# Kustomize 的 namespace 指令會套用到除 Namespace 本身以外的所有資源
namespace: ${NS}

images:
- name: localhost:5000/petclinic-customers-service
  newTag: ${IMAGE_TAG}
- name: localhost:5000/petclinic-vets-service
  newTag: ${IMAGE_TAG}
- name: localhost:5000/petclinic-visits-service
  newTag: ${IMAGE_TAG}
- name: localhost:5000/petclinic-api-gateway
  newTag: ${IMAGE_TAG}

patches:
# ConfigMap 的 svc 參照必須指向正確 namespace（namespace 指令不改 data 內容）
- patch: |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: petclinic-db-config
    data:
      POSTGRES_HOST: "postgres.${NS}.svc"
      CUSTOMERS_SERVICE_URI: "http://customers-service.${NS}.svc:8081"
      VETS_SERVICE_URI:      "http://vets-service.${NS}.svc:8083"
      VISITS_SERVICE_URI:    "http://visits-service.${NS}.svc:8082"

# Ingress host 換成 <username>-sit.local
- patch: |
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: petclinic
    spec:
      rules:
      - host: ${USERNAME}-sit.local
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-gateway
                port:
                  number: 8080
EOF

  # ── git commit + push ────────────────────────────────────────────────────
  echo "[3/3] commit + push → GitHub"
  cd "${ROOT}"
  git add "manifests/sit-users/${USERNAME}/"
  git commit -m "feat(sit): add per-user namespace for ${USERNAME} (${IMAGE_TAG})"
  git push origin main

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✅ overlay 已推送！ArgoCD ApplicationSet 將在 3 分鐘內："
  echo "     1. 偵測到 manifests/sit-users/${USERNAME}/ 目錄"
  echo "     2. 建立 Application petclinic-sit-${USERNAME}"
  echo "     3. 自動 sync → 建立 ${NS} namespace + 所有資源"
  echo ""
  echo "  監控進度:"
  echo "    kubectl get application petclinic-sit-${USERNAME} -n argocd -w"
  echo "    kubectl get pods -n ${NS} -w"
  echo ""
  echo "  存取:"
  echo "    echo '127.0.0.1 ${USERNAME}-sit.local' | sudo tee -a /etc/hosts"
  echo "    curl -s -H 'Host: ${USERNAME}-sit.local' http://localhost:30080/api/customer/owners | jq length"
  echo ""
  echo "  刪除（GitOps）:"
  echo "    scripts/delete-sit-user.sh --gitops ${USERNAME}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# 直接模式：envsubst → kubectl apply（快速，不需 git）
# ════════════════════════════════════════════════════════════════════════════
if ! command -v envsubst &>/dev/null; then
  echo "錯誤: 找不到 envsubst" >&2; exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  建立 SIT namespace: ${NS}"
echo "  Image tag:          ${IMAGE_TAG}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "[1/5] 建立 Namespace ${NS}"
envsubst < "${TMPL}/00-namespace.yaml" | kubectl apply -f -

echo "[2/5] 封存 DB credentials（namespace-scoped）"
kubectl create secret generic petclinic-db-credentials \
  -n "${NS}" \
  --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --dry-run=client -o yaml \
| kubeseal \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=kube-system \
    --format yaml \
| kubectl apply -f -
echo "  ✅ SealedSecret petclinic-db-credentials 套用完成"

echo "[3/5] 套用 ConfigMap、Postgres、PetClinic Services、Ingress"
for f in 05-config.yaml 10-postgres.yaml 20-petclinic-services.yaml 30-ingress.yaml; do
  envsubst < "${TMPL}/${f}" | kubectl apply -f -
done

echo "[4/5] 等待 Postgres StatefulSet 就緒（最多 90s）"
kubectl rollout status statefulset/postgres -n "${NS}" --timeout=90s

echo "[5/5] 等待 PetClinic pods Ready（最多 300s）"
kubectl wait pod \
  -n "${NS}" \
  -l 'app in (customers-service,vets-service,visits-service,api-gateway)' \
  --for=condition=Ready \
  --timeout=300s

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ SIT namespace ${NS} 建立完成！"
echo ""
echo "  存取方式:"
echo "    1) echo '127.0.0.1 ${USERNAME}-sit.local' | sudo tee -a /etc/hosts"
echo "    2) 瀏覽器: http://${USERNAME}-sit.local:30080/"
echo "    3) curl -s -H 'Host: ${USERNAME}-sit.local' \\"
echo "            http://localhost:30080/api/customer/owners | jq length"
echo ""
echo "  刪除: scripts/delete-sit-user.sh ${USERNAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
