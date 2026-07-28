ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-west-2"
IMAGE_URL="${ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/skills-sqs-ecr:latest"
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
          value: "us-west-2"
        - name: PROCESSING_SECONDS
          value: "5"
      nodeSelector:
        karpenter.sh/nodepool: skills-sqs-nodepool
        skills-nodepool: event-worker
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
  role: KarpenterNodeRole-skills-sqs-cluster
  subnetSelectorTerms:
    - tags:
        kubernetes.io/cluster/skills-sqs-cluster: "*"
  securityGroupSelectorTerms:
    - tags:
        kubernetes.io/cluster/skills-sqs-cluster: owned
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
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
EOF

cat <<EOF > keda-vpa.yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: sqs-worker-trigger-auth
  namespace: skills-sqs
spec:
  podIdentity:
    provider: aws-eks
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
      awsRegion: "us-west-2"
      identityOwner: operator
EOF

kubectl apply -f deployment.yaml
kubectl apply -f keda-vpa.yaml
kubectl apply -f karpenter-config.yaml
echo