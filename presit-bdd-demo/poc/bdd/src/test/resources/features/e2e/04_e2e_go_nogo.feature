# language: zh-TW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pre-SIT Phase 4：端到端驗證與 Go/No-Go 決策門檻
# 對應工作計劃：第四、五階段 — GitOps 整合 + 驗收測試
# 驗證項目：完整流程 → 性能基準 → 報告產出 → 上線決策
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@pre-sit @phase-4 @e2e
功能: Pre-SIT 端到端驗證與 Go/No-Go 決策
  作為 應用架構師
  我希望 執行一個模擬真實使用的端到端流程
  以便 產出正式的驗證報告並做出是否部署至 SIT 的決策

  背景:
    假設 Phase 1 數據庫層驗證已通過
    並且 Phase 2 應用層驗證已通過
    並且 Phase 3 功能與集成驗證已通過

  # ─── 端到端業務場景 ────────────────────────────
  @e2e @business-flow @critical
  場景: 完整的寵物看診業務流程
    # Step 1: 註冊新飼主
    當 新飼主 "王小明" 透過 API 註冊，資訊如下:
      | field     | value        |
      | firstName | 小明         |
      | lastName  | 王           |
      | address   | 台北市信義區 |
      | city      | Taipei       |
      | telephone | 0912000111   |
    那麼 註冊應成功並取得飼主 ID

    # Step 2: 登記寵物
    當 為該飼主登記一隻寵物，資訊如下:
      | field     | value      |
      | name      | 小花       |
      | birthDate | 2023-06-01 |
      | typeId    | 1          |
    那麼 寵物登記應成功並取得寵物 ID

    # Step 3: 建立就診記錄
    當 為該寵物建立就診記錄:
      | field       | value                |
      | date        | 2026-05-16           |
      | description | E2E 自動化驗證就診   |
    那麼 就診記錄應成功建立

    # Step 4: 完整查詢驗證
    當 我查詢該飼主的完整資料
    那麼 飼主姓名應為 "王 小明"
    並且 應擁有 1 隻寵物名為 "小花"
    並且 該寵物應有 1 筆就診記錄

    # Step 5: 清理
    當 我清理本場景建立的所有數據
    那麼 清理應成功

  # ─── 性能基準線驗證 ────────────────────────────
  @performance @baseline
  場景: API 回應時間在可接受範圍內
    當 我對以下端點各發送 100 次 GET 請求並記錄回應時間:
      | endpoint                      |
      | /api/customer/owners           |
      | /api/vet/vets                  |
      | /api/customer/owners/1         |
    那麼 所有端點的 P95 回應時間應低於 500 毫秒
    並且 所有端點的 P99 回應時間應低於 1000 毫秒
    並且 所有請求的成功率應達 99% 以上

  @performance @concurrent
  場景: 並發請求下系統保持穩定
    當 我以 20 個並發執行緒對 "/api/customer/owners" 發送 GET 請求，持續 30 秒
    那麼 錯誤率應低於 1%
    並且 平均回應時間應低於 300 毫秒
    並且 Pod 不應發生 OOMKilled 或 CrashLoopBackOff

  # ─── ArgoCD 部署狀態驗證 ────────────────────────
  @argocd @gitops
  場景: ArgoCD 應用同步狀態正常
    當 我查詢 ArgoCD 應用 "petclinic-pre-sit" 的狀態
    那麼 同步狀態 (Sync Status) 應為 "Synced"
    並且 健康狀態 (Health Status) 應為 "Healthy"
    並且 所有資源的同步結果應為 "SyncOK"

  # ─── Go/No-Go 決策門檻 ─────────────────────────
  @decision @go-nogo @critical
  場景: 彙整驗證結果並產出決策報告
    假設 所有 Phase 的測試結果如下:
      | phase                  | tag          | total | passed | failed |
      | Phase 1 數據庫層       | @phase-1     |       |        |        |
      | Phase 2 應用層         | @phase-2     |       |        |        |
      | Phase 3 功能與集成     | @phase-3     |       |        |        |
      | Phase 4 端到端         | @phase-4     |       |        |        |
    當 系統計算總通過率
    那麼 若通過率 >= 95% 且無 @critical 場景失敗，決策為 "GO ✅"
    並且 否則決策為 "NO-GO ❌"
    並且 系統應產出 JSON 格式驗證報告至 "/reports/presit-report.json"
    並且 系統應產出 HTML 格式驗證報告至 "/reports/presit-report.html"
