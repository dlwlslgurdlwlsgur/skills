set -u
export AWS_PAGER=""
for CMD in aws curl; do
  if ! command -v "$CMD" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $CMD" >&2
    exit 2
  fi
done


aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc,skills-lattice-service-vpc --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,Cidr:CidrBlock,State:State}' --output table
# skills-lattice-client-vpc의 Cidr=10.61.0.0/16, State=available이어야 합니다.
# skills-lattice-service-vpc의 Cidr=10.62.0.0/16, State=available이어야 합니다.


aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,State:State.Name}' --output table
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/health"
# skills-lattice-client-ec2와 skills-lattice-service-ec2가 State=running이어야 합니다.
# skills-lattice-client-ec2는 PublicIp가 존재해야 하고, skills-lattice-service-ec2는 PublicIp가 없어야 합니다.
# Client /health 응답의 http_code=200이고 status=ok, app=client가 포함되어야 합니다.


aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].{Name:name,Id:id,AssociatedVPCs:numberOfAssociatedVPCs,AssociatedServices:numberOfAssociatedServices}' --output table
aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].{Name:name,Id:id,Dns:dnsEntry.domainName,Status:status}' --output table
aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{AssociationId:id,VpcId:vpcId,Status:status}' --output table
aws vpc-lattice get-service-network-vpc-association --region ap-northeast-1 --service-network-vpc-association-identifier "$VPC_ASSOCIATION_ID" --query '{AssociationId:id,VpcId:vpcId,Status:status,SecurityGroupIds:securityGroupIds}' --output table
aws vpc-lattice list-service-network-service-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{ServiceId:serviceId,Status:status,Dns:dnsEntry.domainName}' --output table
# Service Network Name=skills-lattice-sn이 존재해야 합니다.
# Service Name=skills-lattice-order-service가 존재하고 Status=ACTIVE이며 Dns가 출력되어야 합니다.
# Client VPC Association의 Status=ACTIVE이어야 합니다.
# Service Association의 Status=ACTIVE이어야 합니다.


aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].{Name:name,Id:id,Type:type,Port:port,Protocol:protocol,Vpc:vpcIdentifier,Status:status}' --output table
aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TARGET_GROUP_ID" --query 'items[].{Target:id,Port:port,Status:status}' --output table
aws vpc-lattice list-listeners --region ap-northeast-1 --service-identifier "$SERVICE_ID" --query 'items[?name==`skills-lattice-http-listener`].{Name:name,Id:id,Port:port,Protocol:protocol}' --output table
aws ec2 describe-security-groups --region ap-northeast-1 --group-ids $SERVICE_SG_IDS --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId,Inbound:IpPermissions}' --output json
# Target Group Name=skills-lattice-order-tg, Type=INSTANCE, Protocol=HTTP, Port=8080이어야 합니다.
# Target은 skills-lattice-service-ec2 Instance이고 Status=HEALTHY이어야 합니다.
# Listener Name=skills-lattice-http-listener, Protocol=HTTP, Port=80이어야 합니다.
# Service EC2 Security Group의 TCP/8080 Inbound는 VPC Lattice Managed Prefix List로 제한되어야 하며 0.0.0.0/0 허용 시 미충족입니다.


curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/v1/client/orders?id=1001"
# http_code=200이어야 합니다.
# 응답 JSON에 client=ok, service.order_id=1001, service.via=vpc-lattice가 포함되어야 합니다.