aws configure set default.region eu-west-1
aws configure set default.output json

VPC=$(aws ec2 create-vpc --cidr-block 172.16.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=event-vpc}]' \
  --query Vpc.VpcId --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames '{"Value":true}'

IGW=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=event-igw}]' --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC

mksub(){ aws ec2 create-subnet --vpc-id $VPC --cidr-block $2 --availability-zone $3 \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$1}]" --query Subnet.SubnetId --output text; }

PUBA=$(mksub event-pub-a   172.16.0.0/24 eu-west-1a)
PUBB=$(mksub event-pub-b   172.16.1.0/24 eu-west-1b)

for s in $PUBA $PUBB; do aws ec2 modify-subnet-attribute --subnet-id $s --map-public-ip-on-launch; done

mkrtb(){ aws ec2 create-route-table --vpc-id $VPC --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$1}]" --query RouteTable.RouteTableId --output text; }

PUBRT=$(mkrtb event-pub-rtb)

aws ec2 create-route --route-table-id $PUBRT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW

aws ec2 associate-route-table --route-table-id $PUBRT --subnet-id $PUBA
aws ec2 associate-route-table --route-table-id $PUBRT --subnet-id $PUBB

SG_ID=$(aws ec2 create-security-group \
    --group-name wsc2026-event-sg \
    --description "WSC2026 Event Security Group" \
    --vpc-id $VPC \
    --query 'GroupId' \
    --output text)
aws ec2 create-tags --resources $SG_ID --tags Key=Name,Value=wsc2026-event-sg

aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

echo