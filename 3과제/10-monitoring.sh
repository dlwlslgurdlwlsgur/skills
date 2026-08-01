#!/bin/bash
set -x
ClusterName="skills-cluster"
Region="ap-northeast-2"

kubectl create namespace amazon-cloudwatch

kubectl create configmap cluster-info \
  --from-literal=cluster.name=${ClusterName} \
  --from-literal=aws.region=${Region} \
  -n amazon-cloudwatch

kubectl get pods -n amazon-cloudwatch


cat <<EOF > cw-dashboard.json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 8,
      "height": 6,
      "properties": {
        "view": "timeSeries",
        "stacked": false,
        "region": "ap-northeast-2",
        "metrics": [
          [ { "expression": "SEARCH('{AWS/ApplicationELB,LoadBalancer} MetricName=\"TargetResponseTime\" LoadBalancer=~\"app/skills-alb.*\"', 'Average', 60)", "id": "e1", "period": 60 } ]
        ],
        "title": "⏱️ ALB Target Response Time"
      }
    },
    {
      "type": "log",
      "x": 8,
      "y": 0,
      "width": 16,
      "height": 6,
      "properties": {
        "query": "SOURCE \"aws-waf-logs-skills\" | fields @timestamp, httpRequest.clientIp, httpRequest.uri, action, terminatingRuleId | filter action = 'BLOCK' | sort @timestamp desc",
        "region": "us-east-1",
        "title": "🛡️ WAF Blocked Requests",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, log | filter kubernetes.container_name = 'user' and stream = 'stdout' | filter log not like /amazon.opentelemetry/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "USER OUT",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 12,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, log | filter kubernetes.container_name = 'user' and stream = 'stderr' | filter log not like /amazon.opentelemetry/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "USER ERR",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, log | filter kubernetes.container_name = 'product' and stream = 'stdout' | filter log not like /amazon.opentelemetry/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "PRODUCT OUT",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 12,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, log | filter kubernetes.container_name = 'product' and stream = 'stderr' | filter log not like /amazon.opentelemetry/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "PRODUCT ERR",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 18,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, log | filter kubernetes.container_name = 'stress' and stream = 'stdout' | filter log not like /amazon.opentelemetry/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "STRESS OUT",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 12,
      "y": 18,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/skills-cluster/application\" | fields @timestamp, log | filter kubernetes.container_name = 'stress' and stream = 'stderr' | filter log not like /amazon.opentelemetry/ | sort @timestamp desc",
        "region": "ap-northeast-2",
        "title": "STRESS ERR",
        "view": "table"
      }
    }
  ]
}
EOF

aws cloudwatch put-dashboard \
  --dashboard-name "skills" \
  --dashboard-body file://cw-dashboard.json \
  --region ap-northeast-2

rm cw-dashboard.json