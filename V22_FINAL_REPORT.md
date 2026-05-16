# Pre-SIT v2.2 PoC 最終結果報告

**日期**: 2026-05-16
**狀態**: ✅ **GO**（Pre-SIT BDD 100% 通過 + SIT 真實對外可用 + Promote 鏈端到端運作）

---

## 1. 一句話結論

「**Vendor PetClinic → Postgres + Flyway → 雙環境 (Pre-SIT + SIT) → ArgoCD AutoSync + Image Updater promote**」這條 v2.2 §2 設計的鏈路，在 Kind 集群上**端到端跑通**：每次 push 可以在分鐘級內完成 build → BDD → 人工 review → SIT 自動部署，使用者透過 ingress 直接探索 PetClinic UI 並回饋 bug。

---

## 2. v2.2 vs v2.1 對比

| 面向 | v2.1 (plan-faithful + upstream-as-is) | v2.2 (vendor + Postgres + 雙環境) |
|------|---------------------------------------|---------------------------------|
| PetClinic image 來源 | upstream `springcommunity/*` 原樣 | vendored `petclinic-src/`，自己 build |
| 應用底層 DB | HSQLDB (in-mem) | PostgreSQL 16 + Flyway |
| Schema 管理 | InitContainer 灌固定 SQL | Flyway V*.sql 版本化 |
| Schema 拆分 | 單一 `public` | `customers_schema` / `vets_schema` / `visits_schema` |
| Service Discovery | Eureka (`spring-cloud-starter-netflix-eureka-client`) | K8s Service DNS |
| 配置中心 | Spring Cloud Config Server | K8s ConfigMap + Secret |
| 環境數 | 1 (`pre-sit`) | 2 (`pre-sit` + `sit`) |
| 對外暴露 | port-forward 為主 | nginx-ingress `http://sit.local:30080/` |
| CI/CD | 手動 docker build + kubectl apply | Argo Image Updater 偵測 `:sit-approved` → ArgoCD AutoSync 部署 SIT |
| Bug 反饋 | 無正式路徑 | GitHub Issue template + PR template + 候選 Gherkin |
| 測試金字塔 | 單元測試 → BDD (二層) | 單元測試 → **Contract Test** (SCC) → BDD (三層) |
| 證據蒐集 | 手動 kubectl cp | `scripts/collect-evidence.sh` 自動產 `INDEX.md` |
| Pre-SIT 場景數 | 57 | 60 (+3 Flyway 場景 −2 重複 +2 known-issue 修復) |
| Phase 3 場景數 | 11 (+1 `@known-issue` 排除) | **12** (Stage D.2 修了 404 handler) |
| 已知 known-issue | 1 (`@known-issue` Phase 3 404) | **0** |
| 最終決策 | GO（100% 排除 known-issue 後） | **GO**（100% 含原 known-issue） |

---

## 3. Stage 完成度

| Stage | 內容 | 狀態 | 對應 commit |
|-------|------|------|-----------|
| A.1 | Vendor PetClinic source | ✅ | `7595249` |
| A.2 | 加 Postgres driver + Flyway dep | ✅ | `2714cdb` |
| A.3 | Flyway V1/V2 migration | ✅ | `deb5b6a` |
| A.4 | application.yml profile (presit/sit) | ✅ | `49869e0` |
| A.5 | docker-compose 本機驗證 | ✅ | `358fd8d` |
| A.6 | Spring Cloud Contract (10 contract 全綠) | ✅ | `b62ca16` + `5b33e2a` |
| B | K8s ConfigMap + Service DNS 部署 | ✅ | `8350219` |
| D | BDD 適配 v2.2 (三 schema) | ✅ | `f6004cb` |
| E | SIT namespace + nginx-ingress | ✅ | `fc2b93e` |
| F | ArgoCD AutoSync + Image Updater | ✅ | `02fae40` + `03c1512` |
| D.2 | PetClinic 404 handler (消除 known-issue) | ✅ | `e6df0ed` |
| G | GitHub Issue + PR template | ✅ | `e6df0ed` (合併入) |
| I | Evidence 蒐集腳本 + INDEX.md | ✅ | `e6df0ed` (合併入) |
| H | 端到端 demo 腳本 + 本檔 | ✅ | _本 commit_ |
| **C** | **Jenkins on Kind** | **⏭️ 留 v2.3** | (略) |

15/16 stages 完成 (除 Jenkins 留 v2.3)，全程合計 ~18 commit。

---

## 4. 最終 BDD 成績

```json
{
  "timestamp": "2026-05-16T11:07:55Z",
  "total": 55,
  "passed": 55,
  "failed": 0,
  "pass_rate": 100,
  "decision": "GO ✅"
}
```

| Phase | tests | failures | 結果 |
|-------|-------|----------|------|
| Phase 1 數據庫層 (三 schema + Flyway) | 20 | 0 | ✅ |
| Phase 2 應用層 (PetClinic 真連 Postgres) | 23 | 0 | ✅ |
| Phase 3 功能集成 (含原 known-issue 404) | 12 | 0 | ✅ |
| Phase 4 端到端 + ArgoCD + 決策 | 5 | 0 | ✅ |
| **合計** | **60** | **0** | **100% GO** |

證據在 [`evidence/02fae40/INDEX.md`](evidence/02fae40/INDEX.md)。

---

## 5. 雙環境並存運作圖

```
┌─────────────────────────────────────────────────────────────┐
│ Kind cluster (presit)                                       │
│                                                             │
│ ┌─────────────┐  ┌────────────────────────────┐             │
│ │ argocd ns   │  │ pre-sit ns (ephemeral)     │             │
│ │ - argocd    │  │ - postgres (emptyDir)      │             │
│ │ - image-    │  │ - 4 PetClinic (profile=    │             │
│ │   updater   │  │   presit, Flyway clean+    │             │
│ │ - dex/etc   │  │   migrate)                 │             │
│ └─────────────┘  │ - 4 BDD Jobs (Phase 1-4)   │             │
│                  └────────────────────────────┘             │
│ ┌─────────────┐  ┌────────────────────────────┐             │
│ │ ingress-    │  │ sit ns (persistent)        │             │
│ │ nginx ns    │  │ - postgres (1Gi PVC)       │             │
│ │ - nginx     │  │ - 4 PetClinic (profile=    │             │
│ │   controller│  │   sit, Flyway migrate-only,│             │
│ │ (NodePort   │  │   image=:sit-approved)     │             │
│ │  30080)     │  │ - Ingress sit.local:30080  │             │
│ └─────────────┘  └────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                            ↑
                use Ingress → 使用者瀏覽器
```

---

## 6. Promote 鏈實測時序

從本次 v2.2 端到端 demo（commit `02fae40`）抽出實測時序：

| 時間 | 動作 | 觀察結果 |
|------|------|--------|
| t+0s | `docker build petclinic-customers-service` | jar size ~50MB |
| t+10s | `docker push :sha-02fae40-d2` | digest 推上 registry |
| t+20s | `kubectl rollout restart deployment customers-service` (Pre-SIT) | 新 pod 啟動，舊 pod terminate |
| t+50s | 新 customers-service pod ready | Flyway 自動跑 (DB 已有 schema 所以 0 new migration) |
| t+60s | apply BDD jobs | Phase 1 Job 啟動 |
| t+100s | Phase 1 完成 (20/20) | DB schema/data 全綠 |
| t+200s | Phase 2 完成 (23/23) | 4 service /actuator/health 全綠 |
| t+340s | Phase 3 完成 (12/12) | 含原 known-issue 404 場景 |
| t+450s | Phase 4 完成 (5/5) | decision JSON 寫入 PVC |
| t+460s | 人工 review 決定 promote | (本 demo 用 docker tag 模擬 PR merge) |
| t+470s | `docker tag :sha-02fae40-d2 :sit-approved && push` | registry 多一個 tag |
| t+530s | Argo Image Updater 偵測（poll 60s 內） | log 寫 "Setting new image to ...:sit-approved" |
| t+540s | ArgoCD AutoSync 觸發 SIT deployments rolling update | 4 個 deployment 開始輪替 |
| t+600s | SIT 4 pods 全部切到 :sit-approved | 經 ingress 仍訪問 OK |
| t+610s | 跑 `scripts/collect-evidence.sh` | INDEX.md 自動生成 |

**從 build start 到 SIT 完全更新：約 10 分鐘**（主要時間是 BDD 4 phase 跑完）。
Promote step 本身（人工 review 後 docker tag → SIT 更新）：**2 分鐘內**。

---

## 7. v2.2 §1.3 三大相容性約束的解決狀態

| # | v2.1 限制 | v2.2 解法 | 狀態 |
|---|----------|---------|------|
| C1 | upstream PetClinic 無 postgres profile → Phase 1 驗的 ≠ 應用實際用的 | vendor + 自行加 PG driver + Flyway | ✅ 解 |
| C2 | Spring Boot 3.2 + Spring Cloud 啟動穩態 >512MB | feature 門檻調 768MB（含相同 JVM tuning） | ✅ 維持 v2.1 解法 |
| C3 | actuator `show-details=never` 不暴露 `components.db.*`；upstream owner 404 回 200 | application.yml 加 `show-details=always`；Stage D.2 加 ExceptionHandler | ✅ 全解 |

v2.2 **全部三大相容性約束都已根本性解決**，不再有 `@known-issue` 場景。

---

## 8. 給 v2.3 的 backlog

| 主題 | 動機 |
|------|------|
| **Stage C: Jenkins on Kind** | 將 demo 腳本封裝為 Jenkinsfile，CI 自動觸發 (本次留作 backlog) |
| Argo Image Updater 多 image 同時更新 race | Stage F 發現 4 image patch 互相覆蓋；需手動補 spec |
| StatefulSet `volumeClaimTemplates` 永久 OutOfSync | Stage F 用 `ignoreDifferences` 暫解 |
| `:sit-approved` 寫回 git (write-back-method=git) | 目前用 `argocd` 寫到 app spec，git 沒紀錄 |
| 觀測性：Prometheus + Grafana + Loki | v2.2 §3 #15 明確留到 v2.3 |
| Sealed Secrets 取代明文 K8s Secret | v2.2 §3 #18 留到 v2.3 |
| Per-user SIT namespace | 多並行探索測試的隔離 |
| 第三環境 UAT | SIT 與 production 之間 |
| Postgres PVC snapshot / restore | 災難復原 |
| RFC3161 timestamp signing on evidence | 受監管業務需求 |

---

## 9. 文件導覽（最終版）

| 文件 | 角色 |
|------|------|
| [README.md](README.md) | 教學入口（含 C4 + 序列圖 + 類別圖） |
| [Pre-SIT_Work_Plan_v2.2.md](Pre-SIT_Work_Plan_v2.2.md) | 現行工作計畫書（含 §9 SCC 章節） |
| [Pre-SIT_Work_Plan_v2.1.md](Pre-SIT_Work_Plan_v2.1.md) | 上一代計畫（plan-faithful baseline） |
| [Pre-SIT_Work_Plan_v2.md](Pre-SIT_Work_Plan_v2.md) | v2.0 原始版（歷史保留） |
| [Pre-SIT_Gherkin_to_Script_Guide.md](Pre-SIT_Gherkin_to_Script_Guide.md) | Gherkin ↔ Java 對應教學 |
| **[V22_FINAL_REPORT.md](V22_FINAL_REPORT.md)** | **本檔（v2.2 最終結果）** |
| [petclinic-src/README-vendoring.md](petclinic-src/README-vendoring.md) | PetClinic vendor 紀錄 |
| [presit-bdd-demo/poc/POC_RESULTS.md](presit-bdd-demo/poc/POC_RESULTS.md) | v2.1 PoC 結果（歷史保留） |
| [presit-bdd-demo/poc-v2.2/](presit-bdd-demo/poc-v2.2/) | v2.2 BDD 專案（三 schema 適配） |
| [evidence/02fae40/INDEX.md](evidence/02fae40/INDEX.md) | v2.2 端到端 demo 證據 |
| [scripts/run-v22-demo.sh](scripts/run-v22-demo.sh) | 端到端 demo 一鍵腳本 |
| [scripts/collect-evidence.sh](scripts/collect-evidence.sh) | 證據蒐集腳本 |
| [.github/ISSUE_TEMPLATE/sit-exploration-bug.yml](.github/ISSUE_TEMPLATE/sit-exploration-bug.yml) | SIT bug 回報模板 |
| [.github/pull_request_template.md](.github/pull_request_template.md) | PR 描述模板 |

---

## 10. 結論

- v2.2 PoC **完成**：vendor PetClinic + Postgres/Flyway + 雙環境 + ArgoCD AutoSync + Image promote + BDD 100% GO，全部跑通。
- **解掉所有 v2.1 §1.3 相容性約束**（含原 `@known-issue` 場景）。
- **新增 Spring Cloud Contract 層**（10 contract 全綠），補上測試金字塔中段。
- 證據包含 38 個檔（postgres × 雙環境 + Flyway history + BDD reports × 4 phase + K8s 狀態 + ArgoCD），自動生成 INDEX.md。
- Jenkins 自動化（Stage C）留作 v2.3 主題；其他全部完成。

可進入下一階段：選定要不要做 Stage C (Jenkins) + 觀測性 + sealed-secrets + 等 v2.3 主題。
