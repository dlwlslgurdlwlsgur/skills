cat << 'EOF' > bastion-userdata.sh
#!/bin/bash
sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
echo "ec2-user:1234" | chpasswd
systemctl restart sshd
sudo yum install python3-pip -y
pip3 install requests
EOF

SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=skills-public-a" \
  --query "Subnets[0].SubnetId" \
  --output text)

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=concert-bastion-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text)

aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type c5.large \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="concert-bastion-profile" \
  --user-data file://bastion-userdata.sh \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-bastion}]'