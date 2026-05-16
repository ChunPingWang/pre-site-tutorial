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

echo "  等待 argo-workflows-server 就緒..."
kubectl -n argo wait deployment argo-workflows-server \
  --for=condition=Available --timeout=120s 2>/dev/null || true

kubectl apply -f "${MANIFESTS}/30-ingress.yaml"
echo "  ✅ Ingress 套用完成"

# ── Step 4.5: UI Screenshot 資源（ConfigMap + Report Server）────────────────
echo "[4.5/5] 套用 UI 截圖 ConfigMap + Report Server（presit-report.local）"
# pre-sit namespace 可能尚未存在（由 ArgoCD 管理），等待後再 apply
if kubectl get namespace pre-sit &>/dev/null; then
  kubectl apply -f "${ROOT}/manifests/pre-sit/40-ui-screenshot.yaml"
  echo "  ✅ UI 截圖資源套用完成"
else
  echo "  ⚠️  pre-sit namespace 尚未就緒，跳過（ArgoCD sync 後可手動執行）:"
  echo "       kubectl apply -f manifests/pre-sit/40-ui-screenshot.yaml"
fi

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
echo "  Argo Workflows UI:  http://argo.local:30080"
echo "  UI Screenshot 報告: http://presit-report.local:30080/ui-screenshots/index.html"
echo ""
echo "  /etc/hosts（一次加入）:"
echo "    sudo tee -a /etc/hosts <<<'127.0.0.1 argo.local presit-report.local'"
echo ""
echo "  手動觸發 Pipeline:"
echo "    kubectl create -f - <<'EOF'"
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
echo "  追蹤執行:"
echo "    kubectl -n argo get workflows -w"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
