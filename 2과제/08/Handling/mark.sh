set -u
export AWS_PAGER=""
OUT_TXT="asgmt2_module3_check_result.txt"
exec > >(tee "$OUT_TXT") 2>&1

for CMD in aws jq grep; do
  if ! command -v "$CMD" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $CMD" >&2
    exit 2
  fi
done
VPC_ID=$(aws ec2 describe-vpcs --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
SG_ID=$(aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
EC2_ID=$(aws ec2 describe-instances --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId | [0]' --output text 2>/dev/null || true)
TOPIC_ARN=$(aws sns list-topics --region ap-southeast-1 --query 'Topics[?contains(TopicArn, `:skills-ceh-alert-topic`)].TopicArn | [0]' --output text 2>/dev/null || true)
LAMBDA_ARN=$(aws lambda get-function-configuration --region ap-southeast-1 --function-name skills-ceh-remediate-fn --query 'FunctionArn' --output text 2>/dev/null || true)


aws ec2 describe-vpcs --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-vpc --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,Cidr:CidrBlock}' --output table
aws ec2 describe-instances --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,State:State.Name,SecurityGroups:SecurityGroups[].GroupId}' --output table
aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[].{Name:Tags[?Key==`Name`].Value|[0],GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}' --output table# VPC_ID=vpc-0123456789abcdef0
# VPC Name=skills-ceh-vpc, Cidr=10.73.0.0/16이어야 합니다.
# EC2 Name=skills-ceh-ec2, State=running이어야 합니다.
# Security Group Name=skills-ceh-protected-sg가 존재하고 EC2에 연결되어 있어야 합니다.


aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[].{GroupId:GroupId,Inbound:IpPermissions,Outbound:IpPermissionsEgress}' --output json
# Inbound 또는 IpPermissions가 빈 배열 []이어야 합니다.


aws sns list-topics --region ap-southeast-1 --query 'Topics[?contains(TopicArn, `:skills-ceh-alert-topic`)].TopicArn' --output table
aws lambda get-function-configuration --region ap-southeast-1 --function-name skills-ceh-remediate-fn --query '{FunctionName:FunctionName,State:State,LastUpdateStatus:LastUpdateStatus,Runtime:Runtime,Handler:Handler,Timeout:Timeout,Role:Role,Environment:Environment.Variables}' --output table# TOPIC_ARN=arn:aws:sns:ap-southeast-1:123456789012:skills-ceh-alert-topic
# SNS Topic ARN에 skills-ceh-alert-topic이 포함되어야 합니다.
# Lambda FunctionName=skills-ceh-remediate-fn, State=Active, Runtime=python3.12, Handler=remediate_security_group.lambda_handler, Timeout>=30이어야 합니다.
# Environment에는 PROTECTED_SECURITY_GROUP_ID와 SNS_TOPIC_ARN이 존재해야 합니다.


aws cloudtrail get-trail-status --region ap-southeast-1 --name skills-ceh-cloudtrail --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime,LatestDeliveryError:LatestDeliveryError}' --output table
aws events describe-rule --region ap-southeast-1 --name skills-ceh-sg-change-rule --event-bus-name default --query '{Name:Name,State:State,EventPattern:EventPattern}' --output json
aws events list-targets-by-rule --region ap-southeast-1 --rule skills-ceh-sg-change-rule --event-bus-name default --query 'Targets[].{Id:Id,Arn:Arn}' --output table
aws lambda get-policy --region ap-southeast-1 --function-name skills-ceh-remediate-fn --query 'Policy' --output text# -------------------------------------------------------------------------
# CloudTrail IsLogging=True이어야 합니다.
# EventBridge Rule Name=skills-ceh-sg-change-rule, State=ENABLED이어야 합니다.
# EventPattern에 AuthorizeSecurityGroupIngress와 EC2 API Call via CloudTrail 조건이 포함되어야 합니다.
# Target Arn은 skills-ceh-remediate-fn Lambda ARN이어야 합니다.
# Lambda Policy에 events.amazonaws.com 호출 권한이 포함되어야 합니다.


export PROTECTED_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress --region ap-southeast-1 --group-id "$PROTECTED_SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
jq -n --arg sg "$PROTECTED_SECURITY_GROUP_ID" '{detail:{eventName:"AuthorizeSecurityGroupIngress",requestParameters:{groupId:$sg}}}' > /tmp/skills-ceh-remediate-event.json
aws lambda invoke --region ap-southeast-1 --function-name skills-ceh-remediate-fn --cli-binary-format raw-in-base64-out --payload file:///tmp/skills-ceh-remediate-event.json /tmp/skills-ceh-remediate-output.json
aws ec2 describe-security-groups --region ap-southeast-1 --group-ids "$PROTECTED_SECURITY_GROUP_ID" --query 'SecurityGroups[0].IpPermissions' --output json
aws logs describe-log-groups --region ap-southeast-1 --log-group-name-prefix /aws/lambda/skills-ceh-remediate-fn --query 'logGroups[].logGroupName' --output table
# Lambda Invoke가 성공해야 합니다.
# 180초 이내 SecurityGroups[0].IpPermissions가 빈 배열 []이어야 합니다.
# /aws/lambda/skills-ceh-remediate-fn Log Group이 출력되어야 합니다.
# 본 항목은 CloudTrail 전달 지연 시간을 채점하지 않습니다.