#!/usr/bin/env bash
# v2.3 Observability：安裝 Prometheus + Grafana + Loki
#
# 執行前提：Kind 叢集已啟動，kubectl context 已指向 presit
# 安裝完成後：
#   Grafana  → http://<node-ip>:30300  admin / presit-admin
#   Prometheus → kubectl port-forward -n monitoring svc/kube-prometheus-kube-prome-prometheus 9090:9090

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "[monitoring] Step 1: 建立 namespace"
kubectl apply -f "${ROOT}/manifests/monitoring/00-namespace.yaml"

echo "[monitoring] Step 2: 安裝 kube-prometheus-stack (Prometheus + Grafana)"
helm upgrade --install kube-prometheus \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "${ROOT}/manifests/monitoring/values-kube-prometheus.yaml" \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.dashboards.label=grafana_dashboard \
  --timeout 10m \
  --wait

echo "[monitoring] Step 3: 安裝 Loki Stack (Loki + Promtail)"
helm upgrade --install loki \
  grafana/loki-stack \
  --namespace monitoring \
  --values "${ROOT}/manifests/monitoring/values-loki.yaml" \
  --timeout 5m \
  --wait

echo "[monitoring] Step 4: 套用 ServiceMonitors + Grafana Dashboards"
kubectl apply -f "${ROOT}/manifests/monitoring/10-servicemonitors.yaml"
kubectl apply -f "${ROOT}/manifests/monitoring/20-dashboards.yaml"

echo "[monitoring] Step 5: 驗證部署狀態"
kubectl get pods -n monitoring
kubectl get servicemonitors -n monitoring

NODE_IP=$(kubectl get node presit-control-plane \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Grafana   http://${NODE_IP}:30300"
echo "  帳號      admin / presit-admin"
echo "  Dashboards:"
echo "    - Pre-SIT Pipeline Overview"
echo "    - Pre-SIT / SIT Logs (Loki)"
echo ""
echo "  Prometheus (port-forward):"
echo "    kubectl port-forward -n monitoring svc/kube-prometheus-kube-prome-prometheus 9090:9090"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
