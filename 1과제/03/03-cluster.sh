REGION="ap-northeast-2"
export AWS_DEFAULT_REGION="$REGION"

KMS_EKS_ALIAS="alias/wsc2026-eks-kms"
SG_NAME="wsc2026-eks-sg"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

# 1. AWS 리소스 조회를 위한 기반 정보 가져오기
say "AWS 계정 ID 및 VPC ID 조회 중..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ok "조회된 계정 ID: $ACCOUNT_ID"

# 태그 Name이 wsc2026-vpc 인 VPC를 찾습니다.
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=wsc2026-skills-vpc" \
  --query "Vpcs[0].VpcId" --output text)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "❌ 태그(Name=wsc2026-vpc)에 해당하는 VPC를 찾을 수 없습니다."
    exit 1
fi
ok "조회된 VPC ID: $VPC_ID"


# 2. 보안 그룹 생성 및 모든 트래픽(0.0.0.0/0) 인/아웃바운드 허용
say "보안 그룹 확인 및 생성 중: $SG_NAME"
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text)

if [ -z "$SECURITY_GROUP_ID" ] || [ "$SECURITY_GROUP_ID" = "None" ]; then
  SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Security group for wsc2026 EKS Cluster" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SG_NAME}]" \
    --query "GroupId" --output text)
  ok "보안 그룹 새로 생성 완료: $SECURITY_GROUP_ID"
else
  ok "기존 보안 그룹 발견: $SECURITY_GROUP_ID"
fi

say "보안 그룹 인바운드 규칙 설정 중 (모든 트래픽, 0.0.0.0/0)..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SECURITY_GROUP_ID" \
  --protocol all \
  --cidr 0.0.0.0/0 2>/dev/null || ok "인바운드 규칙이 이미 존재하거나 적용되었습니다."

# 3. KMS ARN 및 서브넷 ID 조회
say "KMS 및 서브넷 정보 조회 중..."
KMS_ARN=$(aws kms describe-key --key-id "$KMS_EKS_ALIAS" --query 'KeyMetadata.Arn' --output text)
ok "조회된 KMS ARN: $KMS_ARN"

SUBNET_2A_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=wsc2026-skills-app-sub-a" "Name=availability-zone,Values=ap-northeast-2a" \
  --query "Subnets[0].SubnetId" --output text)

SUBNET_2B_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=wsc2026-skills-app-sub-b" "Name=availability-zone,Values=ap-northeast-2b" \
  --query "Subnets[0].SubnetId" --output text)

if [ "$SUBNET_2A_ID" = "None" ] || [ "$SUBNET_2B_ID" = "None" ]; then
    echo "❌ 프라이빗 서브넷(wsc2026-pri-sub-a/b)을 찾지 못했습니다. 태그를 확인해 주세요."
    exit 1
fi
ok "조회된 Subnet 2a: $SUBNET_2A_ID"
ok "조회된 Subnet 2b: $SUBNET_2B_ID"


# 4. cluster.yaml 파일 동적 생성
say "cluster.yaml 생성 시작..."

cat <<EOF > cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: wsc2026-eks-cluster
  version: "1.35"
  region: ap-northeast-2

secretsEncryption:
  keyARN: $KMS_ARN

cloudWatch:
  clusterLogging:
    enableTypes: ["*"]

iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
    wellKnownPolicies:
      awsLoadBalancerController: true
  - metadata:
      name: cert-manager
      namespace: cert-manager
    wellKnownPolicies:
      certManager: true

vpc:
  securityGroup: $SECURITY_GROUP_ID
  subnets:
    private:
      ap-northeast-2a: { id: $SUBNET_2A_ID }
      ap-northeast-2b: { id: $SUBNET_2B_ID }
  clusterEndpoints:
    publicAccess: false
    privateAccess: true
      
managedNodeGroups:
  - name: wsc2026-workload-ng
    labels: { wsc2026/node: application }
    instanceName: wsc2026-workload-node
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 20
    privateNetworking: true
    amiFamily: AmazonLinux2023

  - name: wsc2026-addon-nodegroup
    labels: { wsc2026/node: addon }
    instanceName: wsc2026-addon-node
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 20
    privateNetworking: true
    amiFamily: AmazonLinux2023
EOF