# petclinic-src/ vendoring 紀錄

## Vendor 來源

| 項目 | 值 |
|------|---|
| Upstream repo | https://github.com/spring-petclinic/spring-petclinic-microservices |
| Vendored tag | `v3.2.0` |
| Upstream commit | `161c6bb15ca4e41efa85ca3148280b2dd8b9e629` |
| Vendored date | 2026-05-16 |
| License | Apache 2.0（見 `LICENSE`） |

## Vendored modules（保留 4 個）

| 模組 | 用途 | 本 PoC 是否修改 |
|------|------|----------------|
| `spring-petclinic-customers-service/` | owners / pets / types 領域 | ✅ 加 Postgres + Flyway，改 application.yml |
| `spring-petclinic-vets-service/` | vets / specialties 領域 | ✅ 加 Postgres + Flyway，改 application.yml |
| `spring-petclinic-visits-service/` | visits 領域 | ✅ 加 Postgres + Flyway，改 application.yml |
| `spring-petclinic-api-gateway/` | Spring Cloud Gateway，對外路由 | ✅ 路由改用 K8s Service DNS（拋棄 Eureka） |

## 不 vendor 的 modules（已從 parent pom 移除）

依 v2.2 §3 決策 #6 與 #9，這三個 module 拋棄：

| 模組 | 拋棄原因 |
|------|---------|
| `spring-petclinic-config-server/` | 改用 K8s ConfigMap（決策 #6） |
| `spring-petclinic-discovery-server/` | 改用 K8s Service DNS（決策 #9） |
| `spring-petclinic-admin-server/` | PoC 範圍外（v2.2 §1.2 觀測性留 v2.3） |

如需重新引入，直接從 upstream `v3.2.0` 對應目錄複製進來、並在 `pom.xml` 加回 `<module>`。

## Upstream 同步策略

依 v2.2 §3 決策 #4（monorepo vendoring）：

- **凍結在 `v3.2.0`**，不主動跟 upstream rebase
- 安全 patch 走 cherry-pick：`git clone upstream → 找 CVE 修補 commit → 手動 apply 到 petclinic-src/`
- 重大版本升級走整體重 vendor：`rm -rf petclinic-src/{4 services} → 從新 tag 複製 → diff 本地修改 → 套回`

## 本地修改清單（Local patches）

> 此清單在 v2.2 Stage A 完成後填入；列出我們在 vendored code 上的所有變更，
> 方便未來重新 vendor 時知道要套回哪些修改。

### Patches applied during Stage A

- _(Stage A.2 將補：4 service pom 加 PG driver + Flyway dependency)_
- _(Stage A.3 將補：3 service 加 `src/main/resources/db/migration/V*.sql`)_
- _(Stage A.4 將補：4 service 改 `application.yml` 加 presit / sit profile)_

### Patches applied during Stage B

- _(Stage B.1 將補：api-gateway 路由由 `lb://...` 改為 `http://*.svc:8081`)_
- _(Stage B.2 將補：移除 Spring Cloud Config client，改 `spring.config.import` from K8s ConfigMap)_
