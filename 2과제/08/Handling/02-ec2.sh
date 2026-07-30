#!/bin/bash
set -x
set -e
REGION="ap-southeast-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
TIMESTAMP=$(date +%s)

echo "=== 1. 기존 VPC 및 서브넷 조회 ==="
VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=skills-ceh-vpc" --query "Vpcs[0].VpcId" --output text)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    echo "[오류] skills-ceh-vpc를 찾을 수 없습니다. 이전 VPC 생성 스크립트를 먼저 실행해주세요."
    exit 1
fi
echo "VPC ID: $VPC_ID"

# 이전 스크립트에서 생성한 퍼블릭 서브넷 조회
SUB_ID=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=skills-ceh-pub-1" --query "Subnets[0].SubnetId" --output text)
echo "Subnet ID: $SUB_ID"


echo "=== 2. 감시 대상(Protected) 보안 그룹 생성 ==="
PROTECTED_SG_ID=$(aws ec2 create-security-group --region $REGION \
    --group-name "skills-ceh-protected-sg-$TIMESTAMP" \
    --description "Protected Security Group for CEH Remediation" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=skills-ceh-protected-sg}]' \
    --query "GroupId" --output text)
echo "Protected Security Group ID: $PROTECTED_SG_ID"


echo "=== 3. 최신 Amazon Linux 2023 AMI 조회 ==="
AMI_ID=$(aws ssm get-parameters --region $REGION --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query "Parameters[0].Value" --output text)
echo "AMI ID: $AMI_ID"


echo "=== 4. EC2 인스턴스 (skills-ceh-ec2) 생성 ==="
EC2_ID=$(aws ec2 run-instances --region $REGION \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --subnet-id $SUB_ID \
    --security-group-ids $PROTECTED_SG_ID \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=skills-ceh-ec2}]' \
    --query "Instances[0].InstanceId" --output text)