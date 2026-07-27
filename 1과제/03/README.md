## CloudShell
- mark-sg 만들고 wsc2026-skills-app-sub-a에 연결

<br>

## shell
- 01-vpc.sh
- 02-kms.sh
- 03-cluster.sh

<br>

## S3
- wsc2026-static-<임의의 영문 4자리>-<비번호>-bucket
- KMS
- /static

<br>

## ECR
- 04-ecr.sh
- 배포파일/book
- v1* 설정
```bash
chmod 777 book
cat <<EOF > Dockerfile
FROM alpine:latest
WORKDIR /app
COPY ./book /app/main
RUN apk update && \\
  apk add --no-cache libc6-compat libstdc++ libgcc curl openssl && \\
  apk upgrade --no-cache busybox && \\
  chmod +x /app/main
EXPOSE 8080
CMD ["/app/main"]
EOF
```
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com"
docker build -t "wsc2026-book-ecr:v1.0.0" .
docker tag "wsc2026-book-ecr:v1.0.0" "${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/wsc2026-book-ecr:v1.0.0"
docker push "${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/wsc2026-book-ecr:v1.0.0"
```

<br>

## DynamoDB & Lambda
- 05-dyanmodb.sh
- wsc2026-book-get-function
- Python 3.12
- kms 연결 ( 시작, 환경변수 )
- 환경변수 { TABLE_NAME: wsc2026-book-table(암호화) }
- 30초

<br>

## CloudFront
- wsc2026-cdn
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

## shell
- 06-app.sh
- 07-monitoring.sh
- 08-waf.sh
- cloudFront 연결


185