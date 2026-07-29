REGION="ap-northeast-2"
PROJECT="wsc2026"
CLUSTER_NAME="${PROJECT}-eks"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT}-vpc" "Name=state,Values=available" --query "Vpcs[0].VpcId" --output text --region ${REGION})
PUB_A_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-public-a" "Name=state,Values=available" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PUB_C_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-public-c" "Name=state,Values=available" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PRI_A_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-private-a" "Name=state,Values=available" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PRI_C_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-private-c" "Name=state,Values=available" --query "Subnets[0].SubnetId" --output text --region ${REGION})
EKS_NODE_SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${PROJECT}-eks-node-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${REGION})

cat << EOF > cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}
  version: "1.35"
  tags:
    Project: ${PROJECT}

vpc:
  id: "${VPC_ID}"
  subnets:
    public:
      ap-northeast-2a: { id: "${PUB_A_ID}" }
      ap-northeast-2c: { id: "${PUB_C_ID}" }
    private:
      ap-northeast-2a: { id: "${PRI_A_ID}" }
      ap-northeast-2c: { id: "${PRI_C_ID}" }

managedNodeGroups:
  - name: ${PROJECT}-nodegroup
    instanceType: t3.medium
    minSize: 2
    maxSize: 4
    desiredCapacity: 2
    privateNetworking: true
    securityGroups:
      attachIDs:
        - "${EKS_NODE_SG_ID}"
    tags:
      Project: ${PROJECT}
    iam:
      withAddonPolicies:
        autoScaler: true
        albIngress: true
        cloudWatch: true
EOF

curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl create cluster -f cluster.yaml