## IAM User
- admin으로 user 생성 및 접속

<br>

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
- variable.contestant_number 수정
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
- 배포파일: book
```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION="ap-northeast-2"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
aws ecr create-repository --repository-name kiwigrid/k8s-sidecar --region $REGION
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
docker pull quay.io/kiwigrid/k8s-sidecar:1.28.0
docker tag quay.io/kiwigrid/k8s-sidecar:1.28.0 ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kiwigrid/k8s-sidecar:1.28.0
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/kiwigrid/k8s-sidecar:1.28.0
echo
```

<br>

## 02-k8s
- variable.contestant_number 수정
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
- name: unicorn-mark
- eks 설정
```bash
aws eks update-cluster-config \
  --name unicorn-eks-cluster \
  --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true
```
```bash
aws eks update-cluster-config \
  --name unicorn-eks-cluster \
  --access-config authenticationMode=API
```

<br>

- ALB 접근 제한
```bash
ALB_SG=$(aws elbv2 describe-load-balancers --names unicorn-alb --query "LoadBalancers[0].SecurityGroups[0]" --output text)
aws ec2 describe-security-groups --group-ids $ALB_SG \
  --query "SecurityGroups[0].IpPermissions" \
  --output json > /tmp/all_ingress_rules.json
aws ec2 revoke-security-group-ingress \
  --group-id $ALB_SG \
  --ip-permissions file:///tmp/all_ingress_rules.json 2>/dev/null
CF_PREFIX_ID=$(aws ec2 describe-managed-prefix-lists \
  --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing" \
  --query "PrefixLists[0].PrefixListId" \
  --output text)
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,PrefixListIds=[{PrefixListId=$CF_PREFIX_ID,Description='Allow CloudFront only'}]"
```

<br>

- ALB 트래픽
```bash
CF_DOMAIN=$(aws cloudfront list-distributions --query "DistributionList.Items[0].DomainName" --output text)
for i in {1..50}; do 
  curl -s -o /dev/null -w "%{http_code}\n" -X POST "https://$CF_DOMAIN/v1/book" \
    -H 'Content-Type: application/json' \
    -d '{"client_id":"NORMAL_USER"}'
  sleep 0.5
done
```