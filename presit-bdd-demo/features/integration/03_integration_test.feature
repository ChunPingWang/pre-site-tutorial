# language: zh-TW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pre-SIT Phase 3：功能與集成驗證
# 對應工作計劃：第三階段 — 自動化驗證腳本 + 測試用例
# 驗證項目：CRUD API → 業務邏輯 → 跨服務調用 → 異常處理
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@pre-sit @phase-3 @integration
功能: Pre-SIT 功能與集成驗證
  作為 QA 自動化工程師
  我希望 透過 API Gateway 驗證所有微服務的業務功能
  以便 確保數據庫與應用的端到端流程在 SIT 前完整可用

  背景:
    假設 Phase 1 數據庫層驗證已通過
    並且 Phase 2 應用層驗證已通過
    並且 API Gateway 可透過 "http://api-gateway.pre-sit.svc:8080" 存取

  # ─── Owner CRUD ────────────────────────────────
  @api @owners @crud @smoke
  場景: 查詢所有 Owner 列表
    當 我對 "/api/customer/owners" 發送 GET 請求
    那麼 HTTP 狀態碼應為 200
    並且 回應應為 JSON 陣列
    並且 陣列長度應大於 0

  @api @owners @crud
  場景: 根據 ID 查詢單一 Owner
    假設 已知 Owner ID 為 1
    當 我對 "/api/customer/owners/1" 發送 GET 請求
    那麼 HTTP 狀態碼應為 200
    並且 回應 JSON 應包含:
      | field      | value    |
      | id         | 1        |
      | firstName  | George   |
      | lastName   | Franklin |

  @api @owners @crud
  場景: 新增 Owner 並驗證寫入數據庫
    當 我對 "/api/customer/owners" 發送 POST 請求，Body 為:
      """json
      {
        "firstName": "PreSIT",
        "lastName":  "TestOwner",
        "address":   "100 Test Ave.",
        "city":      "Taipei",
        "telephone": "0911222333"
      }
      """
    那麼 HTTP 狀態碼應為 201
    並且 回應 JSON 的 "id" 欄位應大於 0
    當 我以回應的 ID 對 "/api/customer/owners/{id}" 發送 GET 請求
    那麼 回應 JSON 的 "firstName" 應為 "PreSIT"
    並且 回應 JSON 的 "city" 應為 "Taipei"

  @api @owners @crud
  場景: 更新 Owner 資訊
    假設 已知 Owner ID 為 1
    當 我對 "/api/customer/owners/1" 發送 PUT 請求，Body 為:
      """json
      {
        "id":        1,
        "firstName": "George",
        "lastName":  "Franklin",
        "address":   "Updated Address 999",
        "city":      "Madison",
        "telephone": "6085551023"
      }
      """
    那麼 HTTP 狀態碼應為 204
    當 我對 "/api/customer/owners/1" 發送 GET 請求
    那麼 回應 JSON 的 "address" 應為 "Updated Address 999"

  # ─── Pet CRUD ──────────────────────────────────
  @api @pets @crud
  場景: 為 Owner 新增一隻 Pet
    假設 已知 Owner ID 為 1
    當 我對 "/api/customer/owners/1/pets" 發送 POST 請求，Body 為:
      """json
      {
        "name":      "TestDog",
        "birthDate": "2024-01-15",
        "typeId":    2
      }
      """
    那麼 HTTP 狀態碼應為 201
    當 我對 "/api/customer/owners/1" 發送 GET 請求
    那麼 回應 JSON 的 "pets" 陣列中應包含 name 為 "TestDog" 的記錄

  @api @pets @crud
  場景: 查詢 Pet 的 Type 清單
    當 我對 "/api/customer/petTypes" 發送 GET 請求
    那麼 HTTP 狀態碼應為 200
    並且 回應陣列應包含以下 name:
      | name    |
      | cat     |
      | dog     |
      | lizard  |
      | snake   |
      | bird    |
      | hamster |

  # ─── Visit（跨服務調用）─────────────────────────
  @api @visits @cross-service @critical
  場景: 建立就診記錄（涉及 visits-service 與 customers-service）
    假設 已知 Owner ID 為 1 且 Pet ID 為 1
    當 我對 "/api/visit/owners/1/pets/1/visits" 發送 POST 請求，Body 為:
      """json
      {
        "date":        "2026-05-16",
        "description": "Pre-SIT automated test visit"
      }
      """
    那麼 HTTP 狀態碼應為 201
    當 我對 "/api/customer/owners/1" 發送 GET 請求
    那麼 Owner 的第一隻 Pet 的 visits 中應包含 description 為 "Pre-SIT automated test visit" 的記錄

  # ─── Vet 查詢 ─────────────────────────────────
  @api @vets @read
  場景: 查詢獸醫列表並包含專長
    當 我對 "/api/vet/vets" 發送 GET 請求
    那麼 HTTP 狀態碼應為 200
    並且 回應陣列長度應大於 0
    並且 至少一位獸醫應擁有 specialties 資料

  # ─── 邊界值與異常處理 ──────────────────────────
  @api @error-handling @boundary
  場景: 查詢不存在的 Owner 應返回 404
    當 我對 "/api/customer/owners/99999" 發送 GET 請求
    那麼 HTTP 狀態碼應為 404

  @api @error-handling @validation
  場景: 新增 Owner 缺少必填欄位應返回錯誤
    當 我對 "/api/customer/owners" 發送 POST 請求，Body 為:
      """json
      {
        "firstName": "",
        "lastName":  ""
      }
      """
    那麼 HTTP 狀態碼應為 400 或 422

  @api @error-handling @boundary
  場景: 欄位超過最大長度應返回錯誤
    當 我對 "/api/customer/owners" 發送 POST 請求，Body 為:
      """json
      {
        "firstName": "ThisNameIsWayTooLongToFitInTheColumnDefinedAsVarchar30Characters",
        "lastName":  "Normal",
        "address":   "123 St.",
        "city":      "City",
        "telephone": "12345"
      }
      """
    那麼 HTTP 狀態碼不應為 200 或 201

  # ─── 數據清理 ──────────────────────────────────
  @cleanup @after
  場景: 清理本次測試產生的數據
    當 我刪除所有 firstName 為 "PreSIT" 的 Owner 記錄
    並且 我刪除所有 description 包含 "Pre-SIT automated" 的 Visit 記錄
    那麼 清理操作應全部成功
    並且 數據庫狀態應恢復至測試前
