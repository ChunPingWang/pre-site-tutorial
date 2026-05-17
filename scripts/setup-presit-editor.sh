#!/usr/bin/env bash
# 部署 Pre-SIT Gherkin Editor
#
# 前提：
#   - Kind presit 叢集已就緒（bash scripts/setup-v23.sh 已執行）
#   - GITHUB_TOKEN 環境變數已設定（需有 repo scope）
#
# 用法：
#   export GITHUB_TOKEN="ghp_xxxx"
#   bash scripts/setup-presit-editor.sh

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
step() { echo -e "\n${CYAN}━━ $* ━━${RESET}"; }
ok()   { echo -e "${GREEN}  ✅ $*${RESET}"; }

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "錯誤：請先設定 GITHUB_TOKEN 環境變數" >&2
  echo "  export GITHUB_TOKEN=\"ghp_xxxx\"" >&2
  exit 1
fi

# ── Step 1: Build & push image ───────────────────────────────────────────────
step "Step 1/4: Build presit-editor image"
docker build -q -t localhost:5000/presit-editor:v1 "${ROOT}/presit-editor"
docker push localhost:5000/presit-editor:v1 > /dev/null
ok "Image pushed to localhost:5000/presit-editor:v1"

# ── Step 2: Create GitHub token Secret ──────────────────────────────────────
step "Step 2/4: 建立 GitHub Token Secret"
kubectl create secret generic presit-editor-git \
  --namespace pre-sit \
  --from-literal=GITHUB_TOKEN="${GITHUB_TOKEN}" \
  --from-literal=GIT_USER="presit-editor" \
  --from-literal=GIT_EMAIL="presit-editor@presit.local" \
  --dry-run=client -o yaml | kubectl apply -f -
ok "Secret presit-editor-git 就緒"

# ── Step 3: Apply manifests ──────────────────────────────────────────────────
step "Step 3/4: 套用 K8s manifests"
kubectl apply -f "${ROOT}/manifests/presit-editor/05-rbac.yaml"
kubectl apply -f "${ROOT}/manifests/presit-editor/10-deployment.yaml"
kubectl apply -f "${ROOT}/manifests/presit-editor/15-service.yaml"
kubectl apply -f "${ROOT}/manifests/presit-editor/20-ingress.yaml"
ok "Manifests 套用完成"

# ── Step 4: Wait for ready ───────────────────────────────────────────────────
step "Step 4/4: 等待 presit-editor 就緒"
kubectl rollout status deployment/presit-editor -n pre-sit --timeout=120s
ok "presit-editor 就緒"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Pre-SIT Gherkin Editor 安裝完成！"
echo ""
echo "  訪問：http://presit-editor.local:30080"
echo ""
echo "  /etc/hosts（如尚未加入）："
echo "    echo '127.0.0.1 presit-editor.local' | sudo tee -a /etc/hosts"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
