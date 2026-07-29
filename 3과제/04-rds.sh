export AWS_PAGER=""
REGION="ap-northeast-2"
DB_USER="admin"
PW="Skills2024**"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=skills-vpc" --query "Vpcs[0].VpcId" --output text --region ${REGION})
PRI_A_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-a" --query "Subnets[0].SubnetId" --output text --region ${REGION})
PRI_C_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-c" --query "Subnets[0].SubnetId" --output text --region ${REGION})
RDS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=skills-rds-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${REGION})

DB_SUBNET_GROUP="skills-db-subnets"
aws rds create-db-subnet-group --db-subnet-group-name "${DB_SUBNET_GROUP}" \
    --db-subnet-group-description "RDS Subnet Group" \
    --subnet-ids ${PRI_A_ID} ${PRI_C_ID} --region ${REGION} >/dev/null 2>&1 || echo "DB Subnet Group already exists"

aws rds create-db-instance \
    --db-instance-identifier "skills-mysql80" \
    --engine mysql \
    --engine-version "8.0" \
    --db-instance-class db.t3.micro \
    --allocated-storage 20 \
    --storage-type gp3 \
    --master-username "${DB_USER}" \
    --master-user-password "${PW}" \
    --vpc-security-group-ids ${RDS_SG_ID} \
    --db-subnet-group-name "${DB_SUBNET_GROUP}" \
    --multi-az \
    --no-publicly-accessible \
    --region ${REGION}