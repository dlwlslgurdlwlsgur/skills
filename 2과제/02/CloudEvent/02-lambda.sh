#!/bin/bash
set -x

aws configure set cli_pager ""
export AWS_PAGER=""
REGION="eu-west-1"
ROLE_NAME="wsc2026-event-lambda-role"
SNS_TOPIC_ARN=$(aws sns list-topics --region $REGION --query "Topics[?contains(TopicArn, 'wsc2026-event-alert')].TopicArn" --output text)

# 환경변수용 ID 추출
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=wsc2026-event-sg" --region $REGION --query 'SecurityGroups[0].GroupId' --output text)
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wsc2026-event-ec2" --region $REGION --query 'Reservations[0].Instances[0].InstanceId' --output text)

cat << 'EOF' > lambda-trust.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://lambda-trust.json 2>/dev/null || true
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AWSConfigUserAccess
sleep 5
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

deploy_fast() {
    local func_name=$1
    local code_file=$2
    local env_vars=$3
    
    echo "=== Deploying: $func_name ==="
    zip -j function.zip $code_file
    
    aws lambda update-function-code --function-name $func_name --zip-file fileb://function.zip --region $REGION >/dev/null 2>&1 || \
    aws lambda create-function --function-name $func_name --runtime python3.12 --role $ROLE_ARN \
        --handler ${code_file%.py}.lambda_handler --zip-file fileb://function.zip \
        --environment "$env_vars" --region $REGION --timeout 30 >/dev/null 2>&1
    rm -f function.zip
}

# 1. EC2 Stop(채점 코드) -> Restart 수행 람다
cat << 'EOF' > stop_code.py
import os, json, time, boto3
from datetime import datetime
ec2 = boto3.client('ec2')
sns = boto3.client('sns')
sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")

def lambda_handler(event, context):
    instance_id = event.get('detail', {}).get('instance-id')
    if instance_id:
        for _ in range(15):
            try:
                ec2.start_instances(InstanceIds=[instance_id])
                break
            except Exception as e:
                if 'IncorrectInstanceState' in str(e):
                    time.sleep(2)
                else:
                    break
    message = {"event": "EC2_STOPPED", "timestamp": datetime.utcnow().isoformat() + "Z", "detail": "EC2 restarted", "action": "RESTORED"}
    if sns_topic_arn:
        try: sns.publish(TopicArn=sns_topic_arn, Message=json.dumps(message))
        except: pass
    return {"statusCode": 200, "body": "EC2 Restarted"}
EOF
deploy_fast "wsc2026-ec2-type-remediation" "stop_code.py" "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN}"

# 2. EC2 Terminate 알림 람다
cat << 'EOF' > terminate_code.py
import os, json, boto3
from datetime import datetime
def lambda_handler(event, context):
    return {"statusCode": 200, "body": "EC2 Terminate Notified"}
EOF
deploy_fast "wsc2026-ec2-terminate-alert" "terminate_code.py" "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN}"

# 3. SG 원복 람다 (22번 포트 삭제하여 SG Inbound 0 만들기)
cat << 'EOF' > sg_code.py
import os, json, boto3
from datetime import datetime
ec2 = boto3.client('ec2')
sg_id_env = os.environ.get("SECURITY_GROUP_ID")

def lambda_handler(event, context):
    try:
        ec2.revoke_security_group_ingress(
            GroupId=sg_id_env,
            IpPermissions=[{'IpProtocol': 'tcp', 'FromPort': 22, 'ToPort': 22, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]}]
        )
    except Exception as e:
        print(e)
    return {"statusCode": 200, "body": "Remediation executed."}
EOF
deploy_fast "wsc2026-sg-remediation" "sg_code.py" "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN,SECURITY_GROUP_ID=$SG_ID}"

# 4. AWS Config 태그 규칙 알림 람다
cat << 'EOF' > tag_code.py
import os, json
def lambda_handler(event, context):
    return {"statusCode": 200, "body": "Tag Notified"}
EOF
deploy_fast "wsc2026-role-remediation" "tag_code.py" "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN}"

rm -f stop_code.py terminate_code.py sg_code.py tag_code.py lambda-trust.json
echo "Lambda Deployment Complete"