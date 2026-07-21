## module 설치
```bash
aws configure
```
```bash
winget install Kubernetes.kubectl
winget install Helm.Helm
winget install HashiCorp.Terraform
```

<br>

## 01-vpc
- variable.badge_number 수정
```bash
cd ./01-vpc
```
```bash
terraform init
```
```bash
terraform plan
```
```bash
terraform apply
```

<br>

## S3
- index.html, main.jpeg
```bash
{
    "Sid": "Decrypy Role",
    "Effect": "Allow",
    "Principal": {
        "Service": "cloudfront.amazonaws.com"
    },
    "Action": "kms:*",
    "Resource": "*",
    "Condition": {
        "StringEquals": {
            "aws:SourceArn": "<CLOUDFRONT_ARN>"
        }
    }
}
```

<br>

## ECR
- 배포파일: book, printenv
```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION="ap-northeast-2"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

chmod +x book
cat <<EOF > Dockerfile
FROM alpine:3.20 AS builder
RUN apk add --no-cache ca-certificates upx binutils
COPY book /book
RUN strip --strip-all /book 2>/dev/null || true
RUN upx --lzma /book
FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /book /book
EXPOSE 8080
ENTRYPOINT ["/book"]
EOF
docker build -t book:latest .
docker tag book:latest "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/book:latest"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/book:latest"
docker pull grafana/grafana:11.4.0
docker tag grafana/grafana:11.4.0 "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/grafana:11.4.0"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/grafana:11.4.0"
docker pull curlimages/curl:8.9.1
docker tag curlimages/curl:8.9.1 "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/curlimages/curl:8.9.1"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/curlimages/curl:8.9.1"
aws ecr create-repository --repository-name ecr-public/eks/aws-load-balancer-controller --region ap-northeast-2
docker pull public.ecr.aws/eks/aws-load-balancer-controller:v2.13.4
docker tag public.ecr.aws/eks/aws-load-balancer-controller:v2.13.4 "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/ecr-public/eks/aws-load-balancer-controller:v2.13.4"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/ecr-public/eks/aws-load-balancer-controller:v2.13.4"
echo
```

<br>

## 02-k8s
```bash
aws eks update-kubeconfig --region ap-northeast-2 --name gj2026-eks-cluster
kubectl get all -A
```
```bash
cd ./02-k8s
```
```bash
# Remove-Item .terraform.lock.hcl -ErrorAction SilentlyContinue
terraform init
```
```bash
terraform apply -target="helm_release.aws_load_balancer_controller" -auto-approve
terraform apply -auto-approve
```

<br>

## CloudShell
```bash
CLUSTER_NAME="gj2026-eks-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root"
aws eks associate-access-policy \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster

aws eks update-kubeconfig --region ap-northeast-2 --name gj2026-eks-cluster

ALB_IP1=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*ELB*app/*" --query "NetworkInterfaces[0].PrivateIpAddress" --output text)
ALB_IP2=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*ELB*app/*" --query "NetworkInterfaces[1].PrivateIpAddress" --output text)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: book-allow-from-alb-only
  namespace: skills
spec:
  podSelector:
    matchLabels:
      app: book
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: ${ALB_IP1}/32
    - ipBlock:
        cidr: ${ALB_IP2}/32
    ports:
    - protocol: TCP
      port: 8080
EOF
```

<br>

## 채점
- dynamoDB 데이터 삭제