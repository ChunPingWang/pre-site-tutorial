# Pre-SIT 容器化數據庫驗證工作計畫書（v2.0）

**文件版本**: v2.0  
**建立日期**: 2026年5月16日  
**最後更新**: 2026年5月16日  
**負責部門**: 應用架構團隊  
**變更說明**: 整合 BDD（Gherkin → Step Definition → K8s Job）完整驗證流程  

---

## 1. 項目概述

### 1.1 背景與問題

SIT 環境數據庫狀況通常不可控，導致自動化測試無法穩定執行。本方案在應用部署至 SIT **之前**，以容器化數據庫搭配 BDD 自動化驗證，建立一道品質閘門。

| 問題 | 影響 | 本方案對策 |
|------|------|-----------|
| SIT 數據庫狀態不可控 | 測試不可重複 | 容器化 DB + InitContainer 每次重建 |
| 缺陷在 SIT 才被發現 | 修復成本高 | Pre-SIT Phase 1-4 提前攔截 |
| 驗證結果難以追溯 | 無法量化品質 | Gherkin 場景 → Cucumber 報告 → Go/No-Go JSON |
| 測試與需求脫節 | 覆蓋盲區 | 業務語言撰寫場景，技術語言實現步驟 |

### 1.2 技術棧

| 組件 | 技術 | 用途 |
|------|------|------|
| 測試標的 | Spring PetClinic Microservices | 4 個微服務 + API Gateway |
| 容器平台 | Kind + Kubernetes | 本地 K8s 集群 |
| 鏡像倉庫 | Docker Registry (localhost:5000) | 自建私有倉庫 |
| 部署工具 | ArgoCD | GitOps 自動同步 |
| BDD 框架 | Cucumber + Gherkin (zh-TW) | 行為驅動測試 |
| 測試引擎 | JUnit 5 + AssertJ | 執行與斷言 |
| DB 驗證 | JDBC + PreparedStatement | Schema / Data 驗證 |
| API 驗證 | Java HttpClient | REST 端點測試 |

---

## 2. 整體架構與流程

### 2.1 端到端流程總覽

```
Git Push
  │
  ├─→ Docker Build ──→ Local Registry (localhost:5000)
  │     • presit-bdd-runner:latest     (測試鏡像)
  │     • petclinic-app:latest         (應用鏡像)
  │     • db-init:latest               (DB 初始化鏡像)
  │
  └─→ ArgoCD Webhook ──→ Sync K8s Manifests
                              │
                              ↓  PostSync Hook
                    ┌─────────────────────────────┐
                    │  Kind Cluster (pre-sit NS)  │
                    │                             │
                    │  PostgreSQL StatefulSet      │
                    │    └─ InitContainer: DDL     │
                    │                             │
                    │  PetClinic Deployments       │
                    │    ├─ customers-service      │
                    │    ├─ vets-service           │
                    │    ├─ visits-service         │
                    │    └─ api-gateway            │
                    │                             │
                    │  Validation Jobs (BDD)       │
                    │    Phase 1 → 2 → 3 → 4      │
                    │         ↓                   │
                    │    Cucumber Report           │
                    │    Go/No-Go Decision         │
                    └─────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ↓                               ↓
        ✅ GO → SIT                    ❌ NO-GO → 修復
```

### 2.2 Gherkin → Script → K8s Job 對應關係

```
工作計劃階段           Gherkin Feature                Step Definition                K8s Job                    Maven Profile
─────────────        ─────────────────             ──────────────────            ──────────────              ─────────────
Phase 1 DB層    →  01_database_layer.feature    →  DatabaseLayerSteps.java    →  presit-phase1-database    →  -P phase-1
Phase 2 應用層  →  02_application_layer.feature →  ApplicationIntegration     →  presit-phase2-application →  -P phase-2
Phase 3 集成    →  03_integration_test.feature  →  Steps.java                 →  presit-phase3-integration →  -P phase-3
Phase 4 E2E     →  04_e2e_go_nogo.feature       →  (同上)                     →  presit-phase4-e2e         →  -P phase-4
```

### 2.3 Phase 串接機制

```
Phase 1 Job                   Phase 2 Job                    Phase 3 Job                    Phase 4 Job
┌────────────────┐           ┌────────────────┐            ┌────────────────┐            ┌────────────────┐
│ init: wait-db  │           │ init: wait-P1  │            │ init: wait-P2  │            │ init: wait-P3  │
│   nc -z :5432  │           │ init: wait-app │            │                │            │                │
│                │  complete  │                │  complete   │                │  complete   │                │
│ run: mvn test  │──────────→│ run: mvn test  │───────────→│ run: mvn test  │───────────→│ run: mvn test  │
│   -P phase-1   │           │   -P phase-2   │            │   -P phase-3   │            │   -P phase-4   │
└────────────────┘           └────────────────┘            └────────────────┘            └────────┬───────┘
                                                                                                  │
                                                                                                  ↓
                                                                                        presit-decision.json
                                                                                        ✅ GO / ❌ NO-GO
```

---

## 3. 專案結構

```
presit-bdd-demo/
│
│  ── Gherkin 場景（業務語言，BA/QA 可直接閱讀與維護）──
├── features/
│   ├── database/
│   │   └── 01_database_layer.feature      Phase 1: DDL / DML / 約束 / 索引 / 引用完整性
│   ├── application/
│   │   └── 02_application_layer.feature   Phase 2: Pod 狀態 / Health / 連線池 / 日誌
│   ├── integration/
│   │   └── 03_integration_test.feature    Phase 3: Owner/Pet/Visit CRUD / 跨服務 / 邊界值
│   └── e2e/
│       └── 04_e2e_go_nogo.feature         Phase 4: 端到端流程 / 性能基準 / Go-NoGo
│
│  ── Step Definition（技術實現，Developer 維護）──
├── step-definitions/
│   ├── DatabaseLayerSteps.java            JDBC 連線 + SQL 驗證
│   └── ApplicationIntegrationSteps.java   HttpClient + kubectl + 性能量測
│
│  ── 測試引擎 ──
├── runners/
│   └── PreSitTestRunner.java              JUnit 5 + Cucumber 入口
├── pom.xml                                Maven 依賴 + Phase Profile
│
│  ── 部署與執行 ──
├── scripts/
│   └── run-presit.sh                      本地全流程編排腳本
├── k8s/
│   └── presit-validation-jobs.yaml        4 個 Phase Job + RBAC + Secret
├── Dockerfile                             BDD Runner 多階段建構
│
└── docs/
    └── guide.md                           Gherkin → Script 完整指南
```

---

## 4. 各 Phase 工作內容

### Phase 1：數據庫層驗證

**目的**：確認容器化 PostgreSQL 經 InitContainer 執行 DDL 後，Schema 與測試數據完全正確。

**Gherkin 場景一覽**：

| # | 場景名稱 | Tag | 驗證內容 |
|---|---------|-----|---------|
| 1 | 核心業務表已正確建立 | `@ddl @smoke` | 7 張表存在，欄位數正確 |
| 2 | owners 表欄位定義正確 | `@ddl @columns` | 欄位名 / 型別 / nullable / 長度 |
| 3 | pets 表欄位定義正確 | `@ddl @columns` | 同上 |
| 4 | 所有業務表的主鍵約束正確 | `@ddl @primary-key` | 6 張表的 PK |
| 5 | 外鍵關係正確建立 | `@ddl @foreign-key` | 5 組 FK 關係 |
| 6 | 查詢效能索引已建立 | `@ddl @indexes` | 3 個自定義索引 |
| 7 | 測試數據筆數符合預期 | `@dml @smoke` | 7 張表最低筆數 |
| 8 | pets 引用完整性 | `@dml @referential-integrity` | 無孤立寵物記錄 |
| 9 | visits 引用完整性 | `@dml @referential-integrity` | 無孤立就診記錄 |
| 10 | 標準測試數據內容正確 | `@dml @sample-data` | George Franklin 欄位值比對 |
| 11 | 自增序列正常運作 | `@ddl @sequences` | INSERT RETURNING id > 0，再 DELETE |

**Gherkin → Step 範例**：

```gherkin
# Feature (業務語言)
@ddl @critical @smoke
場景大綱: 核心業務表已正確建立
  當 我查詢 information_schema.tables 中 schema "public" 的表清單
  那麼 表 "<table_name>" 應該存在
  並且 表 "<table_name>" 的欄位數量應為 <column_count>

  例子:
    | table_name | column_count |
    | owners     | 5            |
    | pets       | 5            |
```

```java
// Step Definition (技術實現)
@那麼("表 {string} 應該存在")
public void table_should_exist(String tableName) throws SQLException {
    String sql = "SELECT COUNT(*) FROM information_schema.tables "
               + "WHERE table_schema = 'public' AND table_name = ?";
    try (PreparedStatement ps = connection.prepareStatement(sql)) {
        ps.setString(1, tableName);
        try (ResultSet rs = ps.executeQuery()) {
            rs.next();
            assertThat(rs.getInt(1)).as("表 '%s' 應存在", tableName).isEqualTo(1);
        }
    }
}
```

```yaml
# K8s Job (執行環境)
apiVersion: batch/v1
kind: Job
metadata:
  name: presit-phase1-database
  annotations:
    argocd.argoproj.io/hook: PostSync
spec:
  template:
    spec:
      initContainers:
      - name: wait-for-db
        command: ['sh', '-c', 'until nc -z postgres-service 5432; do sleep 2; done']
      containers:
      - name: bdd-runner
        image: localhost:5000/presit-bdd-runner:latest
        command: ['mvn', 'test', '-P', 'phase-1']
        envFrom:
        - secretRef:
            name: presit-db-credentials
```

---

### Phase 2：應用層驗證

**目的**：確認所有微服務 Pod 正常啟動、通過 Health Check、數據庫連線池就緒。

**Gherkin 場景一覽**：

| # | 場景名稱 | Tag | 驗證內容 |
|---|---------|-----|---------|
| 1 | 微服務 Pod 成功啟動 | `@startup @smoke` | 4 Pod Running, restartCount=0 |
| 2 | 微服務資源使用量合理 | `@startup @resource` | CPU < 80%, MEM < 512MB |
| 3 | 健康檢查端點回應正常 | `@health @smoke` | /actuator/health → 200, "UP" |
| 4 | 數據庫健康指標正常 | `@health @db-indicator` | components.db.status = "UP" |
| 5 | 連線池初始化成功 | `@connection-pool` | 活躍 > 0, 等待 = 0 |
| 6 | 啟動日誌中不包含錯誤 | `@logs` | 無 ERROR, 有 "Started" |
| 7 | K8s Service 端點解析正常 | `@k8s-service` | 5 個 Service 有就緒 Endpoint |

**K8s Job 依賴**：

```yaml
initContainers:
- name: wait-for-phase1
  command: ['kubectl', 'wait', '--for=condition=complete', 'job/presit-phase1-database', '-n', 'pre-sit']
- name: wait-for-apps
  command: ['sh', '-c', 'for svc in customers-service vets-service visits-service api-gateway; do kubectl wait --for=condition=Ready pod -l app=$svc -n pre-sit; done']
```

---

### Phase 3：功能與集成驗證

**目的**：透過 API Gateway 驗證完整的 CRUD 操作、跨服務調用、邊界值與異常處理。

**Gherkin 場景一覽**：

| # | 場景名稱 | Tag | 驗證內容 |
|---|---------|-----|---------|
| 1 | 查詢所有 Owner 列表 | `@api @owners @smoke` | GET /owners → 200, 陣列 |
| 2 | 根據 ID 查詢 Owner | `@api @owners` | GET /owners/1 → George Franklin |
| 3 | 新增 Owner 並驗證 | `@api @owners` | POST → 201, GET 回查 |
| 4 | 更新 Owner 資訊 | `@api @owners` | PUT → 204, GET 驗證新值 |
| 5 | 為 Owner 新增 Pet | `@api @pets` | POST → 201, Owner.pets 包含 |
| 6 | 查詢 Pet Type 清單 | `@api @pets` | 6 種寵物類型 |
| 7 | 建立就診記錄（跨服務） | `@cross-service @critical` | visits-service ↔ customers-service |
| 8 | 查詢獸醫列表 | `@api @vets` | 包含 specialties |
| 9 | 查詢不存在的 Owner | `@error-handling` | → 404 |
| 10 | 缺少必填欄位 | `@error-handling` | → 400 或 422 |
| 11 | 欄位超過最大長度 | `@error-handling` | 非 200/201 |
| 12 | 清理測試數據 | `@cleanup` | 恢復測試前狀態 |

**跨服務調用驗證路徑**：

```
POST /api/visit/owners/1/pets/1/visits
         │
         ↓
  API Gateway (8080)
         │
    ┌────┴────┐
    ↓         ↓
visits-svc  customers-svc
 (8082)       (8081)
    ↓         ↓
visits 表   pets 表 → owners 表
    └────FK────┘       ↑
                  Phase 1 已驗證
```

---

### Phase 4：端到端與 Go/No-Go 決策

**目的**：模擬完整業務流程、測定性能基準線、產出正式驗證報告與部署決策。

**Gherkin 場景一覽**：

| # | 場景名稱 | Tag | 驗證內容 |
|---|---------|-----|---------|
| 1 | 完整寵物看診業務流程 | `@e2e @critical` | 註冊 → 登記寵物 → 就診 → 查詢 → 清理 |
| 2 | API 回應時間基準線 | `@performance` | 3 端點 ×100 次, P95 < 500ms |
| 3 | 並發請求穩定性 | `@performance @concurrent` | 20 並發 30s, 錯誤率 < 1% |
| 4 | ArgoCD 同步狀態 | `@argocd` | Synced + Healthy |
| 5 | 彙整結果與決策 | `@go-nogo @critical` | 通過率 ≥ 95% 且無 critical 失敗 → GO |

**決策規則**：

| 條件 | 決策 |
|------|------|
| 4 Phase 全部通過 且 無 `@critical` 場景失敗 | ✅ GO — 部署至 SIT |
| 任何 Phase 失敗 或 任何 `@critical` 場景失敗 | ❌ NO-GO — 修復後重新驗證 |
| Phase 1 失敗 | ❌ NO-GO 且後續 Phase 不執行 |

---

## 5. 實施時間表

### 5.1 總覽甘特圖

```
Week     1         2         3         4         5         6
        ├─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
Stage 1 │████████████████████│         │         │         │         │  環境搭建
Stage 2 │         │█████████████████████         │         │         │  DB 層 + Feature
Stage 3 │         │         │█████████████████████         │         │  App 層 + Feature
Stage 4 │         │         │         │█████████████████████         │  GitOps + 整合
Stage 5 │         │         │         │         │█████████████████████  驗收 + 移交
```

### 5.2 階段明細

#### Stage 1：環境搭建（Week 1-2）

| # | 任務 | 負責角色 | 工時 | 交付物 |
|---|------|---------|------|--------|
| 1.1 | Kind 集群搭建 + 網路配置 | DevOps | 8h | 可用集群 |
| 1.2 | Local Registry 部署 + Kind 節點對接 | DevOps | 6h | localhost:5000 可推拉 |
| 1.3 | ArgoCD 安裝 + RBAC 配置 | DevOps | 6h | ArgoCD Dashboard |
| 1.4 | Git 倉庫結構建立 | Architect | 4h | 倉庫 + 分支策略 |
| 1.5 | Maven BDD 專案初始化 | Developer | 4h | pom.xml + Runner |
| 1.6 | 環境煙霧測試 | QA | 4h | 環境驗收報告 |

#### Stage 2：數據庫層 + Phase 1 Feature（Week 2-3）

| # | 任務 | 負責角色 | 工時 | 交付物 |
|---|------|---------|------|--------|
| 2.1 | 分析 PetClinic DB Schema | DBA | 6h | Schema 文檔 |
| 2.2 | 編寫 DDL 腳本（01-schema.sql） | DBA | 8h | DDL 檔案 |
| 2.3 | 編寫 DML 腳本（02-sample-data.sql） | QA | 8h | 測試數據檔案 |
| 2.4 | 編寫驗證腳本（03-validation.sql） | DBA | 4h | 驗證 SQL |
| 2.5 | **撰寫 01_database_layer.feature** | QA + BA | 8h | 11 個 Gherkin 場景 |
| 2.6 | **實現 DatabaseLayerSteps.java** | Developer | 12h | Step Definition |
| 2.7 | 構建 DB Docker Image + K8s Manifest | DevOps | 6h | StatefulSet + ConfigMap |
| 2.8 | Phase 1 本地驗證 | QA | 4h | mvn test -P phase-1 通過 |

#### Stage 3：應用層 + Phase 2 & 3 Feature（Week 3-4）

| # | 任務 | 負責角色 | 工時 | 交付物 |
|---|------|---------|------|--------|
| 3.1 | 構建 App Docker Image（多階段） | DevOps | 6h | App 鏡像 |
| 3.2 | 編寫應用 K8s Deployment + Service | DevOps | 8h | 4 Deployment + 4 Service |
| 3.3 | **撰寫 02_application_layer.feature** | QA | 6h | 7 個 Gherkin 場景 |
| 3.4 | **撰寫 03_integration_test.feature** | QA + BA | 10h | 12 個 Gherkin 場景 |
| 3.5 | **實現 ApplicationIntegrationSteps.java** | Developer | 16h | Step Definition |
| 3.6 | Phase 2 & 3 本地驗證 | QA | 6h | mvn test -P phase-2/3 通過 |

#### Stage 4：E2E + GitOps 整合（Week 4-5）

| # | 任務 | 負責角色 | 工時 | 交付物 |
|---|------|---------|------|--------|
| 4.1 | **撰寫 04_e2e_go_nogo.feature** | QA + Architect | 8h | 5 個 Gherkin 場景 |
| 4.2 | 實現 E2E + 性能 + 決策 Steps | Developer | 12h | Step 補充 |
| 4.3 | 編寫 presit-validation-jobs.yaml | DevOps | 8h | 4 Job + RBAC |
| 4.4 | 構建 BDD Runner Docker Image | DevOps | 4h | presit-bdd-runner 鏡像 |
| 4.5 | 編寫 run-presit.sh 編排腳本 | DevOps | 4h | 全流程腳本 |
| 4.6 | ArgoCD Application + PostSync Hook | DevOps | 6h | ArgoCD 配置 |
| 4.7 | 全流程聯調 | All | 8h | Phase 1→2→3→4 串接成功 |

#### Stage 5：驗收與移交（Week 5-6）

| # | 任務 | 負責角色 | 工時 | 交付物 |
|---|------|---------|------|--------|
| 5.1 | 端到端驗收測試 | QA + Architect | 12h | Cucumber 報告 |
| 5.2 | 性能基準線確認 | QA | 8h | 性能指標報告 |
| 5.3 | 問題修復與優化 | Developer + DevOps | 16h | Bug Fix |
| 5.4 | 文檔完善（guide.md + 運維手冊） | Tech Writer | 10h | 完整文檔 |
| 5.5 | 團隊培訓（BDD + K8s + ArgoCD） | Architect | 8h | 培訓記錄 |
| 5.6 | 正式移交 | PM | 4h | 簽核 |

### 5.3 里程碑

| 里程碑 | 時間 | 門檻 |
|--------|------|------|
| M1 環境就緒 | Week 2 | Kind + Registry + ArgoCD 全部運行 |
| M2 Phase 1 通過 | Week 3 | 11 個 DB 場景全部綠燈 |
| M3 Phase 2 & 3 通過 | Week 4 | 19 個應用 + 集成場景全部綠燈 |
| M4 全流程串接 | Week 5 | Phase 1→4 K8s Job 自動串接成功 |
| M5 驗收完成 | Week 6 | 通過率 ≥ 95%，文檔完整，團隊可獨立運作 |

---

## 6. 驗證標準與評分

### 6.1 驗證矩陣

| 驗證層 | Gherkin 場景數 | 涵蓋 Tag | 門檻 |
|--------|-------------|---------|------|
| Phase 1 數據庫層 | 11 | `@ddl @dml @constraints` | 全部通過 |
| Phase 2 應用層 | 7 | `@startup @health @connection-pool` | 全部通過 |
| Phase 3 功能集成 | 12 | `@api @cross-service @error-handling` | ≥ 95% 通過 |
| Phase 4 端到端 | 5 | `@e2e @performance @go-nogo` | critical 全部通過 |
| **合計** | **35** | | **≥ 95% 且無 critical 失敗** |

### 6.2 評分體系（100 分）

| 維度 | 配分 | 評分來源 |
|------|------|---------|
| Phase 1 數據庫層 | 25 分 | 11 場景通過數 / 11 × 25 |
| Phase 2 應用層 | 20 分 | 7 場景通過數 / 7 × 20 |
| Phase 3 功能集成 | 25 分 | 12 場景通過數 / 12 × 25 |
| Phase 4 端到端 | 20 分 | 5 場景通過數 / 5 × 20 |
| 文檔與可維護性 | 10 分 | 人工評審 |

**Go/No-Go 門檻：≥ 80 分 且 @critical 場景 0 失敗**

---

## 7. 風險管理

| 風險 | 概率 | 影響 | 應對策略 |
|------|------|------|---------|
| Kind 集群資源不足 | 中 | 中 | 限制 Pod 資源上限；準備備用雲 K8s |
| DB 版本不兼容 | 低 | 高 | Feature 中用場景大綱覆蓋多版本 |
| DDL/DML 腳本有誤 | 高 | 高 | Phase 1 @smoke 快速攔截；Code Review |
| 團隊 BDD 經驗不足 | 高 | 中 | Stage 5 安排培訓；Gherkin 用中文降低門檻 |
| 測試數據未清理 | 中 | 中 | Phase 3 @cleanup 場景確保還原 |
| Job 串接失敗 | 中 | 高 | initContainer 超時設為 300s；backoffLimit=2 |
| 性能基準線過嚴 | 中 | 低 | Phase 4 先建立基準再逐步收斂 |

---

## 8. 執行指令速查

```bash
# ─── 本地開發 ──────────────────────────────
mvn test -P smoke                          # Smoke Test（2 分鐘）
mvn test -P phase-1                        # 只跑 Phase 1
mvn test -Dcucumber.filter.tags="@critical" # 只跑 Critical

# ─── 全流程 ───────────────────────────────
./scripts/run-presit.sh --all              # Phase 1→2→3→4 + Go/No-Go

# ─── 容器化執行 ──────────────────────────
docker build -t localhost:5000/presit-bdd-runner:latest .
docker push localhost:5000/presit-bdd-runner:latest
kubectl apply -f k8s/presit-validation-jobs.yaml
kubectl logs job/presit-phase4-e2e-decision -n pre-sit -f

# ─── 報告提取 ─────────────────────────────
kubectl cp pre-sit/presit-phase4-e2e-decision:/reports ./local-reports
```

---

## 9. 批准與簽署

| 角色 | 姓名 | 簽署 | 日期 |
|------|------|------|------|
| 項目經理 | | _____ | _____ |
| 應用架構師 | | _____ | _____ |
| QA 主管 | | _____ | _____ |
| IT 部門主管 | | _____ | _____ |

---

**文件版本歷史**

| 版本 | 日期 | 變更說明 |
|------|------|---------|
| v1.0 | 2026-05-16 | 初始版本 |
| v2.0 | 2026-05-16 | 整合 BDD 完整流程（Gherkin → Step → Job），重構 Phase 定義與時間表 |
