#!/usr/bin/env bash
# 對指定 namespace 的 Postgres 建立 pg_dump 快照
#
# 用法:
#   scripts/snapshot-db.sh <namespace>           建立快照
#   scripts/snapshot-db.sh <namespace> --list    列出現有快照

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMPL="${ROOT}/manifests/db-snapshot"

NS="${1:-}"
LIST_MODE=false
[[ "${2:-}" == "--list" ]] && LIST_MODE=true

if [[ -z "${NS}" ]]; then
  echo "用法: $0 <namespace> [--list]" >&2
  echo "  namespace 例: sit / sit-bob / sit-alice" >&2
  exit 1
fi

# ── 確認 namespace 存在且有 Postgres ──────────────────────────────────────────
if ! kubectl get namespace "${NS}" &>/dev/null; then
  echo "❌ namespace ${NS} 不存在" >&2; exit 1
fi
if ! kubectl get statefulset postgres -n "${NS}" &>/dev/null; then
  echo "❌ ${NS} 沒有 postgres StatefulSet" >&2; exit 1
fi

# ── 列出模式 ──────────────────────────────────────────────────────────────────
if [[ "${LIST_MODE}" == "true" ]]; then
  if ! kubectl get pvc postgres-snapshots -n "${NS}" &>/dev/null; then
    echo "（${NS} 尚無快照 PVC）"
    exit 0
  fi
  echo "=== ${NS} 快照清單 ==="
  kubectl run list-snapshots-$$ \
    --image=busybox:1.36 \
    --restart=Never \
    --rm -i \
    --namespace="${NS}" \
    --overrides="{
      \"spec\":{
        \"containers\":[{
          \"name\":\"ls\",
          \"image\":\"busybox:1.36\",
          \"command\":[\"ls\",\"-lh\",\"/snapshots\"],
          \"volumeMounts\":[{\"name\":\"s\",\"mountPath\":\"/snapshots\"}]
        }],
        \"volumes\":[{\"name\":\"s\",\"persistentVolumeClaim\":{\"claimName\":\"postgres-snapshots\"}}]
      }
    }" 2>/dev/null
  exit 0
fi

# ── 建立快照 ──────────────────────────────────────────────────────────────────
SNAPSHOT_NAME="$(date +%Y%m%d-%H%M%S)-${NS}"
export NS
export SNAPSHOT_NAME

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  建立快照: ${SNAPSHOT_NAME}"
echo "  Namespace: ${NS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 確保快照 PVC 存在
if ! kubectl get pvc postgres-snapshots -n "${NS}" &>/dev/null; then
  echo "[1/3] 建立快照 PVC（postgres-snapshots, 5Gi）"
  envsubst '${NS}' < "${TMPL}/00-snapshot-pvc.yaml" | kubectl apply -f -
  # 等待 PVC Bound（local-path 需要第一個 Pod 掛載才會 Bind）
else
  echo "[1/3] 快照 PVC 已存在，跳過"
fi

# 清理同名舊 Job（冪等）
kubectl delete job "pg-snapshot-${SNAPSHOT_NAME}" -n "${NS}" --ignore-not-found >/dev/null

echo "[2/3] 執行 pg_dump Job"
envsubst '${NS} ${SNAPSHOT_NAME}' < "${TMPL}/10-snapshot-job.yaml" | kubectl apply -f -

echo "  等待 pg_dump 完成（最多 120s）..."
kubectl wait job "pg-snapshot-${SNAPSHOT_NAME}" -n "${NS}" \
  --for=condition=Complete --timeout=120s

echo "[3/3] 快照 Job logs:"
kubectl logs -n "${NS}" "job/pg-snapshot-${SNAPSHOT_NAME}" 2>/dev/null | grep -v "^$"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 快照完成: ${SNAPSHOT_NAME}"
echo ""
echo "  還原指令:"
echo "    scripts/restore-db.sh ${NS} ${SNAPSHOT_NAME}"
echo ""
echo "  查看所有快照:"
echo "    scripts/snapshot-db.sh ${NS} --list"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
