// v2.3 Stage C: Pre-SIT BDD orchestrator
//
// 範圍：Jenkins 在 Kind 內當 orchestrator
//   - 觸發既有 BDD K8s Jobs (Phase 1-4)
//   - 等綠燈
//   - 讀 decision JSON
//   - 顯示 promote 指示
//
// 留 v2.4 backlog：
//   - mvn package + docker build/push 改用 kaniko 或 DinD sidecar
//   - 加上 git webhook (Kind 收不到 GitHub webhook，需 polling 或 SMEE proxy)

pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        KUBECTL = '/shared/kubectl'
        NS      = 'pre-sit'
        SIT_NS  = 'sit'
    }

    stages {
        stage('Preflight') {
            steps {
                sh '''
                  ${KUBECTL} version --client=true 2>&1 | head -3
                  ${KUBECTL} get ns ${NS} >/dev/null 2>&1 || { echo "Namespace ${NS} not found"; exit 1; }
                  ${KUBECTL} -n argocd get application petclinic-pre-sit petclinic-sit
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
                sh '${KUBECTL} apply -f manifests/pre-sit/30-bdd-jobs.yaml'
            }
        }

        stage('Wait Phase 1-4') {
            steps {
                sh '''
                  # kubectl wait 不支援兩個 --for 條件的 OR 語意；用 polling 代替
                  DEADLINE=$(($(date +%s) + 1800))
                  until ${KUBECTL} get job presit-phase4-e2e-decision -n ${NS} \
                      -o jsonpath='{.status.conditions[0].type}' 2>/dev/null \
                      | grep -qE 'Complete|Failed'; do
                    [ $(date +%s) -ge ${DEADLINE} ] && echo "TIMEOUT" && exit 1
                    sleep 15
                  done
                  echo "Phase 4 done: $(${KUBECTL} get job presit-phase4-e2e-decision -n ${NS} \
                      -o jsonpath='{.status.conditions[0].type}')"
                '''
            }
        }

        stage('Read decision') {
            steps {
                script {
                    def log = sh(
                      script: "${env.KUBECTL} logs job/presit-phase4-e2e-decision -n ${env.NS}",
                      returnStdout: true)
                    def jsonLine = log.split('\n').find { it.contains('"decision"') }
                    echo "─────────────────────────────────────"
                    echo "  Pre-SIT 決策: ${jsonLine}"
                    echo "─────────────────────────────────────"
                    if (jsonLine != null && jsonLine.contains('"GO ✅"')) {
                        echo '✅ Pre-SIT 通過。建議 promote: docker tag :sha-XXX → :sit-approved → push'
                        echo '   接下來 Argo Image Updater 偵測 + ArgoCD AutoSync 會自動更新 SIT'
                    } else {
                        currentBuild.result = 'UNSTABLE'
                        echo '❌ Pre-SIT 未通過，不 promote'
                    }
                }
            }
        }

        stage('Check SIT app state') {
            steps {
                sh '${KUBECTL} -n argocd get application petclinic-sit'
                sh '''
                  echo "SIT 4 deployment 目前 image：";
                  for d in customers-service vets-service visits-service api-gateway; do
                    printf "  %-22s " "${d}:"
                    ${KUBECTL} -n ${SIT_NS} get deployment ${d} -o jsonpath="{.spec.template.spec.containers[0].image}"
                    echo
                  done
                '''
            }
        }
    }

    post {
        always {
            echo '─── Pipeline 結束。詳細證據請執行 scripts/collect-evidence.sh ───'
        }
    }
}
