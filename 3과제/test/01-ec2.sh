#!/bin/bash
set -x
REGION="ap-northeast-2"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=skills-vpc" --query "Vpcs[0].VpcId" --output text --region ${REGION})

cat << 'EOF' > bastion-userdata.sh
#!/bin/bash
sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
echo "ec2-user:1234" | chpasswd
systemctl restart sshd
sudo yum install python3-pip -y
pip3 install requests
EOF

SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=skills-public-a" \
  --query "Subnets[0].SubnetId" \
  --output text \
  --region ${REGION})

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=skills-alb-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region ${REGION})

aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type c5.large \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --user-data file://bastion-userdata.sh \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-bastion}]' \
  --region ${REGION}