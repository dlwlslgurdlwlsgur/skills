## Region
- 오레곤/us-west-2


## configure
```
aws configure
```


## SQS
```
aws sqs create-queue \
  --queue-name skills-sqs-queue \
  --attributes VisibilityTimeout=30 \
  --region us-west-2
```


## install
```
sudo yum install docker -y
sudo usermod -aG docker ec2-user
sudo systemctl enable --now docker
sudo chmod 666 /var/run/docker.sock
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.35.3/2026-04-08/bin/linux/amd64/kubectl
sudo chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin
```


# EKS Cluster
```
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
eksctl craete cluster -f cluster.yaml
```


## root에 EKS 접근 권한
```
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
```


## install Keda, Karpenter
```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod +x get_helm.sh
./get_helm.sh
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# keda
kubectl create ns keda
helm install keda kedacore/keda --namespace keda

# karpenter
export CLUSTER_NAME=skills-sqs-cluster
export AWS_REGION=us-west-2
export KARPENTER_VERSION=1.0.8
curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml -o karpenter-cloudformation.yaml
aws cloudformation deploy \
  --stack-name Karpenter-$CLUSTER_NAME \
  --template-file karpenter-cloudformation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ClusterName=$CLUSTER_NAME \
  --region $AWS_REGION && rm -f karpenter-cloudformation.yaml

aws eks create-addon --cluster-name $CLUSTER_NAME --addon-name eks-pod-identity-agent --region $AWS_REGION || true
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version $KARPENTER_VERSION \
  --namespace karpenter \
  --create-namespace \
  --set clusterName=$CLUSTER_NAME \
  --set awsRegion=$AWS_REGION \
  --set aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-$CLUSTER_NAME \
  --set interruptionQueue=$CLUSTER_NAME \
  --wait
```


## Setting
```
kubectl create ns skills-sqs

# sqs-worker-sa
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --region=$AWS_REGION \
  --namespace=skills-sqs \
  --name=sqs-worker-sa \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  --approve
```


## Manifest
- deployment, keda-vpa 수정
- SQS_URL, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```
kubectl apply -f deployment.yaml
kubectl apply -f keda-vpa.yaml
kubectl apply -f karpenter-config.yaml
```
```
kubectl get pods -n skills-sqs
```


## 확인 (SQS_URL)
```
for i in {1..12}; do aws sqs send-message --queue-url <SQS_URL> --message-body "test-$i" --region us-west-2; done
```
```
kubectl get scaledobject -n skills-sqs
```
```
kubectl get pods -n skills-sqs
```