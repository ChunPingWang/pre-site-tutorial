#!/usr/bin/env bash
# 為指定使用者建立獨立的 SIT namespace (sit-<username>)
#
# 用法: ./create-sit-user.sh <username> [image-tag]
#   username  : 英數字 + 連字號，例如 alice、bob-dev
#   image-tag : PetClinic image tag，預設 v2.2
#
# 前提:
#   - Kind 叢集已啟動，kubeseal 已安裝（~/.local/bin/kubeseal）
#   - Sealed Secrets controller 已部署（scripts/setup-sealed-secrets.sh）
#   - nginx-ingress 已部署（NodePort 30080）
#   - 登錄你的 /etc/hosts: 127.0.0.1 <username>-sit.local

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMPL="${ROOT}/manifests/sit-user-template"

# ── 參數驗證 ────────────────────────────────────────────────────────────────
USERNAME="${1:-}"
IMAGE_TAG="${2:-v2.2}"

if [[ -z "${USERNAME}" ]]; then
  echo "用法: $0 <username> [image-tag]" >&2
  exit 1
fi
if ! [[ "${USERNAME}" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
  echo "錯誤: username 只允許小寫英數字與連字號，且不能以連字號開頭/結尾" >&2
  exit 1
fi

export USERNAME
export NS="sit-${USERNAME}"
export IMAGE_TAG

# ── 檢查依賴 ────────────────────────────────────────────────────────────────
for cmd in kubectl kubeseal envsubst; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "錯誤: 找不到 ${cmd}，請先安裝" >&2
    exit 1
  fi
done

if ! kubectl get deployment sealed-secrets-controller -n kube-system &>/dev/null; then
  echo "錯誤: Sealed Secrets controller 未就緒，請先執行 scripts/setup-sealed-secrets.sh" >&2
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  建立 SIT namespace: ${NS}"
echo "  Image tag:          ${IMAGE_TAG}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: 建立 namespace ──────────────────────────────────────────────────
echo "[1/5] 建立 Namespace ${NS}"
envsubst < "${TMPL}/00-namespace.yaml" | kubectl apply -f -

# ── Step 2: 取得原始 credentials 並重新封存 ──────────────────────────────
echo "[2/5] 封存 DB credentials（namespace-scoped）"

# 從 sit namespace 取得現有 Secret（已解封的明文），重新封存為新 namespace
POSTGRES_USER=$(kubectl get secret petclinic-db-credentials -n sit \
  -o jsonpath='{.data.POSTGRES_USER}' 2>/dev/null | base64 -d || echo "petclinic")
POSTGRES_PASSWORD=$(kubectl get secret petclinic-db-credentials -n sit \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d || echo "petclinic")

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

# ── Step 3: 套用其餘資源 ────────────────────────────────────────────────────
echo "[3/5] 套用 ConfigMap、Postgres、PetClinic Services、Ingress"
for f in 05-config.yaml 10-postgres.yaml 20-petclinic-services.yaml 30-ingress.yaml; do
  envsubst < "${TMPL}/${f}" | kubectl apply -f -
done

# ── Step 4: 等待 Postgres 就緒 ──────────────────────────────────────────────
echo "[4/5] 等待 Postgres StatefulSet 就緒（最多 90s）"
kubectl rollout status statefulset/postgres -n "${NS}" --timeout=90s

# ── Step 5: 等待 PetClinic pods Ready ───────────────────────────────────────
echo "[5/5] 等待 PetClinic pods Ready（最多 300s）"
kubectl wait pod \
  -n "${NS}" \
  -l 'app in (customers-service,vets-service,visits-service,api-gateway)' \
  --for=condition=Ready \
  --timeout=300s

# ── 完成 ─────────────────────────────────────────────────────────────────────
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ SIT namespace ${NS} 建立完成！"
echo ""
echo "  存取方式:"
echo "    1) 加入 /etc/hosts:"
echo "         echo '127.0.0.1 ${USERNAME}-sit.local' | sudo tee -a /etc/hosts"
echo ""
echo "    2) 瀏覽器: http://${USERNAME}-sit.local:30080/"
echo ""
echo "    3) curl 測試:"
echo "         curl -s -H 'Host: ${USERNAME}-sit.local' \\"
echo "              http://localhost:30080/api/customer/owners | head -c 200"
echo ""
echo "  刪除: scripts/delete-sit-user.sh ${USERNAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
