#!/bin/bash
set -x

aws configure set cli_pager ""
export AWS_PAGER=""
REGION="eu-west-1"
ROLE_NAME="wsc2026-event-lambda-role"
SNS_TOPIC_ARN=$(aws sns list-topics --region $REGION --query "Topics[?contains(TopicArn, 'wsc2026-event-alert')].TopicArn" --output text)

# 인스턴스 ID와 보안그룹 ID를 조회하여 환경변수로 주입 준비
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

sleep 5
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

deploy_fast() {
    local func_name=$1
    local code_file=$2
    local env_vars=$3
    
    echo "=== Deploying: $func_name ==="
    zip -j function.zip $code_file
    
    aws lambda update-function-code \
        --function-name $func_name \
        --zip-file fileb://function.zip \
        --region $REGION >/dev/null 2>&1 || \
    aws lambda create-function \
        --function-name $func_name \
        --runtime python3.12 \
        --role $ROLE_ARN \
        --handler ${code_file%.py}.lambda_handler \
        --zip-file fileb://function.zip \
        --environment "$env_vars" \
        --region $REGION \
        --timeout 30 >/dev/null 2>&1
    
    rm -f function.zip
}

# 1. EC2 타입 변경 원복 람다
cat << 'EOF' > type_code.py
import os, json, boto3, time
from datetime import datetime
ec2 = boto3.client('ec2')
sns = boto3.client('sns')
sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")
target_instance_type = os.environ.get("INSTANCE_TYPE", "t3.micro")

def lambda_handler(event, context):
    detail = event.get('detail', {})
    instance_id = detail.get('requestParameters', {}).get('instanceId')
    
    if instance_id:
        try:
            ec2.stop_instances(InstanceIds=[instance_id])
            waiter = ec2.get_waiter('instance_stopped')
            waiter.wait(InstanceIds=[instance_id])
            
            ec2.modify_instance_attribute(InstanceId=instance_id, InstanceType={'Value': target_instance_type})
            ec2.start_instances(InstanceIds=[instance_id])
        except Exception as e:
            print(f"Error restoring EC2 Type: {e}")
            
    message = {
        "event": "EC2_TYPE_CHANGED",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "detail": f"EC2 instance type restored to {target_instance_type}",
        "action": "RESTORED"
    }
    if sns_topic_arn:
        sns.publish(TopicArn=sns_topic_arn, Message=json.dumps(message))
    return {"statusCode": 200, "body": "EC2 Type Restored"}
EOF
deploy_fast "wsc2026-ec2-type-remediation" "type_code.py" "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN,INSTANCE_ID=$INSTANCE_ID,INSTANCE_TYPE=t3.micro}"

# 2. EC2 종료 알림 람다
cat << 'EOF' > terminate_code.py
import os, json, boto3
from datetime import datetime
sns = boto3.client('sns')
sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")

def lambda_handler(event, context):
    message = {
        "event": "EC2_TERMINATED",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "detail": "EC2 instance was terminated",
        "action": "ALERT_ONLY"
    }
    if sns_topic_arn:
        sns.publish(TopicArn=sns_topic_arn, Message=json.dumps(message))
    return {"statusCode": 200, "body": "EC2 Terminate Notified"}
EOF
deploy_fast "wsc2026-ec2-terminate-alert" "terminate_code.py" "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN}"

# 3. Security Group 원복 람다
cat << 'EOF' > sg_code.py
import os, json, boto3
from datetime import datetime
ec2 = boto3.client('ec2')
sns = boto3.client('sns')
sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")
sg_id_env = os.environ.get("SECURITY_GROUP_ID")

def lambda_handler(event, context):
    detail = event.get('detail', {})
    req_params = detail.get('requestParameters', {})
    group_id = req_params.get('groupId', sg_id_env)
    ip_permissions = req_params.get('ipPermissions', {}).get('items', [])
    
    if group_id and ip_permissions:
        try:
            boto3_perms = []
            for perm in ip_permissions:
                p = {'IpProtocol': perm.get('ipProtocol')}
                if 'fromPort' in perm: p['FromPort'] = perm['fromPort']
                if 'toPort' in perm: p['ToPort'] = perm['toPort']
                if 'ipRanges' in perm and 'items' in perm['ipRanges']:
                    p['IpRanges'] = [{'CidrIp': item['cidrIp']} for item in perm['ipRanges']['items']]
                boto3_perms.append(p)
                
            ec2.revoke_security_group_ingress(GroupId=group_id, IpPermissions=boto3_perms)
        except Exception as e:
            print(f"Revoke error: {e}")
            
    payload = {
        "event": "SG_INBOUND_ADDED",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "detail": f"Unauthorized inbound rule removed from {group_id}",
        "action": "RESTORED"
    }
    if sns_topic_arn:
        sns.publish(TopicArn=sns_topic_arn, Message=json.dumps(payload))
    return {"statusCode": 200, "body": "SG Remediation executed"}
EOF
deploy_fast "wsc2026-sg-remediation" "sg_code.py" "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN,SECURITY_GROUP_ID=$SG_ID}"

# 4. IAM Role 원복 람다
cat << 'EOF' > role_code.py
import os, json, boto3
from datetime import datetime
ec2 = boto3.client('ec2')
sns = boto3.client('sns')
sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")
target_role_name = os.environ.get("ROLE_NAME", "wsc2026-event-ec2-role")
target_profile_name = "wsc2026-event-ec2-profile"

def lambda_handler(event, context):
    detail = event.get('detail', {})
    req_params = detail.get('requestParameters', {}).get('AssociateIamInstanceProfileRequest', {})
    instance_id = req_params.get('InstanceId')
    
    if instance_id:
        try:
            res = ec2.describe_iam_instance_profile_associations(Filters=[{'Name': 'instance-id', 'Values': [instance_id]}])
            associations = res.get('IamInstanceProfileAssociations', [])
            
            if associations:
                assoc_id = associations[0]['AssociationId']
                ec2.replace_iam_instance_profile_association(
                    AssociationId=assoc_id,
                    IamInstanceProfile={'Name': target_profile_name}
                )
            else:
                ec2.associate_iam_instance_profile(
                    IamInstanceProfile={'Name': target_profile_name},
                    InstanceId=instance_id
                )
        except Exception as e:
            print(f"Role Remediate error: {e}")

    message = {
        "event": "ROLE_CHANGED",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "detail": f"IAM Role restored to {target_role_name}",
        "action": "RESTORED"
    }
    if sns_topic_arn:
        sns.publish(TopicArn=sns_topic_arn, Message=json.dumps(message))
    return {"statusCode": 200, "body": "Role Restored"}
EOF
deploy_fast "wsc2026-role-remediation" "role_code.py" "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN,INSTANCE_ID=$INSTANCE_ID,ROLE_NAME=wsc2026-event-ec2-role}"

rm -f type_code.py terminate_code.py sg_code.py role_code.py lambda-trust.json

echo "Lambda Deployment Complete"