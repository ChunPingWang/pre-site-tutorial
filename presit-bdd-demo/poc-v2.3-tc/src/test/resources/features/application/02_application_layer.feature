# language: zh-TW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pre-SIT Phase 2：應用層驗證
# 對應工作計劃：第三階段 — 應用層與驗證層設計
# 驗證項目：容器啟動 → 健康檢查 → DB連線 → API可用性
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@pre-sit @phase-2 @application
功能: Pre-SIT 應用層驗證
  作為 DevOps 工程師
  我希望 確認所有微服務 Pod 正常啟動且連接數據庫成功
  以便 保證應用層在進入功能測試前處於健康狀態

  背景:
    假設 Kind 集群 "pre-sit" 命名空間中所有 Pod 狀態為 Running
    並且 Phase 1 數據庫層驗證已通過

  # ─── 容器啟動驗證 ──────────────────────────────
  @startup @smoke @critical
  場景大綱: 微服務 Pod 成功啟動
    當 我查詢 Pod "<pod_prefix>" 的狀態
    那麼 Pod 狀態應為 "Running"
    並且 重啟次數應為 0
    並且 所有容器應處於 "Ready" 狀態

    例子:
      | pod_prefix        |
      | customers-service |
      | vets-service      |
      | visits-service    |
      | api-gateway       |

  @startup @resource
  場景大綱: 微服務資源使用量在合理範圍
    當 我查詢 Pod "<pod_prefix>" 的資源使用情況
    那麼 CPU 使用率應低於 <cpu_limit_percent>%
    並且 記憶體使用量應低於 <mem_limit_mb> MB

    # v2.1: 512MB → 768MB（Spring Boot 3.2 + Cloud Config + Eureka 啟動穩態 500-530 MiB）
    例子:
      | pod_prefix        | cpu_limit_percent | mem_limit_mb |
      | customers-service | 80                | 768          |
      | vets-service      | 80                | 768          |
      | visits-service    | 80                | 768          |
      | api-gateway       | 80                | 768          |

  # ─── 健康檢查端點驗證 ─────────────────────────
  @health @smoke @critical
  場景大綱: 微服務健康檢查端點回應正常
    當 我對 "<service_url>/actuator/health" 發送 GET 請求
    那麼 HTTP 狀態碼應為 200
    並且 回應 JSON 的 "status" 欄位應為 "UP"

    例子:
      | service_url                                    |
      | http://customers-service.pre-sit.svc:8081      |
      | http://vets-service.pre-sit.svc:8083           |
      | http://visits-service.pre-sit.svc:8082         |
      | http://api-gateway.pre-sit.svc:8080            |

  @health @db-indicator
  場景大綱: 微服務數據庫健康指標正常 (v2.2: 真連 Postgres)
    當 我對 "<service_url>/actuator/health" 發送 GET 請求
    那麼 回應 JSON 中 "components.db.status" 應為 "UP"
    # v2.2 §1.3 C1 已解：應用真連 PostgreSQL
    並且 回應 JSON 中 "components.db.details.database" 應為 "PostgreSQL"

    例子:
      | service_url                                    |
      | http://customers-service.pre-sit.svc:8081      |
      | http://vets-service.pre-sit.svc:8083           |
      | http://visits-service.pre-sit.svc:8082         |

  # ─── DB 連線池驗證 ─────────────────────────────
  @connection-pool
  場景大綱: 連線池初始化成功且參數正確
    當 我對 "<service_url>/actuator/metrics/hikaricp.connections" 發送 GET 請求
    那麼 HTTP 狀態碼應為 200
    並且 活躍連線數應大於 0
    並且 空閒連線數應大於 0
    並且 等待連線數應為 0

    例子:
      | service_url                                    |
      | http://customers-service.pre-sit.svc:8081      |
      | http://vets-service.pre-sit.svc:8083           |
      | http://visits-service.pre-sit.svc:8082         |

  # ─── 日誌檢查 ──────────────────────────────────
  @logs @startup
  場景大綱: 啟動日誌中不包含錯誤
    當 我讀取 Pod "<pod_prefix>" 的啟動日誌
    那麼 日誌中不應包含 "ERROR" 級別訊息
    並且 日誌中不應包含 "Connection refused"
    並且 日誌中應包含 "Started" 訊息

    例子:
      | pod_prefix        |
      | customers-service |
      | vets-service      |
      | visits-service    |
      | api-gateway       |

  # ─── Service 與 Endpoint 驗證 ──────────────────
  @k8s-service
  場景: K8s Service 端點解析正常
    當 我查詢 "pre-sit" 命名空間中的 Endpoints 資源
    那麼 以下 Service 應擁有至少 1 個就緒端點:
      | service_name      |
      | customers-service |
      | vets-service      |
      | visits-service    |
      | api-gateway       |
      | postgres          |
