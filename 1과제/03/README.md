## CloudShell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/03/01-vpc.sh
```
- mark-sg
- wsc2026-skills-app-sub-a에 연결

<br>

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/03/02-kms.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/03/03-cluster.sh
```

<br>

## S3
- wsc2026-static-<임의의 영문 4자리>-<비번호>-bucket
- KMS
- /static

<br>

## ECR
- 배포파일/book
- v1* 설정
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/03/04-ecr.sh
```

<br>

## DynamoDB
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/03/05-dynamodb.sh
```

<br>

## Lambda
- wsc2026-book-get-function
- Python 3.12
- kms 연결 ( 시작, 환경변수 )
- 환경변수 { TABLE_NAME: wsc2026-book-table(암호화) }
- 30초

<br>

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/03/06-app.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/03/07-monitoring.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/03/08-waf.sh
```
- ALB에 Default 403 설정

<br>

## CloudFront
- wsc2026-cdn
- WAF 연결
- origin: /static
- origin: index.html
- Viewer Requests ( ALB )
- ALB: /booking
- ALB Header: AllViewerExceptHostHeader
- lambda functioon url
- Lambda: /v1/book
```json
{
  "Sid": "Decrypt Role",
  "Effect": "Allow",
  "Principal": {
    "Service": "cloudfront.amazonaws.com"
  },
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey*"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "aws:SourceArn": "<CloudFront ARN>"
    }
  }
}
```
```bash
function handler(event) {
  var request = event.request;
  if (request.uri === '/booking') { request.uri = '/v1/book'; } 
  else if (request.uri === '/booking/') { request.uri = '/v1/book'; }
  return request;
}
```

<br>

<img alt="image" src="https://github.com/user-attachments/assets/95f6b23f-176b-42f2-ae66-4c13d8aed1d1" />
<img alt="image" src="https://github.com/user-attachments/assets/a9689117-df46-4c41-a54e-f06462ce6c82" />
