# Pre-SIT 驗證證據報告

| 項目 | 值 |
|---|---|
| Build SHA | `02fae40` |
| 蒐集時間 | 2026-05-16T11:09:26Z |
| Pre-SIT 決策 | **GO ✅** |
| 通過率 | 100% |

## Pre-SIT BDD 結果

- **Phase 1 database**: tests="20" skipped="0" failures="0" errors="0"  ([html](pre-sit/phase1-database/cucumber-report.html))
- **Phase 2 application**: tests="23" skipped="0" failures="0" errors="0"  ([html](pre-sit/phase2-application/cucumber-report.html))
- **Phase 3 integration**: tests="12" skipped="0" failures="0" errors="0"  ([html](pre-sit/phase3-integration/cucumber-report.html))
- **Phase 4 e2e**: tests="5" skipped="0" failures="0" errors="0"  ([html](pre-sit/phase4-e2e/cucumber-report.html))

## Postgres 狀態
- [Pre-SIT schemas](pre-sit/01-postgres-schemas.txt)
- [Pre-SIT row counts](pre-sit/03-rowcounts.txt)
- [Pre-SIT Flyway customers](pre-sit/02-flyway-customers_schema.txt)
- [SIT schemas](sit/01-postgres-schemas.txt)
- [SIT row counts](sit/03-rowcounts.txt)

## ArgoCD apps
- [petclinic-pre-sit](argocd/petclinic-pre-sit.yaml)
- [petclinic-sit](argocd/petclinic-sit.yaml)
- [Image Updater log](argocd/image-updater.log)

## K8s 狀態
- [Pre-SIT pods](k8s/pods-pre-sit.yaml) · [events](k8s/events-pre-sit.txt)
- [SIT pods](k8s/pods-sit.yaml) · [events](k8s/events-sit.txt)

---
_自動生成：`scripts/collect-evidence.sh`_
