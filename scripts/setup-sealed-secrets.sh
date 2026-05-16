#!/usr/bin/env bash
# v2.3 Sealed Secrets：安裝 controller + 套用 SealedSecrets
#
# 執行前提：Kind 叢集已啟動，kubeseal 已安裝（~/.local/bin/kubeseal）
# 重新封存：修改 seal-new-secret 函式後重跑

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "[sealed-secrets] Step 1: 安裝 Sealed Secrets controller"
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets 2>/dev/null || true
helm repo update sealed-secrets 2>/dev/null | tail -1

helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --values "${ROOT}/manifests/sealed-secrets/values.yaml" \
  --wait

echo "[sealed-secrets] Step 2: 等待 controller 就緒"
kubectl rollout status deployment/sealed-secrets-controller -n kube-system --timeout=60s

echo "[sealed-secrets] Step 3: 套用 SealedSecrets"
kubectl apply -f "${ROOT}/manifests/pre-sit/06-sealed-db-credentials.yaml"
kubectl apply -f "${ROOT}/manifests/sit/06-sealed-db-credentials.yaml"

echo "[sealed-secrets] Step 4: 驗證解封"
for NS in pre-sit sit; do
  USER=$(kubectl get secret petclinic-db-credentials -n "${NS}" \
    -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
  echo "  ${NS}: POSTGRES_USER = ${USER} ✅"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Public key 查看（備份用）："
echo "    kubeseal --fetch-cert --controller-name=sealed-secrets-controller \\"
echo "             --controller-namespace=kube-system > pub-cert.pem"
echo ""
echo "  封存新 Secret 的方法："
echo "    kubectl create secret generic <name> -n <ns> \\"
echo "      --from-literal=KEY=VALUE --dry-run=client -o yaml \\"
echo "      | kubeseal --controller-name=sealed-secrets-controller \\"
echo "                 --controller-namespace=kube-system --format yaml"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
