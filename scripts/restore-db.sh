#!/usr/bin/env bash
# 從指定快照還原 namespace 的 Postgres
#
# 用法:
#   scripts/restore-db.sh <namespace> <snapshot-name>
#
# 還原流程:
#   1. Scale down 4 個 PetClinic 服務（切斷 DB 連線）
#   2. 執行 pg_restore Job
#   3. Scale up 服務，等待 Ready
#
# 查看可用快照:
#   scripts/snapshot-db.sh <namespace> --list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMPL="${ROOT}/manifests/db-snapshot"

NS="${1:-}"
SNAPSHOT_NAME="${2:-}"

if [[ -z "${NS}" || -z "${SNAPSHOT_NAME}" ]]; then
  echo "用法: $0 <namespace> <snapshot-name>" >&2
  echo "  查看快照: scripts/snapshot-db.sh <namespace> --list" >&2
  exit 1
fi

# ── 確認 namespace 存在且有快照 PVC ───────────────────────────────────────────
if ! kubectl get namespace "${NS}" &>/dev/null; then
  echo "❌ namespace ${NS} 不存在" >&2; exit 1
fi
if ! kubectl get pvc postgres-snapshots -n "${NS}" &>/dev/null; then
  echo "❌ ${NS} 沒有快照 PVC（postgres-snapshots），請先執行 scripts/snapshot-db.sh ${NS}）" >&2
  exit 1
fi

export NS
export SNAPSHOT_NAME

APPS="customers-service vets-service visits-service api-gateway"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  還原快照: ${SNAPSHOT_NAME}"
echo "  Namespace: ${NS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Scale down PetClinic 服務 ─────────────────────────────────────────
echo "[1/4] Scale down PetClinic 服務（切斷 DB 連線）"
for app in ${APPS}; do
  kubectl scale deployment "${app}" -n "${NS}" --replicas=0 2>/dev/null || true
done
# 等所有 Pod 消失
kubectl wait pod -n "${NS}" \
  -l 'app in (customers-service,vets-service,visits-service,api-gateway)' \
  --for=delete --timeout=60s 2>/dev/null || true
echo "  ✅ 服務已停止"

# ── Step 2: 執行 pg_restore Job ───────────────────────────────────────────────
echo "[2/4] 執行 pg_restore Job"
kubectl delete job "pg-restore-${SNAPSHOT_NAME}" -n "${NS}" --ignore-not-found >/dev/null
envsubst '${NS} ${SNAPSHOT_NAME}' < "${TMPL}/20-restore-job.yaml" | kubectl apply -f -

echo "  等待 pg_restore 完成（最多 120s）..."
if ! kubectl wait job "pg-restore-${SNAPSHOT_NAME}" -n "${NS}" \
    --for=condition=Complete --timeout=120s; then
  echo "❌ pg_restore 失敗！查看 logs："
  kubectl logs -n "${NS}" "job/pg-restore-${SNAPSHOT_NAME}" 2>/dev/null
  echo "重新 scale up 服務..."
  for app in ${APPS}; do
    kubectl scale deployment "${app}" -n "${NS}" --replicas=1 2>/dev/null || true
  done
  exit 1
fi

echo "[3/4] pg_restore logs:"
kubectl logs -n "${NS}" "job/pg-restore-${SNAPSHOT_NAME}" 2>/dev/null | grep -v "^$"

# ── Step 3: Scale up PetClinic 服務 ───────────────────────────────────────────
echo "[4/4] Scale up PetClinic 服務"
for app in ${APPS}; do
  kubectl scale deployment "${app}" -n "${NS}" --replicas=1 2>/dev/null || true
done

echo "  等待服務 Ready（最多 300s）..."
kubectl wait pod \
  -n "${NS}" \
  -l 'app in (customers-service,vets-service,visits-service,api-gateway)' \
  --for=condition=Ready \
  --timeout=300s

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 還原完成！"
echo ""
if [[ "${NS}" == sit-* ]]; then HOST="${NS#sit-}-sit.local"; else HOST="${NS}.local"; fi
echo "  驗收:"
echo "    curl -s -H 'Host: ${HOST}' http://localhost:30080/api/customer/owners | jq length"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
