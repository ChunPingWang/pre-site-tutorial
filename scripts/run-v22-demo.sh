#!/usr/bin/env bash
# v2.2 Stage H: 端到端 demo 腳本
#
# 走完整條 v2.2 鏈：
#   1. (假設環境已啟動 — Kind + ArgoCD + nginx-ingress + Image Updater 等)
#   2. Build PetClinic 4 service + BDD runner image，tag :sha-${SHA}-h, :v2.2
#   3. Push 到 local registry
#   4. Pre-SIT 重啟服務套用新 image
#   5. 跑 4 phase BDD，等綠燈
#   6. Promote: retag :sit-approved
#   7. Argo Image Updater 偵測 → SIT AutoSync 更新
#   8. 等 SIT pod 切到 :sit-approved
#   9. 從 ingress 驗 SIT 仍正常
#  10. 蒐集證據 → evidence/${SHA}/INDEX.md
#  11. 模擬使用者測試發現「Bug」並建立對應的 GitHub Issue 模板填寫範例

set -euo pipefail

ROOT="$(dirname "$0")/.."
cd "${ROOT}"

SHA=$(git rev-parse --short HEAD)
RUNTAG="sha-${SHA}-h"
echo "[demo] SHA=${SHA}, image tag=${RUNTAG}"

# ─── Step 1-3: Build + Push ─────────────────────
echo "[demo] Step 1-3: Build PetClinic + BDD runner image"
(cd petclinic-src && ./mvnw -B package -DskipTests 2>&1 | tail -3)

for svc in customers-service vets-service visits-service api-gateway; do
  TAG="localhost:5000/petclinic-${svc}:${RUNTAG}"
  docker build -t "${TAG}" "petclinic-src/spring-petclinic-${svc}" 2>&1 | tail -1
  docker push "${TAG}" 2>&1 | tail -1
  # Tag :v2.2 (Pre-SIT 用的 mutable label)
  docker tag "${TAG}" "localhost:5000/petclinic-${svc}:v2.2"
  docker push "localhost:5000/petclinic-${svc}:v2.2" 2>&1 | tail -1
done

(cd presit-bdd-demo/poc-v2.2 && docker build -t "localhost:5000/presit-bdd-runner:v2.2" . 2>&1 | tail -1)
docker push "localhost:5000/presit-bdd-runner:v2.2" 2>&1 | tail -1

# ─── Step 4: Pre-SIT 套用新 image ────────────────
echo "[demo] Step 4: Pre-SIT rollout new image"
kubectl -n pre-sit delete pod postgres-0 --ignore-not-found >/dev/null 2>&1
kubectl -n pre-sit wait --for=condition=Ready pod/postgres-0 --timeout=120s
kubectl -n pre-sit rollout restart deployment customers-service vets-service visits-service api-gateway >/dev/null
kubectl -n pre-sit wait --for=condition=Available deployment --all --timeout=300s

# ─── Step 5: 跑 4 Phase BDD ─────────────────────
echo "[demo] Step 5: Pre-SIT 4 phase BDD"
kubectl delete jobs -n pre-sit -l app=presit-validation --ignore-not-found >/dev/null 2>&1
kubectl delete pvc presit-reports -n pre-sit --ignore-not-found >/dev/null 2>&1
kubectl apply -f manifests/pre-sit/30-bdd-jobs.yaml >/dev/null

# 等 Phase 4 完成（不論成敗）
kubectl wait --for=condition=complete --for=condition=failed \
  job/presit-phase4-e2e-decision -n pre-sit --timeout=1800s || true

# 確認 decision
DECISION=$(kubectl logs job/presit-phase4-e2e-decision -n pre-sit 2>/dev/null \
  | grep -oE 'decision":"[^"]+' | head -1 | cut -d'"' -f3 || echo "UNKNOWN")
echo "[demo] Pre-SIT decision: ${DECISION}"

if [[ "${DECISION}" != *"GO"* ]]; then
  echo "[demo] ❌ Pre-SIT 未通過 (decision=${DECISION})，不 promote"
  echo "[demo] 蒐集失敗證據..."
  bash scripts/collect-evidence.sh "${SHA}"
  exit 1
fi

# ─── Step 6: Promote — retag :sit-approved ─────
echo "[demo] Step 6: Promote — retag :sit-approved"
for svc in customers-service vets-service visits-service api-gateway; do
  docker tag "localhost:5000/petclinic-${svc}:${RUNTAG}" \
            "localhost:5000/petclinic-${svc}:sit-approved"
  docker push "localhost:5000/petclinic-${svc}:sit-approved" 2>&1 | tail -1
done

# ─── Step 7-8: 等 SIT 自動更新 ──────────────────
echo "[demo] Step 7-8: 等 Argo Image Updater 偵測 + SIT AutoSync"
# 觸發 Image Updater 立即 poll
kubectl -n argocd rollout restart deployment argocd-image-updater >/dev/null
kubectl -n argocd wait --for=condition=Available deployment/argocd-image-updater --timeout=120s

# 等 SIT customers deployment 出現 sit-approved tag (image-updater patch 完)
echo "[demo] 等 sit-approved 套用..."
for i in $(seq 1 60); do
  CURRENT=$(kubectl -n sit get deployment customers-service \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
  if [[ "${CURRENT}" == *sit-approved* ]]; then
    echo "[demo] SIT customers-service 已切到 :sit-approved"
    break
  fi
  sleep 10
done

# 確認 4 deployment 都更新
for d in customers-service vets-service visits-service api-gateway; do
  kubectl -n sit rollout status deployment "${d}" --timeout=300s || true
done

# ─── Step 9: 從 ingress 驗 SIT ──────────────────
echo "[demo] Step 9: 從 ingress 驗 SIT"
RESP=$(curl -s -H 'Host: sit.local' http://localhost:30080/api/customer/owners/1 || echo "{}")
NAME=$(echo "${RESP}" | python3 -c "import sys,json; d=json.loads(sys.stdin.read() or '{}'); print(d.get('firstName','?')+' '+d.get('lastName','?'))" 2>/dev/null)
echo "[demo] SIT GET /owners/1 → ${NAME}"

# Verify 404 handler 也在 SIT 生效
RC404=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: sit.local' http://localhost:30080/api/customer/owners/99999 || echo "0")
echo "[demo] SIT GET /owners/99999 → HTTP ${RC404} (expected 404)"

# ─── Step 10: 蒐集證據 ──────────────────────────
echo "[demo] Step 10: 蒐集證據"
bash scripts/collect-evidence.sh "${SHA}"

# ─── Step 11: 模擬 bug workflow ─────────────────
echo "[demo] Step 11: 模擬 SIT 探索性測試發現 bug → 對應 Issue 模板"
cat <<'BUG_EXAMPLE'
─────────────────────────────────────────────────────────────
  📝 假想場景: SIT 使用者 testQA 探索 PetClinic 時發現

    步驟 1: 訪問 http://sit.local:30080/owners
    步驟 2: 點 "Add Owner"
    步驟 3: 留 firstName 空白、其他都填、按 Submit
    預期: 顯示「First Name 必填」錯誤訊息
    實際: API 回 400 但 UI 沒顯示對應錯誤、看起來像卡住

  → 應該開 GitHub Issue 使用 .github/ISSUE_TEMPLATE/sit-exploration-bug.yml
  → 候選 Gherkin (附 issue 一起提)：

    @api @error-handling @from-sit-${ISSUE_NUMBER}
    場景: 新增 Owner 缺 firstName 時前端應顯示驗證錯誤
      當 我在 http://sit.local:30080/owners/new 留空 firstName 並 submit
      那麼 表單上方應出現 "First Name is required"
      並且 表單不應提交到後端
─────────────────────────────────────────────────────────────
BUG_EXAMPLE

echo "[demo] ✅ 端到端 v2.2 demo 完成"
echo "[demo] 證據: evidence/${SHA}/INDEX.md"
