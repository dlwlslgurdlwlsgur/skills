#!/bin/bash
set -x

aws configure set cli_binary_format raw-in-base64-out
REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

setup_rule() {
    local rule_name=$1
    local pattern=$2
    local func_name=$3
    
    aws events put-rule --name "$rule_name" --region $REGION --event-pattern "$pattern"
    LAMBDA_ARN=$(aws lambda get-function --function-name "$func_name" --region $REGION --query "Configuration.FunctionArn" --output text)
    
    # EventBridge -> Lambda 타겟 연결
    aws events put-targets --rule "$rule_name" --region $REGION --targets "Id=1,Arn=$LAMBDA_ARN"
    aws lambda add-permission --function-name "$func_name" --region $REGION --statement-id "EBInvoke-$rule_name" \
      --action "lambda:InvokeFunction" --principal "events.amazonaws.com" \
      --source-arn "arn:aws:events:$REGION:$ACCOUNT_ID:rule/$rule_name" 2>/dev/null || true
}

# 1. SG 인바운드 규칙 변경 탐지
setup_rule "wsc2026-sg-change-rule" \
  '{"source":["aws.ec2"],"detail-type":["AWS API Call via CloudTrail"],"detail":{"eventSource":["ec2.amazonaws.com"],"eventName":["AuthorizeSecurityGroupIngress"]}}' \
  "wsc2026-sg-remediation"

# 2. IAM Role 변경 탐지
setup_rule "wsc2026-role-change-rule" \
  '{"source":["aws.ec2"],"detail-type":["AWS API Call via CloudTrail"],"detail":{"eventSource":["ec2.amazonaws.com"],"eventName":["AssociateIamInstanceProfile"]}}' \
  "wsc2026-role-remediation"

# 3. EC2 인스턴스 종료 상태 탐지
setup_rule "wsc2026-ec2-terminate-rule" \
  '{"source":["aws.ec2"],"detail-type":["EC2 Instance State-change Notification"],"detail":{"state":["terminated"]}}' \
  "wsc2026-ec2-terminate-alert"

# 4. EC2 인스턴스 타입 변경 탐지
setup_rule "wsc2026-ec2-type-change-rule" \
  '{"source":["aws.ec2"],"detail-type":["AWS API Call via CloudTrail"],"detail":{"eventSource":["ec2.amazonaws.com"],"eventName":["ModifyInstanceAttribute"]}}' \
  "wsc2026-ec2-type-remediation"

echo "EventBridge Setup Complete"