#!/usr/bin/env bash
# Bring up Kind cluster + local Docker registry, then connect them.
# Idempotent: safe to re-run.
set -euo pipefail

REG_NAME='kind-registry'
REG_PORT='5000'
CLUSTER_NAME='presit'

# 1) Local registry container
if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || echo false)" != 'true' ]; then
  echo "[kind] starting local registry ${REG_NAME} on :${REG_PORT}"
  docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --name "${REG_NAME}" registry:2
fi

# 2) Kind cluster
if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "[kind] creating cluster ${CLUSTER_NAME}"
  kind create cluster --config "$(dirname "$0")/kind-config.yaml" --wait 120s
fi

# 3) Connect registry to kind network
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}")" = 'null' ]; then
  echo "[kind] connecting ${REG_NAME} to kind network"
  docker network connect kind "${REG_NAME}"
fi

# 4) Document the registry inside the cluster
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

kubectl cluster-info --context kind-${CLUSTER_NAME}
echo "[kind] ✅ ready"
