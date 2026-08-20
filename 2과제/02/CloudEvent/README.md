## Region
- 아일랜드/eu-west-1

<br>

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/CloudEvent/01-vpc.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/CloudEvent/02-lambda.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/CloudEvent/03-ec2.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/CloudEvent/04-config.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/CloudEvent/mark.sh
```

<br>

## 삭제
```bash
aws iam remove-role-from-instance-profile --instance-profile-name wsc2026-event-ec2-profile --role-name wsc2026-event-ec2-role
aws iam delete-instance-profile --instance-profile-name wsc2026-event-ec2-profile
aws iam delete-role --role-name wsc2026-event-ec2-role
```
