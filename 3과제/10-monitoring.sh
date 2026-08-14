#!/bin/bash
set -x
ClusterName="skills-cluster"
REGION="ap-northeast-2"

kubectl create namespace amazon-cloudwatch 2>/dev/null || true

kubectl create configmap cluster-info \
  --from-literal=cluster.name=${ClusterName} \
  --from-literal=aws.REGION=${REGION} \
  -n amazon-cloudwatch

kubectl get pods -n amazon-cloudwatch


cat << 'EOF' > cw-dashboard.json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "view": "timeSeries",
        "stacked": false,
        "region": "ap-northeast-2",
        "metrics": [
          [ { "expression": "SEARCH('{AWS/ApplicationELB,LoadBalancer} MetricName=\"TargetResponseTime\" LoadBalancer=~\"app/skills-alb.*\"', 'Average', 60)", "id": "e1", "period": 60 } ]
        ],
        "title": "ALB Response Time"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "view": "timeSeries",
        "stacked": false,
        "metrics": [
          [ "ContainerInsights", "node_cpu_utilization", "ClusterName", "skills-cluster", { "label": "Node CPU (%)", "color": "#1f77b4" } ],
          [ ".", "pod_cpu_utilization", ".", ".", { "label": "Pod CPU (%)", "color": "#ff7f0e" } ],
          [ "ContainerInsights", "node_memory_utilization", "ClusterName", "skills-cluster", { "label": "Node Memory (%)", "color": "#2ca02c" } ],
          [ ".", "pod_memory_utilization", ".", ".", { "label": "Pod Memory (%)", "color": "#d62728" } ]
        ],
        "region": "ap-northeast-2",
        "title": "EKS Utilization (CPU & Memory)"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE \"aws-waf-logs-skills\" | filter action = 'BLOCK' | parse @message /\"name\":\"(?<HKey>[Tt]ype|[Uu]ser-[Aa]gent|[Xx]-[Ff]orwarded-[Ff]or|[Cc]ookie|[Rr]eferer|[Xx]-[Cc]ustom-[Aa]uth|[Aa]uthorization|[Aa]ccept|[Xx]-[Aa]pi-[Kk]ey)\",\"value\":\"(?<HVal>[^\"]+)\"/ | filter HVal != '*/*' | fields concat(HKey, \": \", HVal) as AttackHeader | parse httpRequest.args /^(?<CleanArgs>[^&]+)/ | display @timestamp, httpRequest.uri, CleanArgs, AttackHeader | sort @timestamp desc",
        "region": "us-east-1",
        "title": "WAF Blocked",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 12,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE \"aws-waf-logs-skills\" | filter action = 'ALLOW' | parse @message /\"name\":\"(?<HKey>[Tt]ype|[Uu]ser-[Aa]gent|[Xx]-[Ff]orwarded-[Ff]or|[Cc]ookie|[Rr]eferer|[Xx]-[Cc]ustom-[Aa]uth|[Aa]uthorization|[Aa]ccept|[Xx]-[Aa]pi-[Kk]ey)\",\"value\":\"(?<HVal>[^\"]+)\"/ | filter HVal != '*/*' | fields concat(HKey, \": \", HVal) as AttackHeader | parse httpRequest.args /^(?<CleanArgs>[^&]+)/ | display @timestamp, httpRequest.uri, CleanArgs, AttackHeader | sort @timestamp desc",
        "region": "us-east-1",
        "title": "WAF Allowed (All)",
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
        "query": "SOURCE \"aws-waf-logs-skills\" | filter action = 'ALLOW' | filter ispresent(httpRequest.args) and httpRequest.args != '' | parse httpRequest.args /^(?<CleanArgs>[^&]+)/ | filter CleanArgs != '' | display @timestamp, httpRequest.uri, CleanArgs | sort @timestamp desc",
        "region": "us-east-1",
        "title": "WAF Allowed (Query Focus)",
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
        "query": "SOURCE \"aws-waf-logs-skills\" | filter action = 'ALLOW' | parse @message /\"name\":\"(?<HKey>[Tt]ype|[Uu]ser-[Aa]gent|[Xx]-[Ff]orwarded-[Ff]or|[Cc]ookie|[Rr]eferer|[Xx]-[Cc]ustom-[Aa]uth|[Aa]uthorization|[Aa]ccept|[Xx]-[Aa]pi-[Kk]ey)\",\"value\":\"(?<HVal>[^\"]+)\"/ | filter HVal != '*/*' | fields concat(HKey, \": \", HVal) as AttackHeader | filter ispresent(AttackHeader) | display @timestamp, httpRequest.uri, AttackHeader | sort @timestamp desc",
        "region": "us-east-1",
        "title": "WAF Allowed (Header Focus)",
        "view": "table"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 24,
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
      "y": 24,
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
      "y": 30,
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
      "y": 30,
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
      "y": 36,
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
      "y": 36,
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
