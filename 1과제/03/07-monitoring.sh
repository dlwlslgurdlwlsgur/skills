#!/bin/bash
set -x

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


