#!/bin/bash
set -x
export AWS_PAGER=""

REGION="us-east-1"
SCOPE="CLOUDFRONT"
WAF_NAME="skills-waf"
LOG_GROUP_NAME="aws-waf-logs-skills"

cat <<EOF > waf-rules.json
[
    {
        "Name": "AWS-AWSManagedRulesCommonRuleSet",
        "Priority": 0,
        "Statement": { "ManagedRuleGroupStatement": { "VendorName": "AWS", "Name": "AWSManagedRulesCommonRuleSet" } },
        "OverrideAction": { "None": {} },
        "VisibilityConfig": { "SampledRequestsEnabled": true, "CloudWatchMetricsEnabled": true, "MetricName": "CommonRuleSetMetric" }
    },
    {
        "Name": "AWS-AWSManagedRulesSQLiRuleSet",
        "Priority": 1,
        "Statement": { "ManagedRuleGroupStatement": { "VendorName": "AWS", "Name": "AWSManagedRulesSQLiRuleSet" } },
        "OverrideAction": { "None": {} },
        "VisibilityConfig": { "SampledRequestsEnabled": true, "CloudWatchMetricsEnabled": true, "MetricName": "SQLiRuleSetMetric" }
    },
    {
        "Name": "AWS-AWSManagedRulesKnownBadInputsRuleSet",
        "Priority": 2,
        "Statement": { "ManagedRuleGroupStatement": { "VendorName": "AWS", "Name": "AWSManagedRulesKnownBadInputsRuleSet" } },
        "OverrideAction": { "None": {} },
        "VisibilityConfig": { "SampledRequestsEnabled": true, "CloudWatchMetricsEnabled": true, "MetricName": "BadInputsMetric" }
    },
    {
        "Name": "AWS-AWSManagedRulesLinuxRuleSet",
        "Priority": 3,
        "Statement": { "ManagedRuleGroupStatement": { "VendorName": "AWS", "Name": "AWSManagedRulesLinuxRuleSet" } },
        "OverrideAction": { "None": {} },
        "VisibilityConfig": { "SampledRequestsEnabled": true, "CloudWatchMetricsEnabled": true, "MetricName": "LinuxRuleMetric" }
    },
    {
        "Name": "header",
        "Priority": 4,
        "Statement": {
            "RegexMatchStatement": {
                "RegexString": "hacker|bad",
                "FieldToMatch": {
                    "SingleHeader": {
                        "Name": "type"
                    }
                },
                "TextTransformations": [
                    {
                        "Priority": 0,
                        "Type": "NONE"
                    }
                ]
            }
        },
        "VisibilityConfig": {
            "SampledRequestsEnabled": true,
            "CloudWatchMetricsEnabled": true,
            "MetricName": "header"
        },
        "Action": {
            "Block": {
                "CustomResponse": {
                    "ResponseCode": 403
                }
            }
        }
    },
    {
        "Name": "query",
        "Priority": 5,
        "Statement": {
            "RegexMatchStatement": {
                "RegexString": "hacker|bad",
                "FieldToMatch": {
                    "QueryString": {}
                },
                "TextTransformations": [
                    {
                        "Priority": 0,
                        "Type": "LOWERCASE"
                    },
                    {
                        "Priority": 1,
                        "Type": "URL_DECODE"
                    }
                ]
            }
        },
        "VisibilityConfig": {
            "SampledRequestsEnabled": true,
            "CloudWatchMetricsEnabled": true,
            "MetricName": "query"
        },
        "Action": {
            "Block": {
                "CustomResponse": {
                    "ResponseCode": 403
                }
            }
        }
    }
]
EOF

WEB_ACL_ARN=$(aws wafv2 create-web-acl \
    --name "${WAF_NAME}" \
    --scope "${SCOPE}" \
    --default-action '{"Allow": {}}' \
    --rules file://waf-rules.json \
    --visibility-config "SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=SkillsWebACLCF" \
    --region "${REGION}" \
    --query 'Summary.ARN' \
    --output text)

aws logs create-log-group \
    --log-group-name "${LOG_GROUP_NAME}" \
    --region "${REGION}" || echo "Log group already exists."

LOG_GROUP_ARN=$(aws logs describe-log-groups \
    --log-group-name-prefix "${LOG_GROUP_NAME}" \
    --region "${REGION}" \
    --query "logGroups[0].arn" \
    --output text | sed 's/:\*$//')

cat <<EOF > waf-logging-config.json
{
  "ResourceArn": "${WEB_ACL_ARN}",
  "LogDestinationConfigs": [
    "${LOG_GROUP_ARN}"
  ]
}
EOF

aws wafv2 put-logging-configuration \
    --logging-configuration file://waf-logging-config.json \
    --region "${REGION}"

rm waf-rules.json waf-logging-config.json