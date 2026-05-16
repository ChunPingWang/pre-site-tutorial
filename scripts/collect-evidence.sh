#!/usr/bin/env bash
# v2.2 Stage I: 證據蒐集（Level 1 文字證據）
#
# 對應 v2.2 §8.6 Jenkinsfile post-build stage 的本地腳本版。
# 蒐集：PostgreSQL 查詢 / kubectl 狀態 / ArgoCD app / BDD reports
# 用法:
#   scripts/collect-evidence.sh [SHA]
#   SHA 預設為當前 git HEAD short SHA
set -euo pipefail

SHA="${1:-$(git rev-parse --short HEAD)}"
ROOT="$(dirname "$0")/.."
OUT="${ROOT}/evidence/${SHA}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${OUT}"/{pre-sit/{phase1-database,phase2-application,phase3-integration,phase4-e2e},sit,argocd,k8s,jenkins}

echo "[evidence] SHA=${SHA}, OUT=${OUT}"

# ─── PostgreSQL 狀態 ────────────────────────
echo "[evidence] PostgreSQL queries..."
for ns in pre-sit sit; do
  PG_POD=$(kubectl -n "${ns}" get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -z "${PG_POD}" ]; then continue; fi
  PSQL="kubectl -n ${ns} exec ${PG_POD} -- psql -U petclinic -d petclinic"
  ${PSQL} -c '\dn' > "${OUT}/${ns}/01-postgres-schemas.txt" 2>&1 || true
  for s in customers_schema vets_schema visits_schema; do
    ${PSQL} -c "SELECT version,description,success FROM ${s}.flyway_schema_history ORDER BY installed_rank;" \
      > "${OUT}/${ns}/02-flyway-${s}.txt" 2>&1 || true
  done
  ${PSQL} -c "
    SELECT 'customers.owners' AS t, count(*) FROM customers_schema.owners
    UNION ALL SELECT 'customers.pets', count(*) FROM customers_schema.pets
    UNION ALL SELECT 'customers.types', count(*) FROM customers_schema.types
    UNION ALL SELECT 'vets.vets', count(*) FROM vets_schema.vets
    UNION ALL SELECT 'vets.specialties', count(*) FROM vets_schema.specialties
    UNION ALL SELECT 'visits.visits', count(*) FROM visits_schema.visits
    ORDER BY 1;" > "${OUT}/${ns}/03-rowcounts.txt" 2>&1 || true
done

# ─── BDD reports (Pre-SIT PVC) ──────────────
echo "[evidence] BDD reports from PVC..."
kubectl -n pre-sit apply -f - <<'EOF' >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata: { name: evidence-fetcher, namespace: pre-sit }
spec:
  restartPolicy: Never
  containers:
  - name: c
    image: busybox:1.36
    command: ['sh','-c','sleep 600']
    volumeMounts: [{ name: r, mountPath: /reports, readOnly: true }]
  volumes:
  - name: r
    persistentVolumeClaim: { claimName: presit-reports }
EOF
if kubectl wait pod/evidence-fetcher -n pre-sit --for=condition=Ready --timeout=60s >/dev/null 2>&1; then
  for p in phase-1 phase-2 phase-3 phase-4; do
    target_dir="${OUT}/pre-sit/${p/phase-/phase}-$(case ${p} in phase-1) echo database;; phase-2) echo application;; phase-3) echo integration;; phase-4) echo e2e;; esac)"
    mkdir -p "${target_dir}"
    kubectl cp "pre-sit/evidence-fetcher:/reports/${p}" "${target_dir}" 2>/dev/null || true
  done
  kubectl cp "pre-sit/evidence-fetcher:/reports/presit-decision.json" "${OUT}/pre-sit/presit-decision.json" 2>/dev/null || true
  kubectl cp "pre-sit/evidence-fetcher:/reports/presit-decision.html" "${OUT}/pre-sit/presit-decision.html" 2>/dev/null || true
  kubectl -n pre-sit delete pod evidence-fetcher --ignore-not-found >/dev/null 2>&1
fi

# ─── K8s 狀態 ───────────────────────────────
echo "[evidence] kubectl snapshots..."
for ns in pre-sit sit; do
  kubectl get pods -n "${ns}" -o yaml > "${OUT}/k8s/pods-${ns}.yaml" 2>&1 || true
  kubectl get events -n "${ns}" --sort-by=.metadata.creationTimestamp \
    > "${OUT}/k8s/events-${ns}.txt" 2>&1 || true
done

# ─── ArgoCD apps ────────────────────────────
echo "[evidence] ArgoCD apps..."
for app in petclinic-pre-sit petclinic-sit; do
  kubectl -n argocd get application "${app}" -o yaml > "${OUT}/argocd/${app}.yaml" 2>&1 || true
done
kubectl -n argocd logs deployment/argocd-image-updater --tail=100 \
  > "${OUT}/argocd/image-updater.log" 2>&1 || true

# ─── INDEX.md ──────────────────────────────
echo "[evidence] generating INDEX.md..."
DEC=$(cat "${OUT}/pre-sit/presit-decision.json" 2>/dev/null || echo '{}')
DEC_VALUE=$(echo "${DEC}" | python3 -c "import sys,json; s=sys.stdin.read(); d=json.loads(s) if s.strip() else {}; print(d.get('decision','N/A'))" 2>/dev/null || echo "N/A")
RATE=$(echo "${DEC}" | python3 -c "import sys,json; s=sys.stdin.read(); d=json.loads(s) if s.strip() else {}; print(d.get('pass_rate','N/A'))" 2>/dev/null || echo "N/A")
{
  echo "# Pre-SIT 驗證證據報告"
  echo
  echo "| 項目 | 值 |"
  echo "|---|---|"
  echo "| Build SHA | \`${SHA}\` |"
  echo "| 蒐集時間 | ${TS} |"
  echo "| Pre-SIT 決策 | **${DEC_VALUE}** |"
  echo "| 通過率 | ${RATE}% |"
  echo
  echo "## Pre-SIT BDD 結果"
  echo
  for p in 1 2 3 4; do
    case ${p} in 1) name=database;; 2) name=application;; 3) name=integration;; 4) name=e2e;; esac
    xml="${OUT}/pre-sit/phase${p}-${name}/cucumber-report.xml"
    if [ -f "${xml}" ]; then
      stats=$(grep -oE 'tests="[0-9]+" .*errors="[0-9]+"' "${xml}" | head -1)
      echo "- **Phase ${p} ${name}**: ${stats}  ([html](pre-sit/phase${p}-${name}/cucumber-report.html))"
    fi
  done
  echo
  echo "## Postgres 狀態"
  echo "- [Pre-SIT schemas](pre-sit/01-postgres-schemas.txt)"
  echo "- [Pre-SIT row counts](pre-sit/03-rowcounts.txt)"
  echo "- [Pre-SIT Flyway customers](pre-sit/02-flyway-customers_schema.txt)"
  echo "- [SIT schemas](sit/01-postgres-schemas.txt)"
  echo "- [SIT row counts](sit/03-rowcounts.txt)"
  echo
  echo "## ArgoCD apps"
  echo "- [petclinic-pre-sit](argocd/petclinic-pre-sit.yaml)"
  echo "- [petclinic-sit](argocd/petclinic-sit.yaml)"
  echo "- [Image Updater log](argocd/image-updater.log)"
  echo
  echo "## K8s 狀態"
  echo "- [Pre-SIT pods](k8s/pods-pre-sit.yaml) · [events](k8s/events-pre-sit.txt)"
  echo "- [SIT pods](k8s/pods-sit.yaml) · [events](k8s/events-sit.txt)"
  echo
  echo "---"
  echo "_自動生成：\`scripts/collect-evidence.sh\`_"
} > "${OUT}/INDEX.md"

echo "[evidence] ✅ DONE → ${OUT}/INDEX.md"
