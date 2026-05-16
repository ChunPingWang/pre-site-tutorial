<!--
v2.2 §7 探索測試 Bug → Gherkin 場景閉迴路專用模板
-->

## 變更類型
- [ ] 新功能
- [ ] Bug 修正
- [ ] 新 Gherkin 場景（從 SIT 探索 bug 轉化）
  - 對應 Issue: #
- [ ] DB migration（含 Flyway V*.sql）
- [ ] 文件 / 重構 / CI
- [ ] **Promote to SIT**（retag image :sha-xxx → :sit-approved）

## 影響範圍
- [ ] customers-service
- [ ] vets-service
- [ ] visits-service
- [ ] api-gateway
- [ ] Pre-SIT manifests / BDD
- [ ] SIT manifests
- [ ] Jenkins / ArgoCD 配置

## Pre-SIT 驗證
- [ ] 本機已跑 `mvn test -P phase-X`（請填 phase 編號）
- [ ] Pre-SIT BDD 已跑出 GO （請貼連結）

## SIT 影響評估
- [ ] 不需 SIT 維護視窗
- [ ] 需 SIT 維護視窗（時段：__）
- [ ] 包含 DB migration（Flyway baseline-on-migrate 行為已 review）
- [ ] 不影響使用者進行中的探索測試 / 已通知 SIT 使用者

## Rollback plan（若是 SIT-impacting change）
<!-- 如何回滾、為何安全 -->

---

### Reviewer Checklist（Promote PR 才需要）
- [ ] 確認 Pre-SIT 報告為 GO（通過率 ≥ 95% + @critical 0 失敗）
- [ ] 確認本 PR 變更與 `:sha-xxx` 對應的 commit 一致
- [ ] 確認 DB migration（如有）已 review
- [ ] 已通知 SIT 使用者（如有）
