#!/usr/bin/env bash
# 刪除指定使用者的 SIT namespace (sit-<username>) 及所有資源
#
# 用法:
#   ./delete-sit-user.sh <username>
#       直接 kubectl delete namespace（立即刪除，不動 git）
#
#   ./delete-sit-user.sh --gitops <username>
#       從 git 移除 manifests/sit-users/<username>/，commit + push，
#       ArgoCD ApplicationSet 偵測後自動刪除 Application + K8s 資源

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GITOPS=false
if [[ "${1:-}" == "--gitops" ]]; then
  GITOPS=true
  shift
fi

USERNAME="${1:-}"
if [[ -z "${USERNAME}" ]]; then
  echo "用法: $0 [--gitops] <username>" >&2
  exit 1
fi

NS="sit-${USERNAME}"

# ── GitOps 模式 ──────────────────────────────────────────────────────────────
if [[ "${GITOPS}" == "true" ]]; then
  OVERLAY_DIR="${ROOT}/manifests/sit-users/${USERNAME}"
  if [[ ! -d "${OVERLAY_DIR}" ]]; then
    echo "錯誤: ${OVERLAY_DIR} 不存在，無法刪除。" >&2
    exit 1
  fi

  echo "移除 overlay 目錄: ${OVERLAY_DIR}"
  cd "${ROOT}"
  git rm -r "manifests/sit-users/${USERNAME}/"
  git commit -m "feat(sit): 移除 ${USERNAME} 的 SIT namespace"
  git push origin main

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✅ overlay 已從 git 移除。"
  echo "  ArgoCD ApplicationSet 將在 3 分鐘內刪除："
  echo "    Application petclinic-sit-${USERNAME}"
  echo "    Namespace ${NS} 及所有資源（含 PVC）"
  echo ""
  echo "  監控進度:"
  echo "    kubectl get application -n argocd | grep ${USERNAME}"
  echo "    kubectl get namespace ${NS}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

# ── 直接模式 ─────────────────────────────────────────────────────────────────
if ! kubectl get namespace "${NS}" &>/dev/null; then
  echo "Namespace ${NS} 不存在，無需刪除。" >&2
  exit 0
fi

echo "刪除 namespace ${NS} 及所有資源（包含 PVC）..."
kubectl delete namespace "${NS}"
echo "✅ ${NS} 已刪除。"
echo ""
echo "記得從 /etc/hosts 移除: ${USERNAME}-sit.local"
