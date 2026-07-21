import json
import os
from datetime import datetime, timezone
import boto3

ec2_client = boto3.client("ec2")
sns_client = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")

def publish_alert(event_type, detail, action):
    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN 환경변수가 없습니다.")
        return
    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=json.dumps({
            "event": event_type,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "detail": detail,
            "action": action,
        }),
    )

def sg_remediation_handler(event, context):
    target_sg_id = os.environ.get("SECURITY_GROUP_ID")
    detail = event.get("detail", {})
    request_parameters = detail.get("requestParameters", {})
    event_sg_id = request_parameters.get("groupId") or request_parameters.get("GroupId")
    
    if not event_sg_id:
        print("이벤트에서 보안 그룹 ID를 찾을 수 없습니다.")
        return

    if target_sg_id and event_sg_id != target_sg_id:
        print(f"감시 대상이 아닌 보안 그룹({event_sg_id})이므로 무시합니다.")
        return

    print(f"대상 보안 그룹({event_sg_id})의 SSH 규칙 삭제를 시작합니다.")

    try:
        ec2_client.revoke_security_group_ingress(
            GroupId=event_sg_id,
            IpPermissions=[
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 22,
                    'ToPort': 22,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                }
            ]
        )
        print("SSH 규칙 삭제 성공!")
        
        publish_alert(
            "SG_SSH_OPEN",
            f"Unauthorized SSH rule removed from {event_sg_id}",
            "RESTORED",
        )
    except Exception as e:
        print(f"규칙 삭제 중 에러 발생: {str(e)}")