REGION="ap-northeast-1"
CLIENT_VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=skills-lattice-client-vpc" --query "Vpcs[0].VpcId" --output text)
SERVICE_VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=skills-lattice-service-vpc" --query "Vpcs[0].VpcId" --output text)

CLIENT_SG_ID=$(aws ec2 create-security-group --region $REGION \
    --group-name "skills-lattice-client-assoc-sg" \
    --description "Security group for Lattice Client VPC association" \
    --vpc-id $CLIENT_VPC_ID \
    --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $CLIENT_SG_ID \
    --protocol tcp --port 80 \
    --cidr 10.61.0.0/16

SN_ID=$(aws vpc-lattice create-service-network --region $REGION \
    --name skills-lattice-sn \
    --tags "Name=skills-lattice-sn" \
    --query "id" --output text)

aws vpc-lattice create-service-network-vpc-association --region $REGION \
    --service-network-identifier $SN_ID \
    --vpc-identifier $CLIENT_VPC_ID \
    --security-group-ids $CLIENT_SG_ID \
    --tags "Name=skills-lattice-client-vpc-assoc"

sleep 3

aws vpc-lattice create-service-network-vpc-association --region $REGION \
    --service-network-identifier $SN_ID \
    --vpc-identifier $SERVICE_VPC_ID \
    --tags "Name=skills-lattice-service-vpc-assoc"

TG_CONFIG="{\"port\":8080,\"protocol\":\"HTTP\",\"vpcIdentifier\":\"$SERVICE_VPC_ID\",\"healthCheck\":{\"enabled\":true,\"path\":\"/health\",\"protocol\":\"HTTP\"}}"

TG_ID=$(aws vpc-lattice create-target-group --region $REGION \
    --name skills-lattice-order-tg \
    --type INSTANCE \
    --config "$TG_CONFIG" \
    --tags "Name=skills-lattice-order-tg" \
    --query "id" --output text)

SERVICE_ID=$(aws vpc-lattice create-service --region $REGION \
    --name skills-lattice-order-service \
    --tags "Name=skills-lattice-order-service" \
    --query "id" --output text)

sleep 10

ASSOC_ID=$(aws vpc-lattice create-service-network-service-association --region $REGION \
    --service-network-identifier $SN_ID \
    --service-identifier $SERVICE_ID \
    --tags "Name=skills-lattice-order-service-assoc" \
    --query "id" --output text)

DEFAULT_ACTION="{\"forward\":{\"targetGroups\":[{\"targetGroupIdentifier\":\"$TG_ID\",\"weight\":100}]}}"
LISTENER_ID=$(aws vpc-lattice create-listener --region $REGION \
    --service-identifier $SERVICE_ID \
    --name skills-lattice-http-listener \
    --protocol HTTP \
    --port 80 \
    --default-action "$DEFAULT_ACTION" \
    --tags "Name=skills-lattice-http-listener" \
    --query "id" --output text)

echo