set -u
export AWS_PAGER=""
for CMD in aws curl; do
  if ! command -v "$CMD" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $CMD" >&2
    exit 2
  fi
done


aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc,skills-lattice-service-vpc --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,Cidr:CidrBlock,State:State}' --output table
CLIENT_VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
SERVICE_VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
echo "CLIENT_VPC_ID=${CLIENT_VPC_ID}"
echo "SERVICE_INSTANCE_ID=${SERVICE_INSTANCE_ID}"
if [ -n "$CLIENT_VPC_ID" ] && [ "$CLIENT_VPC_ID" != "None" ] && [ -n "$SERVICE_VPC_ID" ] && [ "$SERVICE_VPC_ID" != "None" ]; then
  aws ec2 describe-subnets --region ap-northeast-1 --filters Name=vpc-id,Values="$CLIENT_VPC_ID","$SERVICE_VPC_ID" --query 'Subnets[].{SubnetId:SubnetId,VpcId:VpcId,Cidr:CidrBlock,AZ:AvailabilityZone,MapPublicIp:MapPublicIpOnLaunch,Name:Tags[?Key==`Name`].Value|[0]}' --output table
else
  echo "Client 또는 Service VPC 식별 실패"
fi
# ----------------------------------------------------------------------------------------------------
# |                                               Vpcs                                               |
# +--------------------------------+-------------------+--------------------+------------------------+
# |              Cidr              |       Name        |       State        |         VpcId          |
# +--------------------------------+-------------------+--------------------+------------------------+
# |  10.61.0.0/16                  |  skills-lattice-client-vpc  |  available         |  vpc-0123456789abcdef0 |
# |  10.62.0.0/16                  |  skills-lattice-service-vpc |  available         |  vpc-0123456789abcdef1 |
# +--------------------------------+-------------------+--------------------+------------------------+
# -------------------------------------------------------------------------------------------------------------------------------------------
# |                                                             DescribeSubnets                                                             |
# +-----------------+----------------+--------------+--------------------------------+----------------------------+-------------------------+
# |       AZ        |     Cidr       | MapPublicIp  |             Name               |         SubnetId           |          VpcId          |
# +-----------------+----------------+--------------+--------------------------------+----------------------------+-------------------------+
# |  ap-northeast-1a|  10.62.1.0/24  |  True        |  skills-lattice-service-pub-1  |  subnet-090e130a5d6f3570e  |  vpc-0184e52e8978cb78a  |
# |  ap-northeast-1c|  10.62.2.0/24  |  True        |  skills-lattice-service-pub-2  |  subnet-07677f43dab772a31  |  vpc-0184e52e8978cb78a  |
# |  ap-northeast-1a|  10.61.1.0/24  |  True        |  skills-lattice-client-pub-1   |  subnet-007b44f9b3271f0f1  |  vpc-0570fa619e86272c3  |
# |  ap-northeast-1c|  10.62.20.0/24 |  False       |  skills-lattice-service-priv-2 |  subnet-0932851b56de2d4fb  |  vpc-0184e52e8978cb78a  |
# |  ap-northeast-1c|  10.61.2.0/24  |  True        |  skills-lattice-client-pub-2   |  subnet-0f5c810e1c575fbe0  |  vpc-0570fa619e86272c3  |
# |  ap-northeast-1a|  10.62.10.0/24 |  False       |  skills-lattice-service-priv-1 |  subnet-0bca5c4ac823b159e  |  vpc-0184e52e8978cb78a  |
# +-----------------+----------------+--------------+--------------------------------+----------------------------+-------------------------+


aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,State:State.Name}' --output table
CLIENT_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
SERVICE_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
SERVICE_SG_IDS=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null || true)
echo "CLIENT_IP=${CLIENT_IP}"
echo "SERVICE_INSTANCE_ID=${SERVICE_INSTANCE_ID}"
echo "SERVICE_SG_IDS=${SERVICE_SG_IDS}"
if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}/health"; echo
else
  echo "Client EC2 Public IP 식별 실패"
fi
# --------------------------------------------------------------------------------------------------------------
# |                                              DescribeInstances                                             |
# +---------------------+------------------------------+---------------+---------------+----------+------------+
# |         Id          |            Name              |   PrivateIp   |   PublicIp    |  State   |   Type     |
# +---------------------+------------------------------+---------------+---------------+----------+------------+
# |  i-0dc5370663e71872d|  skills-lattice-client-ec2   |  10.61.1.187  |  54.95.187.27 |  running |  t3.micro  |
# |  i-0afd7e71c5b7283e6|  skills-lattice-service-ec2  |  10.62.10.126 |  None         |  running |  t3.micro  |
# +---------------------+------------------------------+---------------+---------------+----------+------------+
# {"status": "ok", "app": "client"}
# http_code=200


SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].id|[0]' --output text 2>/dev/null || true)
SERVICE_ID=$(aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].id|[0]' --output text 2>/dev/null || true)
TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].id|[0]' --output text 2>/dev/null || true)
echo "SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}"
echo "SERVICE_ID=${SERVICE_ID}"
aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].{Name:name,Id:id,AssociatedVPCs:numberOfAssociatedVPCs,AssociatedServices:numberOfAssociatedServices}' --output table
aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].{Name:name,Id:id,Dns:dnsEntry.domainName,Status:status}' --output table
if [ -n "$SERVICE_NETWORK_ID" ] && [ "$SERVICE_NETWORK_ID" != "None" ]; then
  aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{AssociationId:id,VpcId:vpcId,Status:status}' --output table
  VPC_ASSOCIATION_ID=$(aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[0].id' --output text 2>/dev/null || true)
  if [ -n "$VPC_ASSOCIATION_ID" ] && [ "$VPC_ASSOCIATION_ID" != "None" ]; then
    aws vpc-lattice get-service-network-vpc-association --region ap-northeast-1 --service-network-vpc-association-identifier "$VPC_ASSOCIATION_ID" --query '{AssociationId:id,VpcId:vpcId,Status:status,SecurityGroupIds:securityGroupIds}' --output table
  fi
  aws vpc-lattice list-service-network-service-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{ServiceId:serviceId,Status:status,Dns:dnsEntry.domainName}' --output table
else
  echo "skills-lattice-sn Service Network 식별 실패"
fi
# SERVICE_NETWORK_ID=sn-0123456789abcdef0
# SERVICE_ID=svc-0123456789abcdef0
# ---------------------------------------------------------------------------------------
# |                                 ListServiceNetworks                                 |
# +---------------------+-----------------+------------------------+--------------------+
# | AssociatedServices  | AssociatedVPCs  |          Id            |       Name         |
# +---------------------+-----------------+------------------------+--------------------+
# |  1                  |  2              |  sn-046696de60aafc7d1  |  skills-lattice-sn |
# +---------------------+-----------------+------------------------+--------------------+
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------------
# |                                                                            ListServices                                                                            |
# +------------------------------------------------------------------------------------------------+------------------------+-------------------------------+----------+
# |                                               Dns                                              |          Id            |             Name              | Status   |
# +------------------------------------------------------------------------------------------------+------------------------+-------------------------------+----------+
# |  skills-lattice-order-service-0c53ac9661d653fed.7d67968.vpc-lattice-svcs.ap-northeast-1.on.aws |  svc-0c53ac9661d653fed |  skills-lattice-order-service |  ACTIVE  |
# +------------------------------------------------------------------------------------------------+------------------------+-------------------------------+----------+
# ---------------------------------------------------------------
# |              ListServiceNetworkVpcAssociations              |
# +-------------------------+---------+-------------------------+
# |      AssociationId      | Status  |          VpcId          |
# +-------------------------+---------+-------------------------+
# |  snva-0f9f5b608f8318df0 |  ACTIVE |  vpc-0184e52e8978cb78a  |
# |  snva-0948a739e3e3342ff |  ACTIVE |  vpc-0570fa619e86272c3  |
# +-------------------------+---------+-------------------------+
# -----------------------------------------------------------------------------------
# |                         GetServiceNetworkVpcAssociation                         |
# +-------------------------+-------------------+---------+-------------------------+
# |      AssociationId      | SecurityGroupIds  | Status  |          VpcId          |
# +-------------------------+-------------------+---------+-------------------------+
# |  snva-0f9f5b608f8318df0 |  None             |  ACTIVE |  vpc-0184e52e8978cb78a  |
# +-------------------------+-------------------+---------+-------------------------+
# --------------------------------------------------------------------------------------------------------------------------------------
# |                                                ListServiceNetworkServiceAssociations                                               |
# +------------------------------------------------------------------------------------------------+------------------------+----------+
# |                                               Dns                                              |       ServiceId        | Status   |
# +------------------------------------------------------------------------------------------------+------------------------+----------+
# |  skills-lattice-order-service-0c53ac9661d653fed.7d67968.vpc-lattice-svcs.ap-northeast-1.on.aws |  svc-0c53ac9661d653fed |  ACTIVE  |
# +------------------------------------------------------------------------------------------------+------------------------+----------+



echo "TARGET_GROUP_ID=${TARGET_GROUP_ID}"
aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].{Name:name,Id:id,Type:type,Port:port,Protocol:protocol,Vpc:vpcIdentifier,Status:status}' --output table
if [ -n "$TARGET_GROUP_ID" ] && [ "$TARGET_GROUP_ID" != "None" ]; then
  aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TARGET_GROUP_ID" --query 'items[].{Target:id,Port:port,Status:status}' --output table
else
  echo "skills-lattice-order-tg Target Group 식별 실패"
fi
if [ -n "$SERVICE_ID" ] && [ "$SERVICE_ID" != "None" ]; then
  aws vpc-lattice list-listeners --region ap-northeast-1 --service-identifier "$SERVICE_ID" --query 'items[?name==`skills-lattice-http-listener`].{Name:name,Id:id,Port:port,Protocol:protocol}' --output table
else
  echo "skills-lattice-order-service Service 식별 실패"
fi
if [ -n "$SERVICE_SG_IDS" ] && [ "$SERVICE_SG_IDS" != "None" ]; then
  aws ec2 describe-security-groups --region ap-northeast-1 --group-ids $SERVICE_SG_IDS --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId,Inbound:IpPermissions}' --output json
else
  echo "Service EC2 Security Group 식별 실패"
fi
# TARGET_GROUP_ID=tg-0123456789abcdef0
# ------------------------------------------------------------------------------------------------------------------------
# |                                                   ListTargetGroups                                                   |
# +----------------------+--------------------------+-------+-----------+---------+------------+-------------------------+
# |          Id          |          Name            | Port  | Protocol  | Status  |   Type     |           Vpc           |
# +----------------------+--------------------------+-------+-----------+---------+------------+-------------------------+
# |  tg-00be11beca7a72bee|  skills-lattice-order-tg |  8080 |  HTTP     |  ACTIVE |  INSTANCE  |  vpc-0184e52e8978cb78a  |
# +----------------------+--------------------------+-------+-----------+---------+------------+-------------------------+
# --------------------------------------------
# |                ListTargets               |
# +------+-----------+-----------------------+
# | Port |  Status   |        Target         |
# +------+-----------+-----------------------+
# |  8080|  HEALTHY  |  i-0afd7e71c5b7283e6  |
# +------+-----------+-----------------------+
# ------------------------------------------------------------------------------------
# |                                   ListListeners                                  |
# +-----------------------------+--------------------------------+-------+-----------+
# |             Id              |             Name               | Port  | Protocol  |
# +-----------------------------+--------------------------------+-------+-----------+
# |  listener-056077f8048350b8d |  skills-lattice-http-listener  |  80   |  HTTP     |
# +-----------------------------+--------------------------------+-------+-----------+
# [
#     {
#         "GroupId": "sg-0729460acf603796c",
#         "GroupName": "skills-lattice-service-ec2-sg",
#         "VpcId": "vpc-0184e52e8978cb78a",
#         "Inbound": [
#             {
#                 "IpProtocol": "tcp",
#                 "FromPort": 8080,
#                 "ToPort": 8080,
#                 "UserIdGroupPairs": [],
#                 "IpRanges": [],
#                 "Ipv6Ranges": [],
#                 "PrefixListIds": [
#                     {
#                         "PrefixListId": "pl-0596057d86614af83"
#                     }
#                 ]
#             }
#         ]
#     }
# ]


if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}/v1/client/orders?id=1001"; echo
else
  echo "Client EC2 Public IP 식별 실패"
fi
# {"client": "ok", "service": {"order_id": "1001", "via": "vpc-lattice"}}
# http_code=200






# set -u
# export AWS_PAGER=""
# for CMD in aws curl; do
#   if ! command -v "$CMD" >/dev/null 2>&1; then
#     echo "ERROR: required command not found: $CMD" >&2
#     exit 2
#   fi
# done


# aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc,skills-lattice-service-vpc --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,Cidr:CidrBlock,State:State}' --output table
# CLIENT_VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
# SERVICE_VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
# echo "CLIENT_VPC_ID=${CLIENT_VPC_ID}"
# echo "SERVICE_VPC_ID=${SERVICE_VPC_ID}"
# if [ -n "$CLIENT_VPC_ID" ] && [ "$CLIENT_VPC_ID" != "None" ] && [ -n "$SERVICE_VPC_ID" ] && [ "$SERVICE_VPC_ID" != "None" ]; then
#   aws ec2 describe-subnets --region ap-northeast-1 --filters Name=vpc-id,Values="$CLIENT_VPC_ID","$SERVICE_VPC_ID" --query 'Subnets[].{SubnetId:SubnetId,VpcId:VpcId,Cidr:CidrBlock,AZ:AvailabilityZone,MapPublicIp:MapPublicIpOnLaunch,Name:Tags[?Key==`Name`].Value|[0]}' --output table
# else
#   echo "Client 또는 Service VPC 식별 실패"
# fi
# # Client/Service VPC가 존재하고 CIDR이 각각 10.61.0.0/16, 10.62.0.0/16인지 확인합니다.


# aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,State:State.Name}' --output table
# CLIENT_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
# SERVICE_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
# SERVICE_SG_IDS=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null || true)
# echo "CLIENT_IP=${CLIENT_IP}"
# echo "SERVICE_INSTANCE_ID=${SERVICE_INSTANCE_ID}"
# echo "SERVICE_SG_IDS=${SERVICE_SG_IDS}"
# if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}/health"; echo
# else
#   echo "Client EC2 Public IP 식별 실패"
# fi
# # Client/Service EC2 상태, Public IP 조건, Client /health HTTP 200 응답을 확인합니다.


# SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].id|[0]' --output text 2>/dev/null || true)
# SERVICE_ID=$(aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].id|[0]' --output text 2>/dev/null || true)
# TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].id|[0]' --output text 2>/dev/null || true)
# echo "SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}"
# echo "SERVICE_ID=${SERVICE_ID}"
# aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].{Name:name,Id:id,AssociatedVPCs:numberOfAssociatedVPCs,AssociatedServices:numberOfAssociatedServices}' --output table
# aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].{Name:name,Id:id,Dns:dnsEntry.domainName,Status:status}' --output table
# if [ -n "$SERVICE_NETWORK_ID" ] && [ "$SERVICE_NETWORK_ID" != "None" ]; then
#   aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{AssociationId:id,VpcId:vpcId,Status:status}' --output table
#   VPC_ASSOCIATION_ID=$(aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[0].id' --output text 2>/dev/null || true)
#   if [ -n "$VPC_ASSOCIATION_ID" ] && [ "$VPC_ASSOCIATION_ID" != "None" ]; then
#     aws vpc-lattice get-service-network-vpc-association --region ap-northeast-1 --service-network-vpc-association-identifier "$VPC_ASSOCIATION_ID" --query '{AssociationId:id,VpcId:vpcId,Status:status,SecurityGroupIds:securityGroupIds}' --output table
#   fi
#   aws vpc-lattice list-service-network-service-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{ServiceId:serviceId,Status:status,Dns:dnsEntry.domainName}' --output table
# else
#   echo "skills-lattice-sn Service Network 식별 실패"
# fi
# # Service Network가 존재하고, Service, VPC Association, Service Association이 ACTIVE 상태인지 확인합니다.


# echo "TARGET_GROUP_ID=${TARGET_GROUP_ID}"
# aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].{Name:name,Id:id,Type:type,Port:port,Protocol:protocol,Vpc:vpcIdentifier,Status:status}' --output table
# if [ -n "$TARGET_GROUP_ID" ] && [ "$TARGET_GROUP_ID" != "None" ]; then
#   aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TARGET_GROUP_ID" --query 'items[].{Target:id,Port:port,Status:status}' --output table
# else
#   echo "skills-lattice-order-tg Target Group 식별 실패"
# fi
# if [ -n "$SERVICE_ID" ] && [ "$SERVICE_ID" != "None" ]; then
#   aws vpc-lattice list-listeners --region ap-northeast-1 --service-identifier "$SERVICE_ID" --query 'items[?name==`skills-lattice-http-listener`].{Name:name,Id:id,Port:port,Protocol:protocol}' --output table
# else
#   echo "skills-lattice-order-service Service 식별 실패"
# fi
# if [ -n "$SERVICE_SG_IDS" ] && [ "$SERVICE_SG_IDS" != "None" ]; then
#   aws ec2 describe-security-groups --region ap-northeast-1 --group-ids $SERVICE_SG_IDS --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId,Inbound:IpPermissions}' --output json
# else
#   echo "Service EC2 Security Group 식별 실패"
# fi
# # Target Group, Target, Listener, Service EC2 Security Group 구성이 요구사항과 일치하는지 확인합니다.


# if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}/v1/client/orders?id=1001"; echo
# else
#   echo "Client EC2 Public IP 식별 실패"
# fi
# # Client API가 HTTP 200을 반환하고 order_id=1001, via=vpc-lattice 값이 포함되는지 확인합니다.