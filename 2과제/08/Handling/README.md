## Region
- 싱가포르/ap-southeast-1

<br>

## Name
- VPC: skills-ceh-vpc
- EC2: skills-ceh-ec2
- SG: skills-ceh-protected-sg
- SNS: skills-ceh-alert-topic
- Lambda: skills-ceh-remediate-fn
- CloudTrail: skills-ceh-cloudtrail
- EventBridge: skills-ceh-sg-change-rule

<br>

## Lambda
- python: remediate_security_group.py
- handler: remediate_security_group.lambda_handler
- env: PROTECTED_SECURITY_GROUP_ID, SNS_TOPIC_ARN

<br>

## CloudTrail
- 생성

<br>

## EventBridge
```
{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["AuthorizeSecurityGroupIngress"]
  }
}
```