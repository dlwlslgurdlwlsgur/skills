TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
VPC_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/ | head -n1 | xargs -I {} curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/{}/vpc-id)
PUB_A=$(aws ec2 describe-subnets --region us-west-2 --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-west-2a" "Name=tag:Name,Values=*pub*,*Pub*,*Public*,*public*" --query "Subnets[0].SubnetId" --output text)
PUB_B=$(aws ec2 describe-subnets --region us-west-2 --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-west-2b" "Name=tag:Name,Values=*pub*,*Pub*,*Public*,*public*" --query "Subnets[0].SubnetId" --output text)
PRIV_A=$(aws ec2 describe-subnets --region us-west-2 --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-west-2a" "Name=tag:Name,Values=*priv*,*Priv*,*Private*,*private*" --query "Subnets[0].SubnetId" --output text)
PRIV_B=$(aws ec2 describe-subnets --region us-west-2 --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-west-2b" "Name=tag:Name,Values=*priv*,*Priv*,*Private*,*private*" --query "Subnets[0].SubnetId" --output text)

# cluster.yaml
cat << EOF > cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: skills-sqs-cluster
  region: us-west-2
  version: "1.35"

iam:
  withOIDC: true

vpc:
  clusterEndpoints:
    publicAccess: true
    privateAccess: true
  subnets:
    public:
      us-west-2a: { id: "$PUB_A" }
      us-west-2b: { id: "$PUB_B" }
    private:
      us-west-2a: { id: "$PRIV_A" }
      us-west-2b: { id: "$PRIV_B" }

fargateProfiles:
  - name: skills-sqs-fp-keda
    selectors:
      - namespace: keda
  - name: skills-sqs-fp-karpenter
    selectors:
      - namespace: karpenter

managedNodeGroups:
  - name: skills-sqs-ng
    labels: { type: app }
    instanceName: skills-sqs-node
    instanceType: t3.medium
    minSize: 1
    maxSize: 2
    desiredCapacity: 1
    privateNetworking: true
    subnets:
     - us-west-2a
     - us-west-2b
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        awsLoadBalancerController: true
        cloudWatch: true
EOF

eksctl create cluster -f cluster.yaml

CLUSTER_NAME="skills-sqs-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root"
aws eks associate-access-policy \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster

echo