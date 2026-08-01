#!/bin/bash
set -x
export AWS_PAGER=""
REGION="ap-northeast-2"
DB_USER="admin"
PW="Skills2024**"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=skills-vpc" --query "Vpcs[0].VpcId" --output text --region ${REGION})
PRI_A_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-a" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PRI_B_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-b" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PRI_C_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-c" --query "Subnets[0].SubnetId" --output text --region ${REGION})
RDS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=skills-rds-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${REGION})

DB_SUBNET_GROUP="skills-db-subnets"
aws rds create-db-subnet-group \
  --db-subnet-group-name ${DB_SUBNET_GROUP} \
  --db-subnet-group-description "Multi-AZ RDS Subnet Group with A, B, C" \
  --subnet-ids ${PRI_A_ID} ${PRI_B_ID} ${PRI_C_ID} \
  --region ${REGION} || echo "Subnet group already exists."

aws rds create-db-instance \
  --db-instance-identifier "apdev-rds-instance" \
  --engine mysql \
  --engine-version 8.0 \
  --db-instance-class db.t3.micro \
  --allocated-storage 20 \
  --storage-type gp3 \
  --master-username ${DB_USER} \
  --master-user-password "${PW}" \
  --vpc-security-group-ids ${RDS_SG_ID} \
  --db-subnet-group-name ${DB_SUBNET_GROUP} \
  --multi-az \
  --no-publicly-accessible \
  --region ${REGION} || echo "RDS creation skipped or already exists."

SECRET_NAME="skills-db-secret-$(date +%s)"
SECRET_ARN=$(aws secretsmanager create-secret \
    --name "${SECRET_NAME}" \
    --secret-string "{\"username\":\"${DB_USER}\",\"password\":\"${PW}\"}" \
    --region ${REGION} \
    --query 'ARN' --output text)

cat <<EOF > proxy-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

PROXY_ROLE_ARN=$(aws iam create-role \
    --role-name "SkillsRDSProxyRole-$(date +%s)" \
    --assume-role-policy-document file://proxy-trust-policy.json \
    --query 'Role.Arn' --output text)

rm proxy-trust-policy.json

aws iam attach-role-policy \
  --role-name $(basename ${PROXY_ROLE_ARN}) \
  --policy-arn "arn:aws:iam::aws:policy/SecretsManagerReadWrite"

sleep 15

aws rds create-db-proxy \
  --db-proxy-name "skills-rds-proxy" \
  --engine-family "MYSQL" \
  --auth "[{\"AuthScheme\":\"SECRETS\",\"SecretArn\":\"${SECRET_ARN}\",\"IAMAuth\":\"DISABLED\",\"ClientPasswordAuthType\":\"MYSQL_NATIVE_PASSWORD\"}]" \
  --role-arn "${PROXY_ROLE_ARN}" \
  --vpc-subnet-ids "${PRI_A_ID}" "${PRI_B_ID}" "${PRI_C_ID}" \
  --vpc-security-group-ids "${RDS_SG_ID}" \
  --no-require-tls \
  --region ${REGION} || echo "RDS Proxy creation failed or already exists."[cite: 1]
  
aws rds register-db-proxy-targets \
  --db-proxy-name "skills-rds-proxy" \
  --target-group-name "default" \
  --db-instance-identifiers "apdev-rds-instance" \
  --region ap-northeast-2