ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION_CODE="ap-northeast-2"
EKS_CLUSTER_NAME="wsc2026-eks-cluster"
APP_EKS_NODE_GROUP_NAME="wsc2026-workload-node"
ALB_SECURITY_GROUP_NAME="wsc2026-app-alb-sg"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }



CLUSTER_NAME="wsc2026-eks-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
eksctl utils write-kubeconfig --name $CLUSTER_NAME
eksctl utils associate-iam-oidc-provider --approve --cluster $CLUSTER_NAME
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root"
aws eks associate-access-policy \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster



## cord dns
kubectl get configmaps coredns -n kube-system -o yaml > coredns.yaml
sed -i "s|cluster.local|wsc2026.skills.local|g" ./coredns.yaml
kubectl apply -f ./coredns.yaml --force
rm -rf ./coredns.yaml
kubectl rollout restart deploy/coredns -n kube-system


## namespace
kubectl create ns wsc2026
kubectl create ns observability


## fluent-bit
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


## sa
eksctl create iamserviceaccount \
  --name wsc2026-book-sa \
  --region=$REGION_CODE \
  --cluster $EKS_CLUSTER_NAME \
  --namespace=wsc2026 \
  --attach-policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" \
  --override-existing-serviceaccounts \
  --approve


## kms
KMS_KEY_ALIASE_NAME="alias/wsc2026-db-kms"
ROLE_ARN=$(eksctl get iamserviceaccount --cluster $EKS_CLUSTER_NAME --name wsc2026-book-sa --namespace wsc2026 --region $REGION_CODE --output json | jq -r '.[].status.roleARN')
ROLE_NAME=$(aws iam get-role --role-name $(aws iam list-roles --query "Roles[?Arn=='$ROLE_ARN'].RoleName" --output text) --query "Role.RoleName" --output text)
KMS_KEY_ARN=$(aws kms describe-key --key-id $KMS_KEY_ALIASE_NAME --query "KeyMetadata.Arn" --output text --region $REGION_CODE)
aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name allow-kms-decrypt \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Action\": \"kms:Decrypt\",
        \"Resource\": \"${KMS_KEY_ARN}\"
      }
    ]
  }"




REGION="ap-northeast-2"
ECR_NAME="wsc2026-book-ecr"
IMAGE_TAG="v1.0.0"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
IMAGE_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_NAME}:${IMAGE_TAG}"

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: book-config
  namespace: wsc2026
data:
  AWS_REGION: ap-northeast-2
  TABLE_NAME: wsc2026-book-table
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: wsc2026-book-pdb
  namespace: wsc2026
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: book
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wsc2026-book-deploy
  namespace: wsc2026
  labels:
    app: book
spec:
  replicas: 2
  selector:
    matchLabels:
      app: book
  template:
    metadata:
      labels:
        app: book
    spec:
      serviceAccountName: wsc2026-book-sa
      containers:
        - name: wsc2026-book-cnt
          image: $IMAGE_URL
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: "256m"
              memory: "512Mi"
            limits:
              cpu: "256m"
              memory: "512Mi"
          env:
            - name: AWS_REGION
              valueFrom:
                configMapKeyRef:
                  name: book-config
                  key: AWS_REGION
            - name: TABLE_NAME
              valueFrom:
                configMapKeyRef:
                  name: book-config
                  key: TABLE_NAME
          startupProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 0
            periodSeconds: 5
            timeoutSeconds: 10
            failureThreshold: 12
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 0
            periodSeconds: 5
            timeoutSeconds: 10
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 0
            periodSeconds: 5
            timeoutSeconds: 10
            failureThreshold: 6
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: book
      nodeSelector:
        wsc2026/node: application
---
apiVersion: v1
kind: Service
metadata:
  name: wsc2026-book-svc
  namespace: wsc2026
  annotations:
    service.kubernetes.io/topology-mode: "Auto"
spec:
  selector:
    app: book
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
EOF




cat <<EOF >> values.yaml
image:
  repository: 602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/amazon/aws-load-balancer-controller

serviceAccount:
  create: false
  name: aws-load-balancer-controller

cluster:
  dnsDomain: wsc2026.skills.local

nodeSelector:
  wsc2026/node: addon

enableShield: false
enableWaf: false
enableWafv2: false
EOF
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod +x get_helm.sh
./get_helm.sh
helm repo add eks https://aws.github.io/eks-charts
helm repo update
rm -f get_helm.sh
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  -f ./values.yaml
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
sleep 15





SG_NAME="wsc2026-app-alb-sg"
say "VPC 및 CloudFront Prefix List 조회 중..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=wsc2026-skills-vpc" \
  --query "Vpcs[0].VpcId" --output text)

PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing" \
  --query "PrefixLists[0].PrefixListId" --output text)

ok "VPC ID: $VPC_ID"
ok "CloudFront Prefix List ID: $PREFIX_LIST_ID"

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text)
if [ -z "$SECURITY_GROUP_ID" ] || [ "$SECURITY_GROUP_ID" = "None" ]; then
  SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Security group for Application ALB restricted to CloudFront" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SG_NAME}]" \
    --query "GroupId" --output text)
  ok "보안 그룹 생성 완료: $SECURITY_GROUP_ID"
else
  ok "기존 보안 그룹 발견: $SECURITY_GROUP_ID"
fi
aws ec2 authorize-security-group-ingress \
  --group-id "$SECURITY_GROUP_ID" \
  --ip-permissions "[
    {
      \"IpProtocol\": \"tcp\",
      \"FromPort\": 80,
      \"ToPort\": 80,
      \"PrefixListIds\": [{\"PrefixListId\": \"$PREFIX_LIST_ID\"}]
    }
  ]" 2>/dev/null || ok "인바운드 규칙이 이미 존재하거나 적용되었습니다."

cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wsc2026-book-ingress
  namespace: wsc2026
  annotations:
    alb.ingress.kubernetes.io/load-balancer-name: wsc2026-app-alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/security-groups: $SECURITY_GROUP_ID
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '5'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '3'
    alb.ingress.kubernetes.io/healthy-threshold-count: '3'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30
    alb.ingress.kubernetes.io/actions.response-403: >
      {"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","statusCode":"403","messageBody":"Restrict access to api"}}
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /v1/book
        pathType: Prefix
        backend:
          service:
            name: wsc2026-book-svc
            port:
              number: 8080
      - path: /health
        pathType: Prefix
        backend:
          service:
            name: wsc2026-book-svc
            port:
              number: 8080
  defaultBackend:
      service:
        name: response-403
        port:
          name: use-annotation
EOF
eksctl utils associate-iam-oidc-provider --region $REGION_CODE --cluster $EKS_CLUSTER_NAME --approve





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






cat <<EOF >> prometeus-sc.yaml
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

cat <<EOF >> prometeus-values.yaml
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

## prometeus
kubectl apply -f ./prometeus-sc.yaml
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade -i prometheus prometheus-community/prometheus \
  -n observability \
  -f ./prometeus-values.yaml
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

## grafana
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update
helm upgrade -i grafana grafana-community/grafana \
  -n observability \
  -f ./grafana-values.yaml