set -e
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION_CODE="ap-northeast-2"
EKS_CLUSTER_NAME="wsc2026-eks-cluster"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

eksctl create iamserviceaccount \
  --name fluent-bit-sa \
  --region $REGION_CODE \
  --cluster $EKS_CLUSTER_NAME \
  --namespace observability \
  --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess \
  --approve

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
        Regex               log .*access method=.*

    [FILTER]
        Name                parser
        Match               kube.*
        Key_Name            log
        Parser              access_log
        Reserve_Data        On

    [FILTER]
        Name                lua
        Match               kube.*
        script              status.lua
        call                add_level

    [FILTER]
        Name                modify
        Match               kube.*
        Remove              remote_addr
        Remove              user_agent
        Remove              stream
        Remove              logtag

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
    function add_level(tag, timestamp, record)
        local status = record["status"]
        if status ~= nil then
            local code = tonumber(status)
            if code ~= nil and code >= 200 and code < 400 then
                record["level"] = "INFO"
            else
                record["level"] = "ERROR"
            end
        else
            record["level"] = "INFO"
        end
        return 1, timestamp, record
    end
EOF

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

cat <<EOF > prometeus-sc.yaml
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
  metricLabelsAllowlist:
    - nodes=[*]

configmapReload:
  prometheus:
    enabled: true

prometheus-node-exporter:
  enabled: true

serverFiles:
  alerts:
    groups:
      - name: wsc2026-alerts
        rules:
          - alert: PodHighCPU
            expr: sum(rate(container_cpu_usage_seconds_total{image!=""}[1m])) by (pod, namespace) / sum(kube_pod_container_resource_limits{resource="cpu"}) by (pod, namespace) * 100 > 80
            for: 3m
            labels:
              severity: warning

          - alert: PodHighMemory
            expr: sum(container_memory_working_set_bytes{image!=""}) by (pod, namespace) / sum(kube_pod_container_resource_limits{resource="memory"}) by (pod, namespace) * 100 > 90
            for: 3m
            labels:
              severity: warning

          - alert: PodNotReady
            expr: kube_pod_status_phase{phase=~"Failed|Unknown|Pending"} > 0 or kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} > 0 or kube_pod_status_ready{condition="false"} > 0
            for: 3m
            labels:
              severity: critical

          - alert: HighErrorRate
            expr: sum(rate(http_requests_total{status=~"5.."}[1m])) / sum(rate(http_requests_total[1m])) * 100 > 5
            for: 1m
            labels:
              severity: critical

          - alert: HighLatency
            expr: sum(rate(http_request_duration_seconds_sum[1m])) / sum(rate(http_request_duration_seconds_count[1m])) > 3
            for: 1m
            labels:
              severity: warning

          - alert: PodCrashLooping
            expr: kube_pod_container_status_restarts_total{namespace="wsc2026"} > 3
            for: 3m
            labels:
              severity: critical
EOF

kubectl apply -f ./prometeus-sc.yaml
rm -f prometeus-sc.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade -i prometheus prometheus-community/prometheus \
  -n observability \
  -f ./prometeus-values.yaml
rm -f prometeus-values.yaml

kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml

cat <<EOF > grafana-values.yaml
adminUser: admin
adminPassword: Skills\$#\$@!

nodeSelector:
  wsc2026/node: addon

service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"

grafana.ini:
  server:
    root_url: "%(protocol)s://%(domain)s:%(http_port)s/"

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-server.observability.svc.wsc2026.skills.local
        access: proxy
        isDefault: true
      - name: Alertmanager
        type: alertmanager
        url: http://prometheus-alertmanager.observability.svc.wsc2026.skills.local
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
              "title": "All Node CPU",
              "type": "timeseries",
              "gridPos": { "x": 0, "y": 1, "w": 8, "h": 6 },
              "id": 2,
              "targets": [{ "expr": "sum(node_cpu_seconds_total{mode!=\"idle\"}) by (node)", "legendFormat": "{{node}}" }]
            },
            {
              "title": "All Node Memory",
              "type": "timeseries",
              "gridPos": { "x": 8, "y": 1, "w": 8, "h": 6 },
              "id": 3,
              "targets": [{ "expr": "sum(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) by (node)", "legendFormat": "{{node}}" }]
            },
            {
              "title": "All Available Nodes",
              "type": "stat",
              "gridPos": { "x": 16, "y": 1, "w": 8, "h": 6 },
              "id": 4,
              "targets": [{ "expr": "sum(kube_node_status_condition{condition=\"Ready\",status=\"true\"})", "legendFormat": "Nodes Ready" }]
            },
            {
              "type": "row",
              "title": "Pod",
              "gridPos": { "x": 0, "y": 7, "w": 24, "h": 1 },
              "id": 5,
              "collapsed": false
            },
            {
              "title": "All Pod CPU",
              "type": "timeseries",
              "gridPos": { "x": 0, "y": 8, "w": 6, "h": 6 },
              "id": 6,
              "targets": [{ "expr": "sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[5m])) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "All Pod Memory",
              "type": "timeseries",
              "gridPos": { "x": 6, "y": 8, "w": 6, "h": 6 },
              "id": 7,
              "targets": [{ "expr": "sum(container_memory_working_set_bytes{container!=\"\"}) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "All Pending Pods",
              "type": "stat",
              "gridPos": { "x": 12, "y": 8, "w": 6, "h": 6 },
              "id": 8,
              "targets": [{ "expr": "sum(kube_pod_status_phase{phase=\"Pending\"})", "legendFormat": "Pending Pods" }]
            },
            {
              "title": "All Pod Restarts",
              "type": "timeseries",
              "gridPos": { "x": 18, "y": 8, "w": 6, "h": 6 },
              "id": 9,
              "targets": [{ "expr": "sum(kube_pod_container_status_restarts_total) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "type": "row",
              "title": "Application Pod",
              "gridPos": { "x": 0, "y": 14, "w": 24, "h": 1 },
              "id": 10,
              "collapsed": false
            },
            {
              "title": "App Pod CPU",
              "type": "timeseries",
              "gridPos": { "x": 0, "y": 15, "w": 6, "h": 6 },
              "id": 11,
              "targets": [{ "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"wsc2026\"}[5m])) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "App Pod Memory",
              "type": "timeseries",
              "gridPos": { "x": 6, "y": 15, "w": 6, "h": 6 },
              "id": 12,
              "targets": [{ "expr": "sum(container_memory_working_set_bytes{namespace=\"wsc2026\"}) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "App Running",
              "type": "stat",
              "gridPos": { "x": 12, "y": 15, "w": 4, "h": 6 },
              "id": 13,
              "targets": [{ "expr": "sum(kube_pod_status_phase{namespace=\"wsc2026\", phase=\"Running\"})", "legendFormat": "Running" }]
            },
            {
              "title": "App Restarts",
              "type": "timeseries",
              "gridPos": { "x": 16, "y": 15, "w": 4, "h": 6 },
              "id": 14,
              "targets": [{ "expr": "sum(kube_pod_container_status_restarts_total{namespace=\"wsc2026\"}) by (pod)", "legendFormat": "{{pod}}" }]
            },
            {
              "title": "App Pending",
              "type": "stat",
              "gridPos": { "x": 20, "y": 15, "w": 4, "h": 6 },
              "id": 15,
              "targets": [{ "expr": "sum(kube_pod_status_phase{namespace=\"wsc2026\", phase=\"Pending\"})", "legendFormat": "Pending" }]
            },
            {
              "type": "row",
              "title": "Application Traffic",
              "gridPos": { "x": 0, "y": 21, "w": 24, "h": 1 },
              "id": 16,
              "collapsed": false
            },
            {
              "title": "App Request Count",
              "type": "timeseries",
              "gridPos": { "x": 0, "y": 22, "w": 6, "h": 6 },
              "id": 17,
              "targets": [{ "expr": "sum(rate(nginx_ingress_controller_requests{namespace=\"wsc2026\"}[5m]))", "legendFormat": "Requests/sec" }]
            },
            {
              "title": "App Response Time",
              "type": "timeseries",
              "gridPos": { "x": 6, "y": 22, "w": 6, "h": 6 },
              "id": 18,
              "targets": [{ "expr": "sum(rate(nginx_ingress_controller_request_duration_seconds_sum{namespace=\"wsc2026\"}[5m])) / sum(rate(nginx_ingress_controller_request_duration_seconds_count{namespace=\"wsc2026\"}[5m]))", "legendFormat": "Latency (s)" }]
            },
            {
              "title": "App Status Code",
              "type": "timeseries",
              "gridPos": { "x": 12, "y": 22, "w": 6, "h": 6 },
              "id": 19,
              "targets": [{ "expr": "sum(rate(nginx_ingress_controller_requests{namespace=\"wsc2026\"}[5m])) by (status)", "legendFormat": "Status {{status}}" }]
            },
            {
              "title": "App Application Logs",
              "type": "logs",
              "datasource": "Loki",
              "gridPos": { "x": 18, "y": 22, "w": 6, "h": 6 },
              "id": 20,
              "targets": [{ "expr": "{namespace=\"wsc2026\"} | json", "refId": "A" }]
            },
            {
              "type": "row",
              "title": "Alert",
              "gridPos": { "x": 0, "y": 28, "w": 24, "h": 1 },
              "id": 21,
              "collapsed": false
            },
            {
              "title": "Alertmanager 알림 현황",
              "type": "state-timeline",
              "gridPos": { "x": 0, "y": 29, "w": 24, "h": 6 },
              "id": 22,
              "targets": [{ "expr": "ALERTS{alertstate=\"firing\"}", "legendFormat": "{{alertname}}" }]
            }
          ],
          "schemaVersion": 38,
          "refresh": "5s"
        }
EOF

helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update
helm upgrade -i grafana grafana-community/grafana \
  -n observability \
  -f ./grafana-values.yaml
rm -f grafana-values.yaml