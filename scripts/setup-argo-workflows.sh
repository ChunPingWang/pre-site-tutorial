#!/usr/bin/env bash
# 安裝 Argo Workflows 並取代 Jenkins，作為 Pre-SIT BDD Orchestrator
#
# 用法:
#   scripts/setup-argo-workflows.sh          完整安裝
#   scripts/setup-argo-workflows.sh --apply  僅套用 manifests（跳過 Helm install）
#
# 前置條件:
#   - Kind cluster presit 已運行
#   - helm 已安裝
#   - kubectl 已設定 context 指向 presit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFESTS="${ROOT}/manifests/argo-workflows"

APPLY_ONLY=false
[[ "${1:-}" == "--apply" ]] && APPLY_ONLY=true

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Argo Workflows 安裝（取代 Jenkins）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Helm install Argo Workflows ───────────────────────────────────────
if [[ "${APPLY_ONLY}" == "false" ]]; then
  echo "[1/5] 安裝 Argo Workflows via Helm"

  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update argo

  helm upgrade --install argo-workflows argo/argo-workflows \
    --namespace argo \
    --create-namespace \
    -f "${MANIFESTS}/10-install-values.yaml" \
    --wait \
    --timeout 5m

  echo "  ✅ Helm 安裝完成"
else
  echo "[1/5] 跳過 Helm install（--apply 模式）"
fi

# ── Step 2: RBAC ──────────────────────────────────────────────────────────────
echo "[2/5] 套用 RBAC（ServiceAccount + Roles）"
kubectl apply -f "${MANIFESTS}/05-rbac.yaml"
echo "  ✅ RBAC 套用完成"

# ── Step 3: WorkflowTemplate ─────────────────────────────────────────────────
echo "[3/5] 套用 WorkflowTemplate（presit-pipeline）"
kubectl apply -f "${MANIFESTS}/20-workflow-template.yaml"
echo "  ✅ WorkflowTemplate 套用完成"

# ── Step 4: Ingress ───────────────────────────────────────────────────────────
echo "[4/5] 套用 Ingress（argo.local）"

# 等待 argo-server Deployment 存在後再套用 Ingress
echo "  等待 argo-workflows-argo-workflows-server 就緒..."
kubectl -n argo wait deployment argo-workflows-argo-workflows-server \
  --for=condition=Available --timeout=120s 2>/dev/null || true

kubectl apply -f "${MANIFESTS}/30-ingress.yaml"
echo "  ✅ Ingress 套用完成"

# ── Step 5: 移除 Jenkins（可選） ──────────────────────────────────────────────
echo "[5/5] Jenkins 狀態（本步驟不自動刪除，請確認後手動執行）"
if kubectl get namespace jenkins &>/dev/null; then
  echo "  Jenkins namespace 仍存在。如要移除："
  echo "    kubectl delete namespace jenkins"
  echo "    kubectl delete clusterrole jenkins-cluster-reader"
  echo "    kubectl delete clusterrolebinding jenkins-cluster-reader"
else
  echo "  Jenkins namespace 不存在，無需清理"
fi

# ── 驗收 ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Argo Workflows 安裝完成"
echo ""
echo "  UI:   http://argo.local:30080"
echo "        （需先在 /etc/hosts 加入 127.0.0.1 argo.local）"
echo ""
echo "  列出 WorkflowTemplates:"
echo "    kubectl -n argo get workflowtemplates"
echo ""
echo "  手動觸發 Pipeline:"
echo "    argo submit --from workflowtemplate/presit-pipeline -n argo --watch"
echo ""
echo "  追蹤 Workflow 執行:"
echo "    argo watch -n argo @latest"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
