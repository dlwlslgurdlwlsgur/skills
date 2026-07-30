#!/bin/bash
set -x
REGION="ap-northeast-2"
PROJECT="wsc2026"
CLUSTER_NAME="skills-cluster"

aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 1. Prometheus & Grafana 설치
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set alertmanager.enabled=false \
  --set grafana.adminPassword="admin" \
  --set prometheus.prometheusSpec.storageSpec.emptyDir.medium="Memory"

# 2. Loki & Promtail 설치 (앱에서 출력하는 stdout 로그를 수집해 Grafana에서 악성 헤더 분석)
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  --set loki.persistence.enabled=false \
  --set promtail.enabled=true

echo "Grafana 접속: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "ID: admin / PW: admin"
echo "Grafana에서 Loki Datasource (http://loki:3100) 추가 후 로그 확인 가능"