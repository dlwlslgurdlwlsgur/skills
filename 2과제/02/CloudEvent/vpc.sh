aws configure set default.region eu-west-1
aws configure set default.output json

# 1. VPC 생성 (event-vpc / 172.16.0.0/16)
VPC=$(aws ec2 create-vpc --cidr-block 172.16.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=event-vpc}]' \
  --query Vpc.VpcId --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames '{"Value":true}'

# 2. 인터넷 게이트웨이(IGW) 생성 및 연결
IGW=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=event-igw}]' --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC

# 3. 서브넷 생성 펑션 정의 및 퍼블릭 서브넷 2개 생성
mksub(){ aws ec2 create-subnet --vpc-id $VPC --cidr-block $2 --availability-zone $3 \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$1}]" --query Subnet.SubnetId --output text; }

PUBA=$(mksub event-pub-a   172.16.0.0/24 eu-west-1a)
PUBB=$(mksub event-pub-b   172.16.1.0/24 eu-west-1b)

# 4. 퍼블릭 서브넷 자동 퍼블릭 IP 할당 설정
for s in $PUBA $PUBB; do aws ec2 modify-subnet-attribute --subnet-id $s --map-public-ip-on-launch; done

# 5. 라우트 테이블 생성 펑션 정의 및 생성 (event-pub-rtb)
mkrtb(){ aws ec2 create-route-table --vpc-id $VPC --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$1}]" --query RouteTable.RouteTableId --output text; }

PUBRT=$(mkrtb event-pub-rtb)

# 6. 라우트 규칙 생성 (인터넷 게이트웨이 매핑)
aws ec2 create-route --route-table-id $PUBRT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW

# 7. 라우팅 테이블 - 서브넷 연결(Association)
aws ec2 associate-route-table --route-table-id $PUBRT --subnet-id $PUBA
aws ec2 associate-route-table --route-table-id $PUBRT --subnet-id $PUBB