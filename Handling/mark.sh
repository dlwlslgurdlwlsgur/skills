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


echo "VPC_ID=${VPC_ID}"
echo "EC2_ID=${EC2_ID}"
echo "SG_ID=${SG_ID}"
aws ec2 describe-vpcs --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-vpc --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,Cidr:CidrBlock}' --output table
aws ec2 describe-instances --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,State:State.Name,SecurityGroups:SecurityGroups[].GroupId}' --output table
aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[].{Name:Tags[?Key==`Name`].Value|[0],GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}' --output table
# VPC, EC2, Security Group 보호 대상 이 존재하고 연결 상태가 요구사항과 일치하는지 확인합니다.


aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[].{GroupId:GroupId,Inbound:IpPermissions,Outbound:IpPermissionsEgress}' --output json
# skills-ceh-protected-sg Inbound 0 의 규칙이 개인지 확인합니다.


echo "TOPIC_ARN=${TOPIC_ARN}"
aws sns list-topics --region ap-southeast-1 --query 'Topics[?contains(TopicArn, `:skills-ceh-alert-topic`)].TopicArn' --output table
aws lambda get-function-configuration --region ap-southeast-1 --function-name skills-ceh-remediate-fn --query '{FunctionName:FunctionName,State:State,LastUpdateStatus:LastUpdateStatus,Runtime:Runtime,Handler:Handler,Timeout:Timeout,Role:Role,Environment:Environment.Variables}' --output table
# SNS Topic Lambda Runtime, Handler, Timeout, Environment 과 가 요구사항과 일치하는지 확인합니다.


aws cloudtrail get-trail-status --region ap-southeast-1 --name skills-ceh-cloudtrail --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime,LatestDeliveryError:LatestDeliveryError}' --output table
aws events describe-rule --region ap-southeast-1 --name skills-ceh-sg-change-rule --event-bus-name default --query '{Name:Name,State:State,EventPattern:EventPattern}' --output json
aws events list-targets-by-rule --region ap-southeast-1 --rule skills-ceh-sg-change-rule --event-bus-name default --query 'Targets[].{Id:Id,Arn:Arn}' --output table
aws lambda get-policy --region ap-southeast-1 --function-name skills-ceh-remediate-fn-role --query 'Policy' --output text
# CloudTrail Trail, EventBridge Rule Event Pattern, Target, Lambda Resource Policy가 요구사항과 일치하는지 확인합니다.


if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  echo "skills-ceh-protected-sg 식별 실패"
else
  aws ec2 revoke-security-group-ingress --region ap-southeast-1 --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
  if ! aws ec2 authorize-security-group-ingress --region ap-southeast-1 --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0; then
    echo "테스트 Inbound 규칙 추가 실패"
  else
    jq -n --arg sg "$SG_ID" '{detail:{eventName:"AuthorizeSecurityGroupIngress",requestParameters:{groupId:$sg}}}' > /tmp/skills-ceh-remediate-event.json
    aws lambda invoke --region ap-southeast-1 --function-name skills-ceh-remediate-fn --cli-binary-format raw-in-base64-out --payload file:///tmp/skills-ceh-remediate-event.json /tmp/skills-ceh-remediate-output.json
    cat /tmp/skills-ceh-remediate-output.json 2>/dev/null || true
    echo
    for I in $(seq 1 36); do
      sleep 5
      echo "poll=${I}"
      aws ec2 describe-security-groups --region ap-southeast-1 --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissions' --output json
      COUNT=$(aws ec2 describe-security-groups --region ap-southeast-1 --group-ids "$SG_ID" --query 'length(SecurityGroups[0].IpPermissions)' --output text 2>/dev/null || true)
      echo "inbound_count=${COUNT}"
      [ "$COUNT" = "0" ] && break
    done
    aws logs describe-log-groups --region ap-southeast-1 --log-group-name-prefix /aws/lambda/skills-ceh-remediate-fn --query 'logGroups[].logGroupName' --output table
    aws ec2 revoke-security-group-ingress --region ap-southeast-1 --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
  fi
fi
# 180 Inbound 0 초 이내 규칙이 다시 개가 되고 Lambda Log Group이 생성되는지 확인합니다.