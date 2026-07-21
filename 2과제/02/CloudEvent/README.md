## SNS
- wsc2026-event-alert
- 표준


## CloudTrail
- wsc2026-event-trail


## Lambda
- wsc2026-event-lambda-role
- python 3.12

- wsc2026-ec2-stop-remediation
```
import os
import json
from datetime import datetime
import boto3
ec2_client = boto3.client('ec2')
sns_client = boto3.client('sns')
instance_id = "<인스턱스 아이디>"
sg_id = "<보안그룹 아이디>"
sns_topic_arn = "<SNS_ARN>"
def lambda_handler(event, context):
    ec2_client.start_instances(InstanceIds=[instance_id])
    message = {
        "event": "EC2_STOPPED",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "detail": f"EC2 instance {instance_id} was stopped and restarted",
        "action": "RESTORED"
    }
    sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=json.dumps(message)
    )
    return {"statusCode": 200, "body": "EC2 Restarted and Notified"}
```

- wsc2026-ec2-terminate-alert
```
import os
import json
from datetime import datetime
import boto3
sns_client = boto3.client('sns')
instance_id = "<인스턱스 아이디>"
sg_id = "<보안그룹 아이디>"
sns_topic_arn = "<SNS_ARN>"
def lambda_handler(event, context):
    detail = event.get('detail', {})
    message = {
        "event": "EC2_TERMINATED",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "detail": f"EC2 instance {instance_id} was terminated",
        "action": "ALERT_ONLY"
    }
    sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=json.dumps(message)
    )
    return {"statusCode": 200, "body": "EC2 Terminate Notified"}
```

- wsc2026-ec2-sg-remediation
```
import os
import json
import boto3
from datetime import datetime
ec2_client = boto3.client('ec2')
sns_client = boto3.client('sns')
instance_id = "<인스턱스 아이디>"
sg_id = "<보안그룹 아이디>"
sns_topic_arn = "<SNS_ARN>"
def lambda_handler(event, context):
    try:
        ec2_client.revoke_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[{
                'IpProtocol': 'tcp',
                'FromPort': 22,
                'ToPort': 22,
                'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
            }]
        )
    except Exception as e:
        print(f"Revoke error or rule already missing: {str(e)}")
    payload = {
        "event": "SG_SSH_OPEN",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "detail": f"Security Group {sg_id} global SSH access removed",
        "action": "RESTORED"
    }
    try:
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(payload)
        )
    except Exception as e:
        print(f"SNS Publish failed: {str(e)}")
    return {"statusCode": 200, "body": "Remediation executed."}
```

- wsc2026-ec2-tag-alert
```
import os
import json
from datetime import datetime
import boto3
sns_client = boto3.client('sns')
instance_id = "<인스턱스 아이디>"
sg_id = "<보안그룹 아이디>"
sns_topic_arn = "<SNS_ARN>"
def lambda_handler(event, context):
    detail = event.get('detail', {})
    compliance = detail.get('newEvaluationResult', {}).get('complianceType', '')
    if compliance == 'NON_COMPLIANT':
        resource_id = detail.get('resourceId', 'unknown-resource')
        resource_type = detail.get('resourceType', 'unknown-type')
        message = {
            "event": "TAG_MISSING",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "detail": f"Required tags are missing on resource {resource_id} ({resource_type})",
            "action": "ALERT_ONLY"
        }
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(message)
        )
    return {"statusCode": 200, "body": "Tag Non-Compliance Notified"}
```


## EventBridge
```
AWS_REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
# wsc2026-ec2-stop-rule
aws events put-rule \
  --name "wsc2026-ec2-stop-rule" \
  --event-pattern "{
    \"source\": [\"aws.ec2\"],
    \"detail-type\": [\"EC2 Instance State-change Notification\"],
    \"detail\": {
      \"state\": [\"stopped\"]
    }
  }"
STOP_LAMBDA_ARN=$(aws lambda get-function --function-name wsc2026-ec2-stop-remediation --query "Configuration.FunctionArn" --output text)
aws events put-targets --rule "wsc2026-ec2-stop-rule" --targets "Id=1,Arn=$STOP_LAMBDA_ARN"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws lambda add-permission --function-name "wsc2026-ec2-stop-remediation" --statement-id "AllowEventBridgeStopToTriggerReal" --action "lambda:InvokeFunction" --principal "events.amazonaws.com" --source-arn "arn:aws:events:eu-west-1:$ACCOUNT_ID:rule/wsc2026-ec2-stop-rule" &>/dev/null || echo "권한 확보 완료"

# wsc2026-ec2-terminate-rule
aws events put-rule --name "wsc2026-ec2-terminate-rule" --region $AWS_REGION --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Instance State-change Notification"],"detail":{"state":["terminated"]}}'
aws events put-targets --rule "wsc2026-ec2-terminate-rule" --region $AWS_REGION --targets "Id=1,Arn=arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function:wsc2026-ec2-terminate-alert"
aws lambda add-permission --function-name "wsc2026-ec2-terminate-alert" --region $AWS_REGION --statement-id "EventBridgeInvoke" --action "lambda:InvokeFunction" --principal "events.amazonaws.com" --source-arn "arn:aws:events:$AWS_REGION:$ACCOUNT_ID:rule/wsc2026-ec2-terminate-rule"

```


## Config
- 계속: SecurityGroup Instance

- name: wsc2026-sg-ssh-rule
- AWS 관리형 규칙: restricted-ssh

- name: wsc2026-required-tags-rule
- AWS 관리형 규칙: required-tags
- 리소스: AWS EC2 Instance
- 리소스 식별자: 인스턴스 아이디
- 파라미터: Name

```
export AWS_DEFAULT_REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

SG_RULE_NAME="wsc2026-sg-ssh-rule"
SG_LAMBDA_NAME="wsc2026-sg-remediation"
SG_EVENT_NAME="wsc2026-sg-change-rule"
TARGET_SG_ID=$(aws configservice get-compliance-details-by-config-rule --config-rule-name "$SG_RULE_NAME" --compliance-types "NON_COMPLIANT" --query "EvaluationResults[0].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId" --output text)
SG_LAMBDA_ARN=$(aws lambda get-function --function-name $SG_LAMBDA_NAME --query "Configuration.FunctionArn" --output text)
aws events put-rule --name "$SG_EVENT_NAME" --event-pattern "{
  \"source\": [\"aws.config\"],
  \"detail-type\": [\"Config Rules Compliance Change\"],
  \"detail\": {
    \"configRuleName\": [\"$SG_RULE_NAME\"],
    \"resourceId\": [\"$TARGET_SG_ID\"],
    \"newEvaluationResult\": { 
      \"complianceType\": [\"NON_COMPLIANT\"] 
    }
  }
}"
aws events put-targets --rule "$SG_EVENT_NAME" --targets "Id=1,Arn=$SG_LAMBDA_ARN"
aws lambda add-permission --function-name "$SG_LAMBDA_NAME" --statement-id "AllowConfigSgToTrigger" --action "lambda:InvokeFunction" --principal "events.amazonaws.com" --source-arn "arn:aws:events:eu-west-1:$ACCOUNT_ID:rule/$SG_EVENT_NAME" &>/dev/null || echo "SG 규칙 권한 확보 완료"

TAG_RULE_NAME="wsc2026-required-tags-rule"
TAG_LAMBDA_NAME="wsc2026-tag-alert"
TAG_EVENT_NAME="wsc2026-required-tags-rule"
TAG_LAMBDA_ARN=$(aws lambda get-function --function-name $TAG_LAMBDA_NAME --query "Configuration.FunctionArn" --output text)
aws events put-rule --name "$TAG_EVENT_NAME" --event-pattern "{
  \"source\": [\"aws.config\"],
  \"detail-type\": [\"Config Rules Compliance Change\"],
  \"detail\": {
    \"configRuleName\": [\"$TAG_RULE_NAME\"],
    \"newEvaluationResult\": { \"complianceType\": [\"NON_COMPLIANT\"] }
  }
}"
aws events put-targets --rule "$TAG_EVENT_NAME" --targets "Id=1,Arn=$TAG_LAMBDA_ARN"
aws lambda add-permission --function-name "$TAG_LAMBDA_NAME" --statement-id "AllowConfigTagToTrigger" --action "lambda:InvokeFunction" --principal "events.amazonaws.com" --source-arn "arn:aws:events:eu-west-1:$ACCOUNT_ID:rule/$TAG_EVENT_NAME" &>/dev/null || echo "Tag 규칙 권한 확보"
aws lambda add-permission --function-name wsc2026-sg-remediation --action lambda:InvokeFunction --statement-id config --principal config.amazonaws.com
aws lambda add-permission --function-name wsc2026-tag-alert --action lambda:InvokeFunction --statement-id config --principal config.amazonaws.com
```