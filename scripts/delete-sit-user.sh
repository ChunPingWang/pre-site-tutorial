#!/usr/bin/env bash
# 刪除指定使用者的 SIT namespace (sit-<username>) 及所有資源
#
# 用法: ./delete-sit-user.sh <username>

set -euo pipefail

USERNAME="${1:-}"
if [[ -z "${USERNAME}" ]]; then
  echo "用法: $0 <username>" >&2
  exit 1
fi

NS="sit-${USERNAME}"

if ! kubectl get namespace "${NS}" &>/dev/null; then
  echo "Namespace ${NS} 不存在，無需刪除。" >&2
  exit 0
fi

echo "刪除 namespace ${NS} 及所有資源（包含 PVC）..."
kubectl delete namespace "${NS}"
echo "✅ ${NS} 已刪除。"
echo ""
echo "記得從 /etc/hosts 移除: ${USERNAME}-sit.local"
