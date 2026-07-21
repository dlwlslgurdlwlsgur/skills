## ECR
- 배포파일 book 삽입
- 04-ecr.sh

<br>

## DynamoDB & Lambda
- 05-dyanmodb.sh
- wsc2026-book-get-function
- Python 3.12
- lambda 역활 만들어져 있음
- kms 연결 ( 시작, 환경변수 )

<br>

## EKS
- 보안그룹 anyopen
```bash
CLUSTER_NAME="wsc2026-eks-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
eksctl utils write-kubeconfig --name $CLUSTER_NAME
eksctl utils associate-iam-oidc-provider --approve --cluster $CLUSTER_NAME
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root"
aws eks associate-access-policy \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

<br>

## CloudFront
- wsc2026-cdn
- origin: /static
- origin: index.html
- Viewer Requests ( ALB )
- lambda functioon url
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

## WAF
- 07-waf.sh
- cloudFront 연결

<br>

## CloudShell
- mark-sg 만들고 wsc2026-skills-app-sub-a에 연결해서 대기