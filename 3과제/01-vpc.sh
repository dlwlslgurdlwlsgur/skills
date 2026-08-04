#!/bin/bash
set -x
REGION="ap-northeast-2"

VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=skills-vpc}]" \
    --query 'Vpc.VpcId' --output text \
    --region ${REGION})

aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames '{"Value": true}' --region ${REGION}
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support '{"Value": true}' --region ${REGION}

IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=skills-igw}]" \
    --query 'InternetGateway.InternetGatewayId' --output text \
    --region ${REGION})

aws ec2 attach-internet-gateway --vpc-id ${VPC_ID} --internet-gateway-id ${IGW_ID} --region ${REGION}

PUB_A_ID=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --cidr-block 10.0.0.0/24 --availability-zone ${REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=skills-public-a},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/skills-cluster,Value=shared}]" \
    --query 'Subnet.SubnetId' --output text --region ${REGION})
aws ec2 modify-subnet-attribute --subnet-id ${PUB_A_ID} --map-public-ip-on-launch --region ${REGION}

PUB_C_ID=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --cidr-block 10.0.1.0/24 --availability-zone ${REGION}c \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=skills-public-c},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/skills-cluster,Value=shared}]" \
    --query 'Subnet.SubnetId' --output text --region ${REGION})
aws ec2 modify-subnet-attribute --subnet-id ${PUB_C_ID} --map-public-ip-on-launch --region ${REGION}

PRI_A_ID=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --cidr-block 10.0.2.0/24 --availability-zone ${REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=skills-private-a},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/skills-cluster,Value=shared}]" \
    --query 'Subnet.SubnetId' --output text --region ${REGION})

PRI_B_ID=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --cidr-block 10.0.3.0/24 --availability-zone ${REGION}b \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=skills-private-b},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/skills-cluster,Value=shared}]" \
    --query 'Subnet.SubnetId' --output text --region ${REGION})

PRI_C_ID=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --cidr-block 10.0.4.0/24 --availability-zone ${REGION}c \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=skills-private-c},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/skills-cluster,Value=shared}]" \
    --query 'Subnet.SubnetId' --output text --region ${REGION})

PUB_RTB_ID=$(aws ec2 create-route-table --vpc-id ${VPC_ID} \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=skills-rt-public}]" \
    --query 'RouteTable.RouteTableId' --output text --region ${REGION})

aws ec2 create-route --route-table-id ${PUB_RTB_ID} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW_ID} --region ${REGION}
aws ec2 associate-route-table --route-table-id ${PUB_RTB_ID} --subnet-id ${PUB_A_ID} --region ${REGION}
aws ec2 associate-route-table --route-table-id ${PUB_RTB_ID} --subnet-id ${PUB_C_ID} --region ${REGION}

EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=skills-nat-eip}]" \
    --query 'AllocationId' --output text --region ${REGION})

NGW_ID=$(aws ec2 create-nat-gateway --subnet-id ${PUB_A_ID} --allocation-id ${EIP_ALLOC_ID} \
    --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=skills-nat}]" \
    --query 'NatGateway.NatGatewayId' --output text --region ${REGION})

aws ec2 wait nat-gateway-available --nat-gateway-ids ${NGW_ID} --region ${REGION}

PRI_RTB_ID=$(aws ec2 create-route-table --vpc-id ${VPC_ID} \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=skills-rt-private}]" \
    --query 'RouteTable.RouteTableId' --output text --region ${REGION})

aws ec2 create-route --route-table-id ${PRI_RTB_ID} --destination-cidr-block 0.0.0.0/0 --nat-gateway-id ${NGW_ID} --region ${REGION}
aws ec2 associate-route-table --route-table-id ${PRI_RTB_ID} --subnet-id ${PRI_A_ID} --region ${REGION}
aws ec2 associate-route-table --route-table-id ${PRI_RTB_ID} --subnet-id ${PRI_B_ID} --region ${REGION}
aws ec2 associate-route-table --route-table-id ${PRI_RTB_ID} --subnet-id ${PRI_C_ID} --region ${REGION}

aws ec2 create-vpc-endpoint --vpc-id ${VPC_ID} \
    --service-name "com.amazonaws.${REGION}.s3" --vpc-endpoint-type Gateway \
    --route-table-ids ${PRI_RTB_ID} ${PUB_RTB_ID} \
    --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=skills-s3-endpoint}]" \
    --region ${REGION}

get_or_create_sg() {
    local SG_NAME=$1
    local DESC=$2
    local SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${SG_NAME}" --query 'SecurityGroups[0].GroupId' --output text --region ${REGION} 2>/dev/null)
    if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
        SG_ID=$(aws ec2 create-security-group --group-name "${SG_NAME}" --description "${DESC}" --vpc-id ${VPC_ID} --query 'GroupId' --output text --region ${REGION})
    fi
    echo $SG_ID
}

ALB_SG_ID=$(get_or_create_sg "skills-alb-sg" "ALB ingress from CloudFront")
EKS_NODE_SG_ID=$(get_or_create_sg "skills-cluster-node-sg" "Additional SG for EKS nodes to access RDS")
RDS_SG_ID=$(get_or_create_sg "skills-rds-sg" "RDS from EKS nodes only")

aws ec2 authorize-security-group-ingress --group-id ${ALB_SG_ID} --protocol -1 --port all --cidr 0.0.0.0/0 --region ${REGION} 2>/dev/null || echo "Ingress rule already exists."
aws ec2 authorize-security-group-ingress --group-id ${EKS_NODE_SG_ID} --protocol -1 --port all --cidr 0.0.0.0/0 --region ${REGION} 2>/dev/null || echo "Ingress rule already exists."
aws ec2 authorize-security-group-ingress --group-id ${RDS_SG_ID} --protocol -1 --port all --cidr 0.0.0.0/0 --region ${REGION} 2>/dev/null || echo "Ingress rule already exists."