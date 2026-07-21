aws configure set default.region ap-northeast-2
aws configure set default.output json

# 1. VPC 생성 (wsc2026-skills-vpc / 192.168.0.0/16)
VPC=$(aws ec2 create-vpc --cidr-block 192.168.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=wsc2026-skills-vpc}]' \
  --query Vpc.VpcId --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames '{"Value":true}'

# 2. 인터넷 게이트웨이(IGW) 생성 및 VPC 연결
IGW=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=wsc2026-skills-igw}]' --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC

# 서브넷 생성 헬퍼 함수 정의
mksub(){ aws ec2 create-subnet --vpc-id $VPC --cidr-block $2 --availability-zone $3 \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$1}]" --query Subnet.SubnetId --output text; }

# 3. 서브넷 생성 (Hub 및 App 서브넷)
HUB_A=$(mksub wsc2026-skills-hub-sub-a   192.168.1.0/24  ap-northeast-2a)
HUB_B=$(mksub wsc2026-skills-hub-sub-b   192.168.10.0/24 ap-northeast-2b)
APP_A=$(mksub wsc2026-skills-app-sub-a   192.168.2.0/24  ap-northeast-2a)
APP_B=$(mksub wsc2026-skills-app-sub-b   192.168.20.0/24 ap-northeast-2b)

# Hub(퍼블릭) 서브넷은 기본적으로 퍼블릭 IP를 할당하도록 설정
for s in $HUB_A $HUB_B; do aws ec2 modify-subnet-attribute --subnet-id $s --map-public-ip-on-launch; done

# 4. NAT 게이트웨이 생성 (App 서브넷의 아웃바운드 인터넷 통신용)
EIPA=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NATA=$(aws ec2 create-nat-gateway --subnet-id $HUB_A --allocation-id $EIPA \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=wsc2026-skills-nat-a}]' --query NatGateway.NatGatewayId --output text)

EIPB=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NATB=$(aws ec2 create-nat-gateway --subnet-id $HUB_B --allocation-id $EIPB \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=wsc2026-skills-nat-b}]' --query NatGateway.NatGatewayId --output text)

# 두 NAT 게이트웨이가 활성화될 때까지 대기
aws ec2 wait nat-gateway-available --nat-gateway-ids $NATA $NATB

# 라우팅 테이블 생성 헬퍼 함수 정의
mkrtb(){ aws ec2 create-route-table --vpc-id $VPC --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$1}]" --query RouteTable.RouteTableId --output text; }

# 5. 라우팅 테이블 생성
HUB_RT=$(mkrtb wsc2026-skills-hub-rtb)
APP_A_RT=$(mkrtb wsc2026-skills-app-rtb-a)
APP_B_RT=$(mkrtb wsc2026-skills-app-rtb-b)

# 6. 라우팅 규칙 추가 (0.0.0.0/0 목적지 지정)
aws ec2 create-route --route-table-id $HUB_RT   --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
aws ec2 create-route --route-table-id $APP_A_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NATA
aws ec2 create-route --route-table-id $APP_B_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NATB

# 7. 서브넷 - 라우팅 테이블 연결(Association)
aws ec2 associate-route-table --route-table-id $HUB_RT   --subnet-id $HUB_A
aws ec2 associate-route-table --route-table-id $HUB_RT   --subnet-id $HUB_B
aws ec2 associate-route-table --route-table-id $APP_A_RT --subnet-id $APP_A
aws ec2 associate-route-table --route-table-id $APP_B_RT --subnet-id $APP_B

# 8. 쿠버네티스(EKS) 및 로드밸런서 연동용 서브넷 태그 설정
aws ec2 create-tags --resources $HUB_A $HUB_B --tags Key=kubernetes.io/role/elb,Value=1
aws ec2 create-tags --resources $APP_A $APP_B --tags Key=kubernetes.io/role/internal-elb,Value=1 Key=karpenter.sh/discovery,Value=wsc2026-eks-cluster