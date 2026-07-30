ClusterName="skills-cluster"
Region="ap-northeast-2"

kubectl create namespace amazon-cloudwatch

kubectl create configmap cluster-info \
  --from-literal=cluster.name=${ClusterName} \
  --from-literal=aws.region=${Region} \
  -n amazon-cloudwatch

aws eks create-addon \
  --cluster-name skills-cluster \
  --addon-name amazon-cloudwatch-observability \
  --region ap-northeast-2

aws eks describe-addon \
  --cluster-name skills-cluster \
  --addon-name amazon-cloudwatch-observability \
  --region ap-northeast-2 \
  --query "addon.status" \
  --output text

# 끝낧때 까지 대기
# 끝낧때 까지 대기
# 끝낧때 까지 대기
# 끝낧때 까지 대기
# 끝낧때 까지 대기

kubectl get pods -n amazon-cloudwatch

cat <<EOF >> cw-dashboard.json
{
  "widgets": [
    {
      "type": "log",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, @message | filter kubernetes.pod_name like /user/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "🟢 [USER] App Logs",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, @message | filter kubernetes.pod_name like /product/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "🔵 [PRODUCT] App Logs",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, @message | filter kubernetes.pod_name like /stress/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "🟠 [STRESS] App Logs",
        "view": "table"
      }
    }
  ]
}
EOF

aws cloudwatch put-dashboard \
  --dashboard-name "Skills-App-Logs-Dashboard" \
  --dashboard-body file://cw-dashboard.json \
  --region ap-northeast-2