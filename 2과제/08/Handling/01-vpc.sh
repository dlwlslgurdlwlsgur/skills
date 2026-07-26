rm -rf ~/.aws
REGION="ap-southeast-1"
AZ1=$(aws ec2 describe-availability-zones --region $REGION --query 'AvailabilityZones[0].ZoneName' --output text)

echo "=== 1. VPC 생성 (skills-ceh-vpc / 10.73.0.0/16) ==="
VPC_ID=$(aws ec2 create-vpc \
    --region $REGION \
    --cidr-block 10.73.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=skills-ceh-vpc}]' \
    --query 'Vpc.VpcId' --output text)

# DNS 호스트네임 및 DNS 확인 활성화
aws ec2 modify-vpc-attribute --region $REGION --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --region $REGION --vpc-id $VPC_ID --enable-dns-support

echo "VPC ID: $VPC_ID"

echo "=== 2. 인터넷 게이트웨이(IGW) 생성 및 VPC 연결 ==="
IGW_ID=$(aws ec2 create-internet-gateway \
    --region $REGION \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=skills-ceh-igw}]' \
    --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway --region $REGION --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
echo "IGW ID: $IGW_ID"

echo "=== 3. 퍼블릭 서브넷 1개 생성 ==="
PUB_SUB_ID=$(aws ec2 create-subnet \
    --region $REGION \
    --vpc-id $VPC_ID \
    --cidr-block 10.73.1.0/24 \
    --availability-zone $AZ1 \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=skills-ceh-pub-1}]' \
    --query 'Subnet.SubnetId' --output text)

# 퍼블릭 IP 자동 할당 활성화
aws ec2 modify-subnet-attribute --region $REGION --subnet-id $PUB_SUB_ID --map-public-ip-on-launch
echo "Public Subnet ID ($AZ1): $PUB_SUB_ID"

echo "=== 4. 라우팅 테이블 생성 및 서브넷 연결 ==="
PUB_RT_ID=$(aws ec2 create-route-table \
    --region $REGION \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=skills-ceh-pub-rt}]' \
    --query 'RouteTable.RouteTableId' --output text)

# IGW로 향하는 기본 라우트(0.0.0.0/0) 추가
aws ec2 create-route \
    --region $REGION \
    --route-table-id $PUB_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID > /dev/null

# 라우팅 테이블에 퍼블릭 서브넷 연결
aws ec2 associate-route-table \
    --region $REGION \
    --subnet-id $PUB_SUB_ID \
    --route-table-id $PUB_RT_ID > /dev/null

echo