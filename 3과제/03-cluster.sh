#!/bin/bash
set -x
REGION="ap-northeast-2"
CLUSTER_NAME="skills-cluster"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=skills-vpc" "Name=state,Values=available" --query "Vpcs[0].VpcId" --output text --region ${REGION})
PUB_A_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=skills-public-a" "Name=state,Values=available" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PUB_C_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=skills-public-c" "Name=state,Values=available" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PRI_A_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=skills-private-a" "Name=state,Values=available" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PRI_C_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=skills-private-c" "Name=state,Values=available" --query "Subnets[0].SubnetId" --output text --region ${REGION})
EKS_NODE_SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=skills-cluster-node-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${REGION})

cat << EOF > cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}
  version: "1.35"

cloudWatch:
  clusterLogging:
    enableTypes: ["*"]

addons:
  - name: amazon-cloudwatch-observability

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
  id: "${VPC_ID}"
  subnets:
    public:
      ap-northeast-2a: { id: "${PUB_A_ID}" }
      ap-northeast-2c: { id: "${PUB_C_ID}" }
    private:
      ap-northeast-2a: { id: "${PRI_A_ID}" }
      ap-northeast-2c: { id: "${PRI_C_ID}" }

managedNodeGroups:
  - name: skills-nodegroup
    instanceType: t3.medium
    minSize: 2
    maxSize: 4
    desiredCapacity: 2
    privateNetworking: true
    securityGroups:
      attachIDs:
        - "${EKS_NODE_SG_ID}"
    iam:
      withAddonPolicies:
        autoScaler: true
        albIngress: true
        cloudWatch: true
EOF

eksctl create cluster -f cluster.yaml