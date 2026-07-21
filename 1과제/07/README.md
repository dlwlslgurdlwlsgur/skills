## IAM User
- admin으로 user 생성 및 접속


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
terraform init
terraform plan
terraform apply
```

<br>

## S3
- index.html, main.jpeg

<br>

## ECR
- 배포파일: book, printenv
```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION="ap-northeast-2"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
chmod +x book
cat <<EOF > Dockerfile
FROM alpine:3.20
RUN apk add --no-cache ca-certificates coreutils
COPY book /book
EXPOSE 8080
ENTRYPOINT ["/book"]
EOF
docker build -t unicorn-concert-app:v1.0.0 .
docker tag unicorn-concert-app:v1.0.0 "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/unicorn-concert-app:v1.0.0"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/unicorn-concert-app:v1.0.0"
docker pull grafana/grafana:11.4.0
docker tag grafana/grafana:11.4.0 "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/grafana:11.4.0"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/grafana:11.4.0"
docker pull curlimages/curl:8.9.1
docker tag curlimages/curl:8.9.1 "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/curlimages/curl:8.9.1"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/curlimages/curl:8.9.1"
docker pull public.ecr.aws/eks/aws-load-balancer-controller:v2.13.4
docker tag public.ecr.aws/eks/aws-load-balancer-controller:v2.13.4 "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/ecr-public/eks/aws-load-balancer-controller:v2.13.4"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/ecr-public/eks/aws-load-balancer-controller:v2.13.4"
aws ecr create-repository --repository-name kiwigrid/k8s-sidecar --region $REGION
docker pull quay.io/kiwigrid/k8s-sidecar:1.28.0
docker tag quay.io/kiwigrid/k8s-sidecar:1.28.0 ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kiwigrid/k8s-sidecar:1.28.0
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kiwigrid/k8s-sidecar:1.28.0
echo
```

<br>

## 02-k8s
- variable.badge_number 수정
```bash
aws eks update-kubeconfig --region ap-northeast-2 --name unicorn-eks-cluster
```
```bash
cd ./02-k8s
terraform init
terraform apply -target="helm_release.aws_load_balancer_controller" -auto-approve
terraform apply -auto-approve
```

<br>

## CloudShell
```bash
CLUSTER_NAME="unicorn-eks-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:user/admin"
aws eks associate-access-policy \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:user/admin" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
aws eks update-kubeconfig --region ap-northeast-2 --name unicorn-eks-cluster
kubectl get all -A
```


183
198
모니터링