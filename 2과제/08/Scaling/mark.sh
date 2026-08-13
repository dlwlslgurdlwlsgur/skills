set -u
export AWS_PAGER=""
OUT_TXT="asgmt2_module4_check_result.txt"
exec > >(tee "$OUT_TXT") 2>&1
if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: required command not found: aws" >&2
  exit 2
fi
if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: required command not found: kubectl" >&2
  echo "CloudShell 또는 채점 환경에 kubectl을 준비한 뒤 다시 실행하십시오." >&2
  exit 2
fi


aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,Version:version,Role:roleArn,Vpc:resourcesVpcConfig.vpcId,Subnets:resourcesVpcConfig.subnetIds}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-keda --query 'fargateProfile.{Name:fargateProfileName,Status:status,Selectors:selectors,Subnets:subnets}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-karpenter --query 'fargateProfile.{Name:fargateProfileName,Status:status,Selectors:selectors,Subnets:subnets}' --output table
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o wide
# Cluster Name=skills-sqs-cluster, Status=ACTIVE, Endpoint 출력, Vpc 및 Subnets 출력이 있어야 합니다.
# Fargate Profile skills-sqs-fp-keda와 skills-sqs-fp-karpenter가 Status=ACTIVE이어야 합니다.
# skills-sqs-fp-keda Selector namespace는 keda, skills-sqs-fp-karpenter Selector namespace는 karpenter이어야 합니다.
# CloudShell에서 kubectl 접근이 가능하고 Fargate Node가 출력되어야 합니다.


QUEUE_URL=$(aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue --query QueueUrl --output text 2>/dev/null || true)
echo "QUEUE_URL=${QUEUE_URL}"
if [ -n "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
  aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names QueueArn VisibilityTimeout --output table
else
  echo "skills-sqs-queue Queue URL 식별 실패"
fi
kubectl get serviceaccount keda-operator -n keda -o jsonpath='keda/keda-operator role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
kubectl get serviceaccount karpenter -n karpenter -o jsonpath='karpenter/karpenter role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
kubectl get serviceaccount sqs-worker-sa -n skills-sqs -o jsonpath='skills-sqs/sqs-worker-sa role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
# Queue URL이 출력되어야 합니다.
# QueueArn이 출력되고 VisibilityTimeout>=30이어야 합니다.
# keda/keda-operator, karpenter/karpenter, skills-sqs/sqs-worker-sa의 role-arn annotation이 비어 있지 않아야 합니다.


kubectl get deployment keda-operator -n keda -o json | jq '{name:.metadata.name, availableReplicas:(.status.availableReplicas // 0), readyReplicas:(.status.readyReplicas // 0)}'
kubectl get pods -n keda -o json | jq '[.items[] | select(.metadata.name | test("^keda-operator-")) | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
kubectl get deployment karpenter -n karpenter -o json | jq '{name:.metadata.name, availableReplicas:(.status.availableReplicas // 0), readyReplicas:(.status.readyReplicas // 0)}'
kubectl get pods -n karpenter -o json | jq '[.items[] | select(.metadata.name | test("^karpenter-")) | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
# keda-operator Deployment의 availableReplicas가 1 이상이어야 합니다.
# karpenter Deployment의 availableReplicas가 1 이상이어야 합니다.
# 각 Deployment Pod의 phase는 Running이어야 합니다.
# 해당 Pod들은 Fargate Node에서 실행되어야 합니다.


kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='name={.metadata.name}{"\n"}serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, scaleTargetRef:.spec.scaleTargetRef, minReplicaCount:.spec.minReplicaCount, maxReplicaCount:.spec.maxReplicaCount, pollingInterval:.spec.pollingInterval, cooldownPeriod:.spec.cooldownPeriod, triggers:.spec.triggers}'
kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, podIdentity:.spec.podIdentity}'
# Deployment name=sqs-worker, serviceAccountName=sqs-worker-sa이어야 합니다.
# selector/podLabels에 app=sqs-worker가 포함되어야 합니다.
# nodeSelector에 karpenter.sh/nodepool=skills-sqs-nodepool, skills-nodepool=event-worker가 포함되어야 합니다.
# env에 SQS_QUEUE_URL, AWS_REGION, PROCESSING_SECONDS가 있어야 합니다.
# ScaledObject name=sqs-worker-scaledobject, scaleTargetRef.name=sqs-worker, minReplicaCount=0, maxReplicaCount=6, pollingInterval<=15, cooldownPeriod<=30이어야 합니다.
# Trigger type은 aws-sqs-queue이고 queueLength=2이어야 합니다.
# TriggerAuthentication name=sqs-worker-trigger-auth, namespace=skills-sqs가 출력되어야 합니다.
# podIdentity.provider=aws-eks이어야 합니다.


kubectl get nodepool skills-sqs-nodepool -o json | jq '{name:.metadata.name, labels:.spec.template.metadata.labels, nodeClassRef:.spec.template.spec.nodeClassRef, requirements:.spec.template.spec.requirements, consolidationPolicy:.spec.disruption.consolidationPolicy}'
kubectl get ec2nodeclass skills-sqs-nodeclass -o json | jq '{name:.metadata.name, role:.spec.role, instanceProfile:.spec.instanceProfile, subnetSelectorTerms:.spec.subnetSelectorTerms, securityGroupSelectorTerms:.spec.securityGroupSelectorTerms, amiFamily:.spec.amiFamily}'
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o json | jq '[.items[] | {name:.metadata.name, nodepool:.metadata.labels["karpenter.sh/nodepool"], skillsNodepool:.metadata.labels["skills-nodepool"], instanceType:.metadata.labels["node.kubernetes.io/instance-type"], ready:([.status.conditions[] | select(.type=="Ready")][0].status)}]'
kubectl get pods -n skills-sqs -l app=sqs-worker -o json | jq '[.items[] | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
# NodePool name=skills-sqs-nodepool이어야 합니다.
# NodePool labels에 skills-nodepool=event-worker가 있어야 합니다.
# NodePool nodeClassRef.name=skills-sqs-nodeclass이어야 합니다.
# NodePool consolidationPolicy가 비어 있지 않아야 합니다.
# EC2NodeClass name=skills-sqs-nodeclass이어야 하며 role 또는 instanceProfile이 출력되어야 합니다.
# Worker EC2 Node는 nodepool=skills-sqs-nodepool, skillsNodepool=event-worker, ready=True가 출력되어야 합니다.
# Worker Pod는 phase와 node가 출력되어야 합니다.
# 단, Worker Deployment 및 KEDA 설정의 minReplicaCount=0 특성상 채점 시점에 Worker EC2 Node 또는 Worker Pod가 없을 수 있으므로, 이 경우 동일 과제의 4-6 SQS 기반 Scale Out 실행 결과에서 확인된 Worker EC2 Node 및 Worker Pod 출력을 포함하여 판정할 수 있습니다.


if [ -z "$QUEUE_URL" ] || [ "$QUEUE_URL" = "None" ]; then
  echo "skills-sqs-queue Queue URL 식별 실패"
else
  SENT=0
  for I in $(seq 1 12); do
    aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "judge-$I" >/dev/null 2>&1 && SENT=$((SENT + 1))
  done
  echo "sent=${SENT}"
  for T in 60 120 180; do
    sleep 60
    echo "after_${T}s"
    aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --output table
    kubectl get deployment sqs-worker -n skills-sqs
    kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
    kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
    kubectl get nodeclaims -l karpenter.sh/nodepool=skills-sqs-nodepool
  done
fi
# SQS 메시지 발행 수가 12개이어야 합니다.
# 마지막 메시지 발행 완료 후 180초 이내 sqs-worker Pod가 증가해야 합니다.
# 180초 이내 Karpenter EC2 Worker Node가 1개 이상 Ready 상태로 확인되어야 합니다.
# SQS ApproximateNumberOfMessages가 감소해야 합니다.
# ApproximateNumberOfMessagesNotVisible은 Worker가 처리 중인 메시지이므로, 대기 메시지가 감소하고 Pod가 처리 중이면 실패로 보지 않습니다.
# Scale In 완료 시간은 채점하지 않습니다.
# 본 항목은 SQS 메시지를 생성하므로 4모듈의 마지막 채점 항목으로 수행합니다.