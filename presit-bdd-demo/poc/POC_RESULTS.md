# Pre-SIT PoC 結果報告

**執行日期**: 2026-05-16
**目標**: 依 v2 工作計畫書，在 Kind 集群上以 ArgoCD 部署 PetClinic 微服務 + 容器化 PostgreSQL，並以 Cucumber/Gherkin 自動執行 Phase 1–4 驗證，產出 Go/No-Go 決策報告。

---

## 1. 最終結果

| 指標 | 值 |
|---|---|
| 總場景數 | **57** (Phase 1: 17, Phase 2: 23, Phase 3: 12, Phase 4: 5) |
| 通過 | **45** |
| 失敗 | **7** |
| 通過率 | **86%** |
| 決策 | **❌ NO-GO** (門檻為 ≥ 95% 且 @critical 全綠) |

JSON 決策報告 (`reports/presit-decision.json`):
```json
{"timestamp":"2026-05-16T01:46:34Z","total":52,"passed":45,"failed":7,"pass_rate":86,"decision":"NO-GO ❌"}
```

> 註：彙整時 Phase 4 自身 5 個情境（5 個 PASS）剛開始執行還未寫入彙整檔，所以 `total=52` 而非 57。實際完整數字為 57/45 通過。

---

## 2. 各 Phase 結果

### ✅ Phase 1 數據庫層：17 / 17 (100%)

完全綠燈。實際對容器化 PostgreSQL 驗證：

| 驗證項 | 結果 |
|---|---|
| 7 張表存在 (`owners, pets, types, vets, specialties, vet_specialties, visits`) | ✅ |
| 7 張表欄位數量正確 | ✅ |
| `owners`、`pets` 表的 10 個欄位定義（data_type/nullable/max_length） | ✅ |
| 6 組主鍵約束 | ✅ |
| 5 組外鍵約束 | ✅ |
| 3 個自定義索引 (`idx_owners_last_name`, `idx_pets_name`, `idx_vets_last_name`) | ✅ |
| 7 張表資料筆數達門檻 | ✅ |
| 引用完整性：pets→owners、visits→pets 無孤立記錄 | ✅ |
| George Franklin 標準資料欄位值 | ✅ |
| 序列：INSERT RETURNING id → DELETE | ✅ |

---

### ❌ Phase 2 應用層：17 / 23 (74%)

6 個失敗，全屬「計畫書斷言 vs Spring Boot 實際行為」的不對齊：

| 失敗場景 | 根因 | 屬性 |
|---|---|---|
| 微服務資源使用量 (customers/vets) — 2 次 | 計畫書斷言 `MEM < 512MB`；upstream Spring Boot 3.2 + Spring Cloud Config + Eureka client 啟動穩態約 500–530 MiB（即使 `-Xmx200m -XX:MaxMetaspaceSize=160m`） | 真實限制不切實際 |
| 數據庫健康指標 `components.db.status` (3 例) | upstream config-server 未設 `management.endpoint.health.show-details=always`，actuator 只回 `{"status":"UP","groups":[...]}`，沒有 `components` 物件 | upstream 預設配置 |
| api-gateway log 含 `Connection refused` | api-gateway 透過 Netty 與 Eureka 解析後端服務時，連線失敗會以 stacktrace 形式持續出現在 log 中（穩態） | Spring Cloud Gateway 行為 |

通過：4 個微服務啟動、健康端點 200/UP、K8s Service Endpoints 解析、`Started` 訊息存在等。

---

### ❌ Phase 3 功能集成：11 / 12 (92%)

唯一失敗：

| 失敗場景 | 實際 | 預期 | 根因 |
|---|---|---|---|
| `GET /api/customer/owners/99999` 應 404 | 200 | 404 | upstream PetClinic customers-service 對「找不到的 owner」回 `200 OK` 並帶空/null body，未實作 RESTful 404 |

通過：CRUD 全套（GET/POST/PUT）、新增 Owner→回查、新增 Pet→Owner.pets 包含、跨服務建立 Visit、petTypes 6 種、Vets+specialties、邊界值（缺欄位 → 400/422、過長欄位 → 非 200/201）、清理。

---

### ✅ Phase 4 端到端 + Go/No-Go：5 / 5 (100%)

| 場景 | 結果 |
|---|---|
| 完整寵物看診業務流程（註冊飼主→登記寵物→建立就診→查詢驗證→清理） | ✅ |
| API P95 < 500ms / P99 < 1000ms（3 端點 ×100 次） | ✅ |
| 20 並發 30 秒，錯誤率 < 1%、平均回應 < 300ms、無 OOMKilled | ✅ |
| ArgoCD 應用 `petclinic-pre-sit` Synced + Healthy | ✅ |
| 彙整結果並產出 JSON/HTML 決策 | ✅ |

---

## 3. 基礎設施部署摘要

```
Kind 集群 (presit, 1 control-plane)
├── kube-system: metrics-server (--kubelet-insecure-tls)
├── argocd: 7 個 deployment (admin 密碼: u9nlXvmvXqeU1hvF)
└── pre-sit:
    ├── PostgreSQL StatefulSet (postgres:16-alpine)
    │   └── ConfigMap initdb: 01-schema.sql + 02-sample-data.sql
    ├── config-server     (springcommunity/spring-petclinic-config-server:3.2.0)
    ├── discovery-server  (springcommunity/spring-petclinic-discovery-server:3.2.0)
    ├── customers-service (springcommunity/spring-petclinic-customers-service:3.2.0)
    ├── vets-service      (springcommunity/spring-petclinic-vets-service:3.2.0)
    ├── visits-service    (springcommunity/spring-petclinic-visits-service:3.2.0)
    ├── api-gateway       (springcommunity/spring-petclinic-api-gateway:3.2.0)
    └── BDD Runner Jobs   (localhost:5000/presit-bdd-runner:latest, 4 個 Phase)

ArgoCD Application: petclinic-pre-sit → Synced + Healthy
Local Docker Registry: kind-registry:5000 (mirror 至 localhost:5000)
```

---

## 4. 對 v2 工作計畫書的修正建議

PoC 過程發現原始計畫 / 提供的 demo 在以下 5 處與真實環境不對齊。建議於 v2.1 釐清：

| # | 位置 | 問題 | 建議 |
|---|---|---|---|
| 1 | `pom.xml` `<testSourceDirectory>step-definitions</testSourceDirectory>` 加 `<includes>runners/**</includes>` 缺失 | Surefire 找不到 Runner → 0 test executed | 改為標準 Maven layout (`src/test/java`) |
| 2 | Phase 1 feature 用 `因為`、Phase 4 用 `否則` | 非 Gherkin zh-TW 關鍵字，FeatureParserException | 改為 `# 註解` 或 `並且` |
| 3 | `owners` 表結構：`@ddl` 場景說 5 欄位、`@sample-data` 場景比對 `city` 欄位 | 內部不一致 | 統一為 5 欄位（已採用）或 6 欄位含 city |
| 4 | Phase 2 `MEM < 512MB` | Spring Boot 3.2 + Spring Cloud 啟動就 500+ MiB | 放寬到 768MB 或先建立基準再收斂 |
| 5 | Phase 2 `components.db.status == UP` | 需 `management.endpoint.health.show-details=always`，但 upstream config 未設 | 在 config-server 加上該設定或改驗 `/actuator/health/db` 端點 |
| 6 | Phase 3 `查詢不存在 Owner 應返回 404` | upstream PetClinic customers-service 回 200 | 已知 upstream 行為；如需 404 必須改寫 application code |
| 7 | demo `DatabaseLayerSteps.java` 多個 step 是「假裝斷言」（如 `result_should_be_empty` 印空 list） | 看似綠燈實際無驗證 | PoC 已修為真實斷言 |
| 8 | demo 缺 `01-schema.sql`、`02-sample-data.sql`、Postgres manifest、4 服務 manifest、ArgoCD Application、Phase 2/3/4 step bindings | 無法直接跑 | PoC 已補全（見 `poc/sql/`, `poc/manifests/`, `poc/argocd/`, `poc/bdd/`） |

---

## 5. 對「Plan-faithful + Upstream 原圖」的根本不相容

依使用者要求保持計畫忠實 + 不重 build PetClinic，PoC 採折衷：

- **Postgres** 僅供 Phase 1 結構驗證（hand-authored DDL/DML 符合計畫書斷言）
- **PetClinic 微服務**使用 upstream 預設的 in-memory HSQLDB 啟動（upstream 無 postgres profile，重建會違反「不修改 upstream」條件）
- Phase 2/3 對「應用是否健康、API 是否可用」的驗證是真實的；但「應用底下的 DB 就是 Phase 1 驗證的那一個 Postgres」不成立

如要嚴格端到端綁定，必須二選一：
1. 重 build PetClinic 為 postgres profile（PoC 已排除）
2. 取消 Phase 1 對 7 表結構的硬編碼斷言，改驗 PetClinic 啟動後自動產生的 HSQLDB schema

---

## 6. 交付清單

```
poc/
├── POC_RESULTS.md           ← 本檔
├── kind/
│   ├── kind-config.yaml
│   └── up.sh                ← 重複執行安全的環境啟動腳本
├── sql/
│   ├── 01-schema.sql        ← 滿足 Phase 1 全部結構斷言
│   └── 02-sample-data.sql   ← 滿足筆數 / George Franklin 斷言
├── manifests/
│   ├── 00-namespace.yaml
│   ├── 10-postgres.yaml     ← StatefulSet + Service + initdb
│   ├── 20-config-server.yaml
│   ├── 30-discovery-server.yaml
│   ├── 40-microservices.yaml (4 服務，JVM 調整: -Xmx200m -XX:MaxMetaspaceSize=160m)
│   └── 50-presit-jobs.yaml  ← 4 Phase Jobs + RBAC + PVC + Secret
├── argocd/
│   └── petclinic-pre-sit.yaml
├── bdd/                     ← 修正後的 BDD 專案
│   ├── pom.xml              ← 標準 Maven layout
│   ├── Dockerfile           ← 多階段 build, localhost:5000/presit-bdd-runner:latest
│   └── src/test/{java,resources}/...
└── reports/                 ← PVC 拷出的 4 Phase 報告 + 決策檔
    ├── presit-decision.json
    ├── presit-decision.html
    ├── phase-1/cucumber-report.{html,json,xml}
    ├── phase-2/cucumber-report.{html,json,xml}
    ├── phase-3/cucumber-report.{html,json,xml}
    └── phase-4/cucumber-report.{html,json,xml}
```

---

## 7. 結論

- **BDD → Cucumber → K8s Job → ArgoCD → Go/No-Go 整條流程已端到端跑通**。
- 框架本身正確；NO-GO 是計畫書部分斷言與 upstream PetClinic 實際行為不相容的真實結果。
- 在計畫書按本報告第 4 節調整後，預期通過率可達 ≥ 95% 並達成 GO 決策。
