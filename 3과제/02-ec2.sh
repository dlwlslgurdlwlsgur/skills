#!/bin/bash
set -x
REGION="ap-northeast-2"
INSTANCE_NAME="apdev-bastion"
ROLE_NAME="${INSTANCE_NAME}-role"
PROFILE_NAME="${INSTANCE_NAME}-profile"
SG_NAME="${INSTANCE_NAME}-sg"

# 1. IAM 역할 및 권한 (PowerUserAccess) 생성
cat << EOF > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://trust-policy.json 2>/dev/null || true
aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam create-instance-profile --instance-profile-name ${PROFILE_NAME} 2>/dev/null || true
aws iam add-role-to-instance-profile --instance-profile-name ${PROFILE_NAME} --role-name ${ROLE_NAME} 2>/dev/null || true
rm -f trust-policy.json

sleep 10

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=skills-vpc" "Name=state,Values=available" --query "Vpcs[0].VpcId" --output text --region ${REGION})
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=skills-public-a" --query "Subnets[0].SubnetId" --output text --region ${REGION} 2>/dev/null)

SG_ID=$(aws ec2 create-security-group \
  --group-name ${SG_NAME} \
  --description "Any open SG for bastion" \
  --vpc-id ${VPC_ID} \
  --query 'GroupId' \
  --output text \
  --region ${REGION} 2>/dev/null || aws ec2 describe-security-groups --filters "Name=group-name,Values=${SG_NAME}" --query 'SecurityGroups[0].GroupId' --output text --region ${REGION})

aws ec2 authorize-security-group-ingress \
  --group-id ${SG_ID} \
  --protocol -1 \
  --port all \
  --cidr 0.0.0.0/0 \
  --region ${REGION} 2>/dev/null || echo "Ingress rule already exists."

cat << 'EOF' > user-data.sh
#!/bin/bash
export AWS_DEFAULT_REGION="ap-northeast-2"
sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
echo "ec2-user:1234" | chpasswd
systemctl restart sshd
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.35.3/2026-04-08/bin/linux/amd64/kubectl
sudo chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin
sudo yum install docker -y
sudo usermod -aG docker ec2-user
sudo systemctl enable --now docker
sudo chmod 666 /var/run/docker.sock
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
sudo yum install mariadb105 -y
EOF

AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query 'Parameters[0].Value' --output text --region ${REGION})

aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --instance-type t3.medium \
  --subnet-id ${SUBNET_ID} \
  --security-group-ids ${SG_ID} \
  --iam-instance-profile Name=${PROFILE_NAME} \
  --user-data file://user-data.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
  --associate-public-ip-address \
  --region ${REGION} >/dev/null
