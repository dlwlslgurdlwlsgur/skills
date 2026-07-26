curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod +x get_helm.sh
./get_helm.sh

# keda
kubectl create ns keda 2>/dev/null || true
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm upgrade --install keda kedacore/keda --namespace keda

# karpenter
export CLUSTER_NAME=skills-sqs-cluster
export AWS_REGION=us-west-2
export KARPENTER_VERSION=1.0.8
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml -o karpenter-cloudformation.yaml
aws cloudformation deploy \
  --stack-name Karpenter-$CLUSTER_NAME \
  --template-file karpenter-cloudformation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ClusterName=$CLUSTER_NAME \
  --region $AWS_REGION && rm -f karpenter-cloudformation.yaml

aws eks create-addon --cluster-name $CLUSTER_NAME --addon-name eks-pod-identity-agent --region $AWS_REGION || true

KARPENTER_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name Karpenter-$CLUSTER_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`KarpenterControllerRoleArn`].OutputValue' --output text 2>/dev/null || true)

if [ "$KARPENTER_ROLE_ARN" == "None" ] || [ -z "$KARPENTER_ROLE_ARN" ]; then
  KARPENTER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}"
fi

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version $KARPENTER_VERSION \
  --namespace karpenter \
  --create-namespace \
  --set settings.clusterName=$CLUSTER_NAME \
  --set settings.clusterEndpoint=$(aws eks describe-cluster --region $AWS_REGION --name $CLUSTER_NAME --query "cluster.endpoint" --output text) \
  --set settings.interruptionQueue=$CLUSTER_NAME \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$KARPENTER_ROLE_ARN \
  --wait

# sqs-worker-sa
kubectl create ns skills-sqs 2>/dev/null || true
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --region=$AWS_REGION \
  --namespace=skills-sqs \
  --name=sqs-worker-sa \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  --override-existing-serviceaccounts \
  --approve

ECR_REPO_NAME="skills-sqs-ecr"
IMAGE_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest"
SQS_URL=$(aws sqs get-queue-url --queue-name skills-sqs-queue --region $AWS_REGION --query "QueueUrl" --output text)

cat <<EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sqs-worker
  namespace: skills-sqs
  labels:
    app: sqs-worker
spec:
  replicas: 0
  selector:
    matchLabels:
      app: sqs-worker
  template:
    metadata:
      labels:
        app: sqs-worker
    spec:
      serviceAccountName: sqs-worker-sa
      containers:
      - name: worker
        image: $IMAGE_URL
        env:
        - name: SQS_QUEUE_URL
          value: "$SQS_URL"
        - name: AWS_REGION
          value: "$AWS_REGION"
        - name: PROCESSING_SECONDS
          value: "5"
      nodeSelector:
        karpenter.sh/nodepool: skills-sqs-nodepool
        skills-nodepool: event-worker
EOF

cat <<EOF > keda-vpa.yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: sqs-worker-trigger-auth
  namespace: skills-sqs
spec:
  podIdentity:
    provider: aws
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-worker-scaledobject
  namespace: skills-sqs
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sqs-worker
  minReplicaCount: 0
  maxReplicaCount: 6
  pollingInterval: 15
  cooldownPeriod: 30
  triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: sqs-worker-trigger-auth
    metadata:
      queueURL: "$SQS_URL"
      queueLength: "2"
      awsRegion: "$AWS_REGION"
      identityOwner: operator
EOF

cat <<EOF > karpenter-config.yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: skills-sqs-nodeclass
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest
  role: KarpenterNodeRole-$CLUSTER_NAME
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "$CLUSTER_NAME"
  securityGroupSelectorTerms:
    - tags:
        kubernetes.io/cluster/$CLUSTER_NAME: "owned"
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: skills-sqs-nodepool
spec:
  template:
    metadata:
      labels:
        skills-nodepool: event-worker
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: skills-sqs-nodeclass
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
EOF

kubectl apply -f deployment.yaml
kubectl apply -f keda-vpa.yaml
kubectl apply -f karpenter-config.yaml

echo