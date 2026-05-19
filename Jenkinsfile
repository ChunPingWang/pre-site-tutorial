// Jenkins Full CI/CD: Pre-SIT BDD orchestrator + deploy pre-sit + promote to SIT
//
// 範圍：Jenkins 在 Kind 內處理完整 CD
//   - Deploy pre-sit 環境（kubectl apply manifests/pre-sit/）
//   - 觸發既有 BDD K8s Jobs (Phase 1-4)
//   - 等綠燈 → 讀 decision JSON
//   - GO 時：kubectl apply manifests/sit/ + kubectl set image 促進相同 image 到 SIT
//
// 留 v2.4 backlog：
//   - mvn package + docker build/push 改用 kaniko 或 DinD sidecar
//   - 加上 git webhook (Kind 收不到 GitHub webhook，需 polling 或 SMEE proxy)

pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 45, unit: 'MINUTES')
    }

    environment {
        KUBECTL    = '/shared/kubectl'
        NS         = 'pre-sit'
        SIT_NS     = 'sit'
        MANIFEST   = 'manifests/pre-sit'
        SIT_MANIFEST = 'manifests/sit'
    }

    stages {
        stage('Preflight') {
            steps {
                sh '''
                  ${KUBECTL} version --client=true 2>&1 | head -3
                  ${KUBECTL} get ns ${NS}     >/dev/null 2>&1 || echo "INFO: namespace ${NS} will be created"
                  ${KUBECTL} get ns ${SIT_NS} >/dev/null 2>&1 || echo "INFO: namespace ${SIT_NS} will be created"
                '''
            }
        }

        stage('Deploy Pre-SIT') {
            steps {
                sh '''
                  # 冪等：apply namespace、config、postgres、services、RBAC
                  ${KUBECTL} apply -f ${MANIFEST}/00-namespace.yaml
                  ${KUBECTL} apply -f ${MANIFEST}/05-config.yaml
                  # 06-sealed-db-credentials.yaml 需 Sealed Secrets controller（可選）
                  ${KUBECTL} apply -f ${MANIFEST}/06-sealed-db-credentials.yaml 2>/dev/null || true
                  ${KUBECTL} apply -f ${MANIFEST}/10-postgres.yaml
                  ${KUBECTL} apply -f ${MANIFEST}/20-petclinic-services.yaml
                  ${KUBECTL} apply -f ${MANIFEST}/25-presit-sa.yaml
                  # 等 postgres StatefulSet ready 再等 deployments
                  ${KUBECTL} -n ${NS} wait --for=condition=Ready pod -l app=postgres --timeout=120s
                  ${KUBECTL} -n ${NS} wait --for=condition=Available deployment --all --timeout=300s
                '''
            }
        }

        stage('Reset Pre-SIT for clean run') {
            steps {
                sh '''
                  set +e
                  ${KUBECTL} delete jobs -n ${NS} -l app=presit-validation 2>&1 | head -10
                  ${KUBECTL} delete pvc presit-reports -n ${NS} 2>&1 | head -3
                  ${KUBECTL} -n ${NS} delete pod postgres-0 --ignore-not-found 2>&1 | head -3
                  ${KUBECTL} -n ${NS} wait --for=condition=Ready pod/postgres-0 --timeout=120s
                  ${KUBECTL} -n ${NS} rollout restart deployment customers-service vets-service visits-service 2>&1 | head -3
                  ${KUBECTL} -n ${NS} wait --for=condition=Available deployment --all --timeout=300s
                  set -e
                '''
            }
        }

        stage('Apply BDD Jobs') {
            steps {
                sh '${KUBECTL} apply -f ${MANIFEST}/30-bdd-jobs.yaml'
            }
        }

        stage('Wait Phase 1-4') {
            steps {
                sh '''
                  # kubectl wait 不支援兩個 --for 條件的 OR 語意；用 polling 代替
                  # K8s 1.29+ 新增 SuccessCriteriaMet condition，出現在 Complete 之前
                  DEADLINE=$(($(date +%s) + 1800))
                  until ${KUBECTL} get job presit-phase4-e2e-decision -n ${NS} \
                      -o jsonpath='{.status.conditions[*].type}' 2>/dev/null \
                      | grep -qE 'Complete|Failed|SuccessCriteriaMet'; do
                    [ $(date +%s) -ge ${DEADLINE} ] && echo "TIMEOUT" && exit 1
                    sleep 15
                  done
                  echo "Phase 4 done: $(${KUBECTL} get job presit-phase4-e2e-decision -n ${NS} \
                      -o jsonpath='{.status.conditions[*].type}')"
                '''
            }
        }

        stage('Read Decision') {
            steps {
                script {
                    def log = sh(
                      script: "${env.KUBECTL} logs job/presit-phase4-e2e-decision -n ${env.NS}",
                      returnStdout: true)
                    def jsonLine = log.split('\n').find { it.contains('"decision"') }
                    echo "─────────────────────────────────────"
                    echo "  Pre-SIT 決策: ${jsonLine}"
                    echo "─────────────────────────────────────"
                    env.PRESIT_RESULT = (jsonLine != null && jsonLine.contains('"GO ✅"')) ? 'GO' : 'NO-GO'
                    echo "PRESIT_RESULT = ${env.PRESIT_RESULT}"
                    if (env.PRESIT_RESULT == 'NO-GO') {
                        currentBuild.result = 'UNSTABLE'
                        echo '❌ Pre-SIT 未通過，不 promote，SIT 維持現況'
                    }
                }
            }
        }

        stage('Deploy SIT') {
            when { environment name: 'PRESIT_RESULT', value: 'GO' }
            steps {
                sh '''
                  # 冪等：apply sit namespace + postgres + services + ingress
                  ${KUBECTL} apply -f ${SIT_MANIFEST}/00-namespace.yaml
                  ${KUBECTL} apply -f ${SIT_MANIFEST}/05-config.yaml
                  ${KUBECTL} apply -f ${SIT_MANIFEST}/06-sealed-db-credentials.yaml 2>/dev/null || true
                  ${KUBECTL} apply -f ${SIT_MANIFEST}/10-postgres.yaml
                  ${KUBECTL} apply -f ${SIT_MANIFEST}/20-petclinic-services.yaml
                  ${KUBECTL} apply -f ${SIT_MANIFEST}/30-ingress.yaml
                  # Postgres 先 ready，再等 deployments
                  ${KUBECTL} -n ${SIT_NS} wait --for=condition=Ready pod -l app=postgres --timeout=120s
                  # Promote：將剛通過 Pre-SIT 的相同 image 設定到 SIT
                  for svc in customers-service vets-service visits-service api-gateway; do
                    IMAGE=$(${KUBECTL} -n ${NS} get deployment ${svc} \
                        -o jsonpath="{.spec.template.spec.containers[0].image}" 2>/dev/null)
                    if [ -n "${IMAGE}" ]; then
                      ${KUBECTL} -n ${SIT_NS} set image deployment/${svc} app=${IMAGE}
                      echo "Promoted ${svc} → ${IMAGE}"
                    else
                      echo "SKIP ${svc}: not found in ${NS}"
                    fi
                  done
                  ${KUBECTL} -n ${SIT_NS} rollout status deployment --all --timeout=300s
                '''
                echo '✅ Pre-SIT 通過，SIT 已部署，促進完成'
            }
        }

        stage('Check SIT State') {
            steps {
                sh '''
                  echo "SIT 4 deployment 目前 image："
                  for d in customers-service vets-service visits-service api-gateway; do
                    printf "  %-22s " "${d}:"
                    ${KUBECTL} -n ${SIT_NS} get deployment ${d} \
                        -o jsonpath="{.spec.template.spec.containers[0].image}" 2>/dev/null || echo "(not found)"
                    echo
                  done
                '''
            }
        }
    }

    post {
        success  { echo '✅ Pipeline 完成，SIT 已更新至最新通過版本' }
        unstable { echo '❌ Pre-SIT 未通過，SIT 維持原版本' }
        always   { echo '─── 詳細證據請執行 scripts/collect-evidence.sh ───' }
    }
}
