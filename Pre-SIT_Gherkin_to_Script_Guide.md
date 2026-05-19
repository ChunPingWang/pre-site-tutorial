# Pre-SIT 驗證：從 Gherkin 到自動化腳本的完整演示

**版本**: v1.0 ｜ **日期**: 2026-05-16 ｜ **作者**: Application Architect

---

## 目錄

1. [整體對應關係](#1-整體對應關係)
2. [專案結構](#2-專案結構)
3. [Phase 1：數據庫層 — Gherkin → Step → 執行](#3-phase-1數據庫層)
4. [Phase 2：應用層 — Gherkin → Step → 執行](#4-phase-2應用層)
5. [Phase 3：功能與集成 — Gherkin → Step → 執行](#5-phase-3功能與集成)
6. [Phase 4：端到端與決策 — Gherkin → Step → 執行](#6-phase-4端到端與決策)
7. [執行流程：本地到 K8s Job](#7-執行流程)
8. [報告與 Go/No-Go 決策](#8-報告與決策)

---

## 1. 整體對應關係

從工作計劃書到可執行腳本，每一層都有明確的對應：

```
工作計劃書                    Gherkin Feature              Step Definition           K8s 執行
──────────────              ──────────────              ──────────────           ──────────
第二階段：DB層設計    ──→  01_database_layer.feature  ──→  DatabaseLayerSteps.java  ──→  Job: presit-phase1
第三階段：應用層設計  ──→  02_application_layer.feature──→  ApplicationIntegration   ──→  Job: presit-phase2
第三階段：驗證腳本    ──→  03_integration_test.feature ──→  Steps.java               ──→  Job: presit-phase3
第四五階段：驗收      ──→  04_e2e_go_nogo.feature      ──→                          ──→  Job: presit-phase4
```

### Tag 與 Phase 的對應

| 工作計劃階段 | Gherkin Tag | Maven Profile | K8s Job 名稱 |
|-------------|-------------|---------------|-------------|
| 第二階段 數據庫層 | `@phase-1 @database` | `phase-1` | `presit-phase1-database` |
| 第三階段 應用層 | `@phase-2 @application` | `phase-2` | `presit-phase2-application` |
| 第三階段 集成測試 | `@phase-3 @integration` | `phase-3` | `presit-phase3-integration` |
| 第四五階段 驗收 | `@phase-4 @e2e` | `phase-4` | `presit-phase4-e2e-decision` |
| 快速冒煙 | `@smoke` | `smoke` | — (手動觸發) |
| 關鍵路徑 | `@critical` | — (篩選用) | — |

---

## 2. 專案結構

```
presit-bdd-demo/
│
├── features/                          ← Gherkin 場景（業務語言）
│   ├── database/
│   │   └── 01_database_layer.feature      Phase 1: DDL/DML/約束
│   ├── application/
│   │   └── 02_application_layer.feature   Phase 2: 啟動/健康/連線
│   ├── integration/
│   │   └── 03_integration_test.feature    Phase 3: CRUD/業務邏輯
│   └── e2e/
│       └── 04_e2e_go_nogo.feature         Phase 4: 端到端/決策
│
├── step-definitions/                  ← 步驟實現（技術語言）
│   ├── DatabaseLayerSteps.java            Phase 1 的 JDBC 操作
│   └── ApplicationIntegrationSteps.java   Phase 2-4 的 HTTP/K8s 操作
│
├── runners/                           ← 測試執行器
│   └── PreSitTestRunner.java              JUnit 5 + Cucumber 入口
│
├── scripts/                           ← 自動化腳本
│   └── run-presit.sh                      全流程編排腳本
│
├── k8s/                               ← K8s 資源定義
│   └── presit-validation-jobs.yaml        4 個 Phase Job + RBAC
│
├── Dockerfile                         ← 測試鏡像構建
├── pom.xml                            ← Maven 依賴與 Profile
│
└── docs/
    └── guide.md                       ← 本文檔
```

---

## 3. Phase 1：數據庫層

### 3.1 Gherkin（業務可讀）

```gherkin
# language: zh-TW
@pre-sit @phase-1 @database
功能: Pre-SIT 數據庫層驗證

  背景:
    假設 PostgreSQL 容器已在 Kind 集群的 "pre-sit" 命名空間中運行
    並且 InitContainer 已執行完成

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

### 3.2 Step Definition（技術實現）

```java
@那麼("表 {string} 應該存在")
public void table_should_exist(String tableName) throws SQLException {
    String sql = "SELECT COUNT(*) FROM information_schema.tables "
               + "WHERE table_schema = 'public' AND table_name = ?";
    try (PreparedStatement ps = connection.prepareStatement(sql)) {
        ps.setString(1, tableName);
        try (ResultSet rs = ps.executeQuery()) {
            rs.next();
            assertThat(rs.getInt(1))
                .as("表 '%s' 應存在", tableName)
                .isEqualTo(1);
        }
    }
}
```

### 3.3 執行方式

```bash
# 本地執行
mvn test -P phase-1

# K8s Job 執行（由 ArgoCD PostSync Hook 觸發）
kubectl apply -f k8s/presit-validation-jobs.yaml
kubectl wait --for=condition=complete job/presit-phase1-database -n pre-sit
```

### 3.4 對應架構圖位置

```
Kind Cluster → Database Layer → K8s Job: db-data-loader
                                    ↓
                               ConfigMap: db-init-scripts
                               (01-schema.sql / 02-sample-data.sql)
```

### 3.5 驗證項目覆蓋

| 工作計劃檢查項 | Gherkin 場景 | Tag |
|---------------|-------------|-----|
| 所有表都已創建 | 核心業務表已正確建立 | `@ddl @smoke` |
| 欄位定義正確 | owners/pets 表欄位定義正確 | `@ddl @columns` |
| 主鍵約束已設置 | 所有業務表的主鍵約束正確 | `@ddl @primary-key` |
| 外鍵約束已設置 | 外鍵關係正確建立 | `@ddl @foreign-key` |
| 索引已創建 | 查詢效能索引已建立 | `@ddl @indexes` |
| 測試數據已加載 | 測試數據筆數符合預期 | `@dml @data-loading` |
| 外鍵引用有效 | pets/visits 引用完整性 | `@dml @referential-integrity` |

---

## 4. Phase 2：應用層

### 4.1 Gherkin（業務可讀）

```gherkin
@pre-sit @phase-2 @application
功能: Pre-SIT 應用層驗證

  背景:
    假設 Phase 1 數據庫層驗證已通過

  @startup @smoke @critical
  場景大綱: 微服務 Pod 成功啟動
    當 我查詢 Pod "<pod_prefix>" 的狀態
    那麼 Pod 狀態應為 "Running"
    並且 重啟次數應為 0
```

### 4.2 Step Definition（技術實現）

```java
@當("我查詢 Pod {string} 的狀態")
public void query_pod_status(String podPrefix) throws Exception {
    ProcessBuilder pb = new ProcessBuilder(
        "kubectl", "get", "pods", "-n", "pre-sit",
        "-l", "app=" + podPrefix, "-o", "json"
    );
    Process p = pb.start();
    String json = new String(p.getInputStream().readAllBytes());
    lastJsonBody = mapper.readTree(json);
}
```

### 4.3 K8s Job 依賴鏈

```yaml
initContainers:
- name: wait-for-phase1       # ← 等待前一個 Phase 完成
  command: ["kubectl", "wait", "--for=condition=complete",
            "job/presit-phase1-database", ...]
- name: wait-for-apps         # ← 等待所有應用 Pod Ready
  command: ["kubectl", "wait", "--for=condition=Ready",
            "pod", "-l", "app=customers-service", ...]
```

---

## 5. Phase 3：功能與集成

### 5.1 Gherkin（業務可讀）

```gherkin
@pre-sit @phase-3 @integration
功能: Pre-SIT 功能與集成驗證

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

  @api @visits @cross-service @critical
  場景: 建立就診記錄（涉及 visits-service 與 customers-service）
    ...
```

### 5.2 Step Definition（技術實現）

```java
@當("我對 {string} 發送 POST 請求，Body 為:")
public void send_post_request(String path, String body) throws Exception {
    HttpRequest req = HttpRequest.newBuilder()
        .uri(URI.create(gatewayUrl + path))
        .header("Content-Type", "application/json")
        .POST(HttpRequest.BodyPublishers.ofString(body))
        .build();
    lastResponse = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
    lastJsonBody = mapper.readTree(lastResponse.body());
}
```

### 5.3 跨服務驗證覆蓋

```
                    POST /api/visit/owners/1/pets/1/visits
                              ↓
API Gateway ──→ visits-service ──→ customers-service
    (8080)          (8082)              (8081)
                      ↓                    ↓
                visits 表 ←──FK──→ pets 表 ←──FK──→ owners 表
                                        ↑
                     Phase 1 已驗證 Schema & Data ─┘
```

---

## 6. Phase 4：端到端與決策

### 6.1 Gherkin（業務可讀）

```gherkin
@pre-sit @phase-4 @e2e
功能: Pre-SIT 端到端驗證與 Go/No-Go 決策

  @e2e @business-flow @critical
  場景: 完整的寵物看診業務流程
    當 新飼主 "王小明" 透過 API 註冊 ...
    當 為該飼主登記一隻寵物 ...
    當 為該寵物建立就診記錄 ...
    當 我查詢該飼主的完整資料
    那麼 飼主姓名應為 "王 小明"
    並且 應擁有 1 隻寵物名為 "小花"
    並且 該寵物應有 1 筆就診記錄

  @decision @go-nogo @critical
  場景: 彙整驗證結果並產出決策報告
    當 系統計算總通過率
    那麼 若通過率 >= 95% 且無 @critical 場景失敗，決策為 "GO ✅"
    否則 決策為 "NO-GO ❌"
```

---

## 7. 執行流程

### 7.1 從代碼到 K8s Job 的完整鏈路

```
  開發者 Push Code
       │
       ↓
  ┌──────────────────────────────┐
  │  Git Repository              │  features/ + step-definitions/ + pom.xml
  └──────────┬───────────────────┘
             │  Webhook
             ↓
  ┌──────────────────────────────┐
  │  Docker Build & Push         │  docker build → localhost:5000/presit-bdd-runner
  └──────────┬───────────────────┘
             │
             ↓
  ┌──────────────────────────────┐
  │  ArgoCD 偵測到變更           │  Sync → Apply K8s Manifests
  └──────────┬───────────────────┘
             │  PostSync Hook
             ↓
  ┌──────────────────────────────────────────────────────┐
  │  Kind Cluster (pre-sit namespace)                    │
  │                                                      │
  │  Job: presit-phase1-database                         │
  │    InitContainer: wait-for-db (nc -z postgres 5432)  │
  │    Container: mvn test -P phase-1                    │
  │         │                                            │
  │         ↓ (kubectl wait --for=complete)               │
  │  Job: presit-phase2-application                      │
  │    InitContainer: wait-for-phase1 + wait-for-apps    │
  │    Container: mvn test -P phase-2                    │
  │         │                                            │
  │         ↓                                            │
  │  Job: presit-phase3-integration                      │
  │    InitContainer: wait-for-phase2                    │
  │    Container: mvn test -P phase-3                    │
  │         │                                            │
  │         ↓                                            │
  │  Job: presit-phase4-e2e-decision                     │
  │    InitContainer: wait-for-phase3                    │
  │    Container: mvn test -P phase-4                    │
  │         │                                            │
  │         ↓                                            │
  │    /reports/presit-decision.json                      │
  │    ✅ GO  →  部署至 SIT                               │
  │    ❌ NO-GO → 通知開發者修復                          │
  └──────────────────────────────────────────────────────┘
```

### 7.2 本地開發快速驗證

```bash
# 1. 只跑 Smoke Test（開發中快速回饋，約 2 分鐘）
mvn test -P smoke

# 2. 只跑某個 Phase
mvn test -P phase-1          # 數據庫層
mvn test -P phase-3          # 集成測試

# 3. 只跑特定 Tag
mvn test -Dcucumber.filter.tags="@ddl and @critical"

# 4. 全流程（約 15-30 分鐘）
./scripts/run-presit.sh --all
```

### 7.3 CI/CD 整合

```bash
# ArgoCD PostSync Hook 自動觸發
# k8s/presit-validation-jobs.yaml 中的 annotation:
#   argocd.argoproj.io/hook: PostSync
#
# 當 ArgoCD 完成應用部署同步後，自動啟動 Phase 1 Job
# 每個 Phase Job 的 initContainer 會等待前一個 Phase 完成
```

---

## 8. 報告與決策

### 8.1 Cucumber 報告輸出

```
reports/
├── cucumber-report.html      ← 人類可讀 HTML 報告
├── cucumber-report.json      ← 機器可讀 JSON（可對接 CI Dashboard）
├── cucumber-report.xml       ← JUnit XML（對接 Jenkins / GitLab CI）
├── pretty/                   ← 美化版 HTML 報告
└── presit-decision.json      ← Go/No-Go 決策結果
```

### 8.2 決策報告範例

```json
{
  "timestamp": "2026-05-16T08:30:00Z",
  "total_phases": 4,
  "passed_phases": 4,
  "failed_phases": 0,
  "pass_rate": 100,
  "decision": "GO",
  "details": {
    "phase_results": [
      "✅ Phase 1: 數據庫層驗證 (45s)",
      "✅ Phase 2: 應用層驗證 (32s)",
      "✅ Phase 3: 功能與集成驗證 (128s)",
      "✅ Phase 4: 端到端與決策 (95s)"
    ]
  }
}
```

### 8.3 Go/No-Go 判定規則

| 條件 | 決策 |
|------|------|
| 4 Phase 全部通過 且 無 `@critical` 失敗 | ✅ GO |
| 任何 Phase 失敗 或 任何 `@critical` 場景失敗 | ❌ NO-GO |
| Phase 1 失敗 | ❌ NO-GO（後續 Phase 不會執行） |

---

## 附錄 C：Gherkin → Step Definition 是手動契約，不是自動產生

### C.1 常見誤解

> 「Cucumber 會自動把 Gherkin 場景轉成測試程式碼嗎？」

**不會。** Gherkin `.feature` 檔案是**規格文件**，Step Definition `.java` 檔案是**規格的實作**。
兩者之間的對應關係是**開發者手動維護的契約**。

Cucumber 框架在**執行時期**做的唯一一件事是：
把每一行 step 文字，用 annotation 裡的 expression 做 regex 比對，找到對應的 Java 方法並呼叫。

```
.feature 檔（人寫）              Step Definition（人寫）           Cucumber（執行時自動）
────────────────────             ──────────────────────────        ─────────────────────
  當 我查詢 schema "vets_schema"   @當("我查詢 schema {string}")    ← regex 比對 step 文字
  的表清單                         public void querySchemaTables(   ← 呼叫此方法
                                       String schema) { ... }
```

### C.2 如果 Step 沒有對應的方法

Cucumber 會拋出 **`Undefined step`** 錯誤，場景狀態為 `UNDEFINED`（不是 FAIL，是根本沒執行）：

```
Undefined step: 當 我查詢 schema "vets_schema" 的表清單
You can implement this step using the snippet(s) below:

@當("我查詢 schema {string} 的表清單")
public void 我查詢Schema的表清單(String string) {
    // Write code here that turns the phrase above into concrete actions
    throw new io.cucumber.java.PendingException();
}
```

Cucumber 可以**產生空的 stub**（只有方法簽名），但 stub 裡的 `throw new PendingException()` 必須由開發者替換成真正的邏輯。**程式邏輯不會自動產生。**

### C.3 維護契約的三條規則

| 規則 | 說明 |
|---|---|
| **Step 文字改變 → annotation 必須同步改** | feature 改了措辭，Java 的 `@當("...")` 要跟著改，否則 `Undefined step` |
| **一個 step 對應一個方法** | 同樣的 step 文字不能有兩個 annotation 完全相同的方法（Cucumber 會報 ambiguous） |
| **DataTable / DocString 型別必須手動宣告** | `DataTable`、`String`（DocString）等參數型別，開發者要在方法簽名上明確宣告 |

### C.4 本專案的分工實踐

```
BA / QA                    Developer
─────────────────          ──────────────────────────────────────────
撰寫/修改 .feature 檔      看 BA 新增的 step，判斷是否需要新增方法：
                             ├── 已有相同 annotation → 直接復用
                             ├── 新 step → 寫新方法（JDBC / HTTP / kubectl）
                             └── step 改措辭 → 更新 annotation 裡的 expression
```

**關鍵點**：BA 可以獨立修改 Gherkin 場景的**業務描述**（例如改期望數值、新增測試案例），
但一旦**步驟文字本身改變**，就需要 Developer 同步更新 Step Definition。
這是 BDD 工作流中 BA 與 Developer **協作邊界**所在。

---

## 附錄 A：Gherkin 中文關鍵字速查

| Gherkin 英文 | 中文 (zh-TW) | 用途 |
|-------------|-------------|------|
| Feature | 功能 | 測試功能描述 |
| Background | 背景 | 每個場景前的共用前置條件 |
| Scenario | 場景 | 單一測試案例 |
| Scenario Outline | 場景大綱 | 數據驅動的測試案例 |
| Examples | 例子 | 場景大綱的測試數據表 |
| Given | 假設 | 前置條件 |
| When | 當 | 操作動作 |
| Then | 那麼 | 預期結果 |
| And | 並且 | 連接同類步驟 |
| But | 但是 | 連接反向條件 |

## 附錄 B：快速上手指令

```bash
# 1. 構建測試鏡像
docker build -t localhost:5000/presit-bdd-runner:latest .
docker push localhost:5000/presit-bdd-runner:latest

# 2. 部署到 Kind 集群
kubectl apply -f k8s/presit-validation-jobs.yaml

# 3. 監看執行進度
kubectl get jobs -n pre-sit -w

# 4. 查看特定 Phase 日誌
kubectl logs job/presit-phase1-database -n pre-sit

# 5. 查看測試報告
kubectl cp pre-sit/presit-phase4-e2e-decision:/reports ./local-reports

# 6. 清理
kubectl delete jobs -l app=presit-validation -n pre-sit
```
