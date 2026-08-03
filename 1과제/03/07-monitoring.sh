#!/bin/bash
set -x

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION_CODE="ap-northeast-2"
EKS_CLUSTER_NAME="wsc2026-eks-cluster"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

# 1. Fluent Bit IAM Service Account
eksctl create iamserviceaccount \
  --name fluent-bit-sa \
  --region $REGION_CODE \
  --cluster $EKS_CLUSTER_NAME \
  --namespace observability \
  --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess \
  --approve

# 2. Fluent Bit ConfigMap (Lua Script Update)
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: observability
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush               1
        Grace               5
        Daemon              off
        Log_Level           info
        Parsers_File        /fluent-bit/etc/parsers.conf

    [INPUT]
        Name                tail
        Path                /var/log/containers/*wsc2026*.log
        Parser              cri
        Tag                 kube.*
        Refresh_Interval    10
        Mem_Buf_Limit       50M

    [FILTER]
        Name                grep
        Match               kube.*
        Exclude             log .*path=/health.*

    [FILTER]
        Name                parser
        Match               kube.*
        Key_Name            log
        Parser              access_log
        Reserve_Data        True
        Preserve_Key        False

    [FILTER]
        Name                lua
        Match               kube.*
        script              status.lua
        call                format_log

    [OUTPUT]
        Name                cloudwatch_logs
        Match               kube.*
        region              ap-northeast-2
        Log_Group_Name      wsc2026-log-group
        Log_Stream_Name     wsc2026-log-stream
        Auto_Create_Group   true

  parsers.conf: |
    [PARSER]
        Name                cri
        Format              regex
        Regex               ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<log>.*)$
        Time_Key            time
        Time_Format         %Y-%m-%dT%H:%M:%S.%L%z

    [PARSER]
        Name                access_log
        Format              regex
        Regex               ^(?<timestamp>\d{4}\/\d{2}\/\d{2} \d{2}\:\d{2}\:\d{2}) access method=(?<method>[^ ]+) path=(?<path>[^ ]+) status=(?<status>[^ ]+) duration=(?<duration>[^ ]+) remote_addr=(?<remote_addr>[^ ]+) user_agent="(?<user_agent>[^"]+)"
        Time_Key            timestamp
        Time_Format         %Y/%m/%d %H:%M:%S

  status.lua: |
    function format_log(tag, timestamp, record)
        local status = record["status"]
        if status ~= nil then
            local code = tonumber(status)
            if code ~= nil then
                if code >= 500 then
                    record["level"] = "ERROR"
                elseif code >= 400 then
                    record["level"] = "WARN"
                else
                    record["level"] = "INFO"
                end
            end
            record["remote_addr"] = nil
            record["user_agent"] = nil
            record["stream"] = nil
            record["logtag"] = nil
        end
        return 1, timestamp, record
    end
EOF

# 3. Fluent Bit DaemonSet
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: observability 
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    metadata:
      labels:
        app: fluent-bit
    spec:
      serviceAccountName: fluent-bit-sa
      containers:
        - name: fluent-bit
          image: fluent/fluent-bit:latest
          ports:
            - containerPort: 2020
          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: config
              mountPath: /fluent-bit/etc/
      volumes:
        - name: varlog
          hostPath:
            path: /var/log
        - name: config
          configMap:
            name: fluent-bit-config
      nodeSelector:
        wsc2026/node: application
EOF

# 4. EBS CSI Driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --region $REGION_CODE \
  --cluster $EKS_CLUSTER_NAME \
  --namespace kube-system \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2 \
  --approve

eksctl create addon \
  --name aws-ebs-csi-driver \
  --region $REGION_CODE \
  --cluster $EKS_CLUSTER_NAME \
  --service-account-role-arn arn:aws:iam::$ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole \
  --force

# 5. StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: wsc2026-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
allowVolumeExpansion: true
EOF

# Prometheus 메트릭 수집을 보장하기 위한 App Deployment 패치
kubectl patch deployment wsc2026-book-deploy -n wsc2026 -p '{"spec":{"template":{"metadata":{"annotations":{"prometheus.io/scrape":"true","prometheus.io/port":"8080","prometheus.io/path":"/metrics"}}}}}' 2>/dev/null || true

# 6. Prometheus Values (Alert Rules 완벽 매핑)
cat <<EOF > prometeus-values.yaml
server:
  retention: "7d"
  nodeSelector:
    wsc2026/node: addon
  persistentVolume:
    enabled: true

alertmanager:
  enabled: true
  nodeSelector:
    wsc2026/node: addon

prometheus-pushgateway:
  enabled: false

kube-state-metrics:
  enabled: true
  nodeSelector:
    wsc2026/node: addon

serverFiles:
  rules:
    groups:
      - name: wsc2026-alerts
        rules:
          - alert: PodHighCPU
            expr: sum(rate(container_cpu_usage_seconds_total{container!="", pod=~".*"}[1m])) by (pod) / sum(kube_pod_container_resource_limits{resource="cpu", pod=~".*"}) by (pod) > 0.8
            for: 3m
            labels:
              severity: warning

          - alert: PodHighMemory
            expr: sum(container_memory_working_set_bytes{container!="", pod=~".*"}) by (pod) / sum(kube_pod_container_resource_limits{resource="memory", pod=~".*"}) by (pod) > 0.9
            for: 3m
            labels:
              severity: warning

          - alert: PodNotReady
            expr: kube_pod_status_ready{condition="true"} == 0 or kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} > 0
            for: 3m
            labels:
              severity: critical

          - alert: HighErrorRate
            expr: sum(rate(http_requests_total{status=~"4..|5.."}[1m])) / sum(rate(http_requests_total[1m])) > 0.05
            for: 1m
            labels:
              severity: critical

          - alert: HighLatency
            expr: (sum(rate(http_request_duration_seconds_sum[1m])) / sum(rate(http_request_duration_seconds_count[1m]))) > 3
            for: 1m
            labels:
              severity: warning

          - alert: PodCrashLooping
            expr: kube_pod_container_status_restarts_total{namespace="wsc2026"} > 3
            for: 3m
            labels:
              severity: critical
EOF

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade -i prometheus prometheus-community/prometheus \
  -n observability \
  -f ./prometeus-values.yaml
rm -f prometeus-values.yaml

# 7. Grafana Values (Dashboard & Datascources)
cat <<EOF > grafana-values.yaml
adminUser: admin
adminPassword: Skills\$#\$@!

nodeSelector:
  wsc2026/node: addon

serviceAccount:
  create: false
  name: fluent-bit-sa

service:
  enabled: true
  type: LoadBalancer
  port: 80
  targetPort: 3000
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/api/health"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "3000"

grafana.ini:
  server:
    root_url: "%(protocol)s://%(domain)s:%(http_port)s/"

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-server.observability.svc.cluster.local
        access: proxy
        isDefault: true
      - name: Alertmanager
        type: alertmanager
        url: http://prometheus-alertmanager.observability.svc.cluster.local
        access: proxy
        jsonData:
          implementation: prometheus
      - name: CloudWatch
        type: cloudwatch
        access: proxy
        jsonData:
          authType: default
          defaultRegion: ap-northeast-2

dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

dashboards:
  default:
    wsc2026-custom-dashboard:
      json: |
        {
          "id": null,
          "title": "wsc2026-grafana-dashboard",
          "tags": ["wsc2026", "kubernetes"],
          "style": "dark",
          "timezone": "browser",
          "editable": true,
          "graphTooltip": 1,
          "panels": [
            {
              "type": "row",
              "title": "Node",
              "gridPos": { "x": 0, "y": 0, "w": 24, "h": 1 },
              "id": 1,
              "collapsed": false
            },
            {
              "title": "Node CPU (%)",
              "type": "timeseries",
              "gridPos": { "x": 0, "y": 1, "w": 12, "h": 6 },
              "id": 2,
              "fieldConfig": {
                "defaults": {
                  "min": 0,
                  "max": 100,
                  "unit": "percent",
                  "thresholds": {
                    "mode": "absolute",
                    "steps": [
                      { "color": "green", "value": null },
                      { "color": "yellow", "value": 60 },
                      { "color": "red", "value": 80 }
                    ]
                  }
                }
              },
              "targets": [{ "expr": "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)", "legendFormat": "{{instance}}" }]
            },
            {
              "title": "Node Memory (%)",
              "type": "timeseries",
              "gridPos": { "x": 12, "y": 1, "w": 12, "h": 6 },
              "id": 3,
              "fieldConfig": {
                "defaults": {
                  "min": 0,
                  "max": 100,
                  "unit": "percent",
                  "thresholds": {
                    "mode": "absolute",
                    "steps": [
                      { "color": "green", "value": null },
                      { "color": "yellow", "value": 60 },
                      { "color": "red", "value": 80 }
                    ]
                  }
                }
              },
              "targets": [{ "expr": "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))", "legendFormat": "{{instance}}" }]
            },
            {
              "title": "Available Nodes",
              "type": "stat",
              "gridPos": { "x": 0, "y": 7, "w": 12, "h": 3 },
              "id": 4,
              "options": {
                "reduceOptions": { "calcs": ["lastNotNull"] },
                "orientation": "horizontal",
                "textMode": "value_and_name",
                "colorMode": "value",
                "graphMode": "none"
              },
              "fieldConfig": {
                "defaults": {
                  "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }] }
                }
              },
              "targets": [{ "expr": "sum(kube_node_labels{label_wsc2026_node=\"addon\"})", "legendFormat": "wsc2026-addon-nodegroup" }]
            },
            {
              "title": "",
              "type": "stat",
              "gridPos": { "x": 12, "y": 7, "w": 12, "h": 3 },
              "id": 5,
              "options": {
                "reduceOptions": { "calcs": ["lastNotNull"] },
                "orientation": "horizontal",
                "textMode": "value_and_name",
                "colorMode": "value",
                "graphMode": "none"
              },
              "fieldConfig": {
                "defaults": {
                  "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }] }
                }
              },
              "targets": [{ "expr": "sum(kube_node_labels{label_wsc2026_node=\"application\"})", "legendFormat": "wsc2026-workload-ng" }]
            },
            {
              "type": "row",
              "title": "Pod",
              "gridPos": { "x": 0, "y": 10, "w": 24, "h": 1 },
              "id": 6,
              "collapsed": false
            },
            {
              "title": "Pod CPU",
              "type": "timeseries",
              "gridPos": { "x": 0, "y": 11, "w": 12, "h": 6 },
              "id": 7,
              "fieldConfig": {
                "defaults": { "min": 0, "unit": "none" }
              },
              "targets": [{ "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"wsc2026\", container!=\"\"}[5m])) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "Pod Memory",
              "type": "timeseries",
              "gridPos": { "x": 12, "y": 11, "w": 12, "h": 6 },
              "id": 8,
              "fieldConfig": {
                "defaults": { "min": 0, "unit": "bytes" }
              },
              "targets": [{ "expr": "sum(container_memory_working_set_bytes{namespace=\"wsc2026\", container!=\"\"}) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "Pending Pods",
              "type": "stat",
              "gridPos": { "x": 0, "y": 17, "w": 12, "h": 5 },
              "id": 9,
              "options": {
                "textMode": "value",
                "graphMode": "none",
                "colorMode": "value"
              },
              "fieldConfig": {
                "defaults": {
                  "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "red", "value": 1 } ] }
                }
              },
              "targets": [{ "expr": "sum(kube_pod_status_phase{namespace=\"wsc2026\", phase=\"Pending\"})", "legendFormat": "Pending Pods" }]
            },
            {
              "title": "Pod Restarts",
              "type": "stat",
              "gridPos": { "x": 12, "y": 17, "w": 12, "h": 5 },
              "id": 10,
              "options": {
                "reduceOptions": { "calcs": ["lastNotNull"] },
                "textMode": "value_and_name",
                "graphMode": "area",
                "colorMode": "value"
              },
              "fieldConfig": {
                "defaults": {
                  "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "red", "value": 1 } ] }
                }
              },
              "targets": [{ "expr": "sum(kube_pod_container_status_restarts_total{namespace=\"wsc2026\"}) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "type": "row",
              "title": "Application Pod",
              "gridPos": { "x": 0, "y": 22, "w": 24, "h": 1 },
              "id": 11,
              "collapsed": false
            },
            {
              "title": "App Pod CPU",
              "type": "timeseries",
              "gridPos": { "x": 0, "y": 23, "w": 12, "h": 6 },
              "id": 12,
              "fieldConfig": {
                "defaults": { "min": 0, "unit": "none" }
              },
              "targets": [{ "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"wsc2026\", pod=~\"wsc2026-book-deploy.*\", container!=\"\"}[5m])) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "App Pod Memory",
              "type": "timeseries",
              "gridPos": { "x": 12, "y": 23, "w": 12, "h": 6 },
              "id": 13,
              "fieldConfig": {
                "defaults": { "min": 0, "unit": "bytes" }
              },
              "targets": [{ "expr": "sum(container_memory_working_set_bytes{namespace=\"wsc2026\", pod=~\"wsc2026-book-deploy.*\", container!=\"\"}) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "App Running",
              "type": "stat",
              "gridPos": { "x": 0, "y": 29, "w": 8, "h": 5 },
              "id": 14,
              "options": {
                "textMode": "value",
                "graphMode": "area",
                "colorMode": "value"
              },
              "fieldConfig": {
                "defaults": {
                  "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }] }
                }
              },
              "targets": [{ "expr": "sum(kube_pod_status_phase{namespace=\"wsc2026\", phase=\"Running\", pod=~\"wsc2026-book-deploy.*\"})", "legendFormat": "Running" }]
            },
            {
              "title": "App Restarts",
              "type": "stat",
              "gridPos": { "x": 8, "y": 29, "w": 8, "h": 5 },
              "id": 15,
              "options": {
                "reduceOptions": { "calcs": ["lastNotNull"] },
                "textMode": "value_and_name",
                "graphMode": "area",
                "colorMode": "value"
              },
              "fieldConfig": {
                "defaults": {
                  "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "red", "value": 1 } ] }
                }
              },
              "targets": [{ "expr": "sum(kube_pod_container_status_restarts_total{namespace=\"wsc2026\", pod=~\"wsc2026-book-deploy.*\"}) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "App Pending",
              "type": "stat",
              "gridPos": { "x": 16, "y": 29, "w": 8, "h": 5 },
              "id": 16,
              "options": {
                "textMode": "value",
                "graphMode": "none",
                "colorMode": "value"
              },
              "fieldConfig": {
                "defaults": {
                  "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "red", "value": 1 } ] }
                }
              },
              "targets": [{ "expr": "sum(kube_pod_status_phase{namespace=\"wsc2026\", phase=\"Pending\", pod=~\"wsc2026-book-deploy.*\"})", "legendFormat": "Pending" }]
            },
            {
              "type": "row",
              "title": "Application Traffic",
              "gridPos": { "x": 0, "y": 34, "w": 24, "h": 1 },
              "id": 17,
              "collapsed": false
            },
            {
              "title": "Request Count",
              "type": "timeseries",
              "gridPos": { "x": 0, "y": 35, "w": 8, "h": 6 },
              "id": 18,
              "fieldConfig": {
                "defaults": { "min": 0 }
              },
              "targets": [{ "expr": "sum(rate(http_requests_total[1m])) * 60 or vector(0)", "legendFormat": "Requests/min" }]
            },
            {
              "title": "Response Time",
              "type": "timeseries",
              "gridPos": { "x": 8, "y": 35, "w": 8, "h": 6 },
              "id": 19,
              "fieldConfig": {
                "defaults": {
                  "unit": "ms",
                  "min": 0,
                  "custom": { "showPoints": "always", "drawStyle": "line" }
                }
              },
              "targets": [{ "expr": "(sum(rate(http_request_duration_seconds_sum[1m])) / sum(rate(http_request_duration_seconds_count[1m]))) * 1000 or vector(0)", "legendFormat": "Avg Response Time" }]
            },
            {
              "title": "Status Codes",
              "type": "timeseries",
              "gridPos": { "x": 16, "y": 35, "w": 8, "h": 6 },
              "id": 20,
              "fieldConfig": {
                "defaults": { "min": 0, "custom": { "showPoints": "always", "drawStyle": "line" } }
              },
              "targets": [
                { "expr": "sum(rate(http_requests_total{status=~\"2..\"}[1m])) * 60 or vector(0)", "legendFormat": "2XX" },
                { "expr": "sum(rate(http_requests_total{status=~\"4..\"}[1m])) * 60 or vector(0)", "legendFormat": "4XX" },
                { "expr": "sum(rate(http_requests_total{status=~\"5..\"}[1m])) * 60 or vector(0)", "legendFormat": "5XX" },
                { "expr": "vector(0)", "legendFormat": "ELB 4XX" },
                { "expr": "vector(0)", "legendFormat": "ELB 5XX" }
              ]
            },
            {
              "title": "Application Logs",
              "type": "logs",
              "datasource": "CloudWatch",
              "gridPos": { "x": 0, "y": 41, "w": 24, "h": 8 },
              "id": 21,
              "targets": [
                {
                  "datasource": { "type": "cloudwatch", "uid": "CloudWatch" },
                  "queryMode": "Logs",
                  "region": "ap-northeast-2",
                  "logGroupNames": ["wsc2026-log-group"],
                  "expression": "fields @timestamp, @message | filter @message not like /health/ | sort @timestamp desc | limit 100",
                  "refId": "A"
                }
              ]
            },
            {
              "type": "row",
              "title": "Alerts",
              "gridPos": { "x": 0, "y": 49, "w": 24, "h": 1 },
              "id": 22,
              "collapsed": false
            },
            {
              "title": "Active Alerts",
              "type": "alertlist",
              "gridPos": { "x": 0, "y": 50, "w": 24, "h": 6 },
              "id": 23,
              "options": {
                "showOptions": false,
                "viewMode": "list",
                "stateFilter": { "firing": true, "pending": false, "normal": false }
              }
            }
          ],
          "schemaVersion": 38,
          "refresh": "5s"
        }
EOF

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade -i grafana grafana/grafana \
  -n observability \
  -f ./grafana-values.yaml
rm -f grafana-values.yaml