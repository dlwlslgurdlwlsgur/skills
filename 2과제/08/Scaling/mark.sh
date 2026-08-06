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


aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.[name,status]' --output text | awk '{print "Cluster Name: "$1" | Status: "$2}'
for FP in skills-sqs-fp-keda skills-sqs-fp-karpenter; do
  echo -n "fargate_profile=${FP} -> "
  aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name "$FP" --query 'fargateProfile.[status,selectors[0].namespace]' --output text | awk '{print "Status: "$1" | Namespace: "$2}'
done
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster >/dev/null 2>&1
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o custom-columns='NODE_NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status'
# Cluster Name: skills-sqs-cluster | Status: ACTIVE
# fargate_profile=skills-sqs-fp-keda -> Status: ACTIVE | Namespace: keda
# fargate_profile=skills-sqs-fp-karpenter -> Status: ACTIVE | Namespace: karpenter
# NODE_NAME                                        STATUS
# fargate-ip-10-0-x-x.us-west-2.compute.internal   True
# fargate-ip-10-0-y-y.us-west-2.compute.internal   True


QUEUE_URL=$(aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue --query QueueUrl --output text 2>/dev/null || true)
echo "QUEUE_URL=${QUEUE_URL}"
if [ -n "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
  aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names VisibilityTimeout --query 'Attributes.VisibilityTimeout' --output text | awk '{print "VisibilityTimeout: "$1}'
else
  echo "skills-sqs-queue Queue URL 식별 실패"
fi
for X in "keda keda-operator" "karpenter karpenter" "skills-sqs sqs-worker-sa"; do
  set -- $X
  echo -n "$1/$2 role="
  kubectl get serviceaccount "$2" -n "$1" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
  echo
done
# QUEUE_URL=https://sqs.us-west-2.amazonaws.com/123456789012/skills-sqs-queue
# VisibilityTimeout: 30
# keda/keda-operator role=arn:aws:iam::123456789012:role/...
# karpenter/karpenter role=arn:aws:iam::123456789012:role/...
# skills-sqs/sqs-worker-sa role=arn:aws:iam::123456789012:role/...


kubectl get pod -n keda -o custom-columns='POD_NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName'
kubectl get pod -n karpenter -o custom-columns='POD_NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName'
# POD_NAME                              STATUS    NODE
# keda-operator-xxxxxxxxxx-xxxxx        Running   fargate-ip-10-0-x-x.us-west-2.compute.internal
# POD_NAME                              STATUS    NODE
# karpenter-xxxxxxxxxx-xxxxx            Running   fargate-ip-10-0-y-y.us-west-2.compute.internal


kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='SA={.spec.template.spec.serviceAccountName}{"\n"}NodeSelector={.spec.template.spec.nodeSelector}{"\n"}Env={.spec.template.spec.containers[0].env[*].name}{"\n"}'
kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o jsonpath='MinMax={.spec.minReplicaCount}/{.spec.maxReplicaCount} | Trigger={.spec.triggers[0].type} | Q_Length={.spec.triggers[0].metadata.queueLength}{"\n"}'
kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o jsonpath='Provider={.spec.podIdentity.provider}{"\n"}'
# SA=sqs-worker-sa
# NodeSelector={"karpenter.sh/nodepool":"skills-sqs-nodepool","skills-nodepool":"event-worker"}
# Env=SQS_QUEUE_URL AWS_REGION PROCESSING_SECONDS
# MinMax=0/6 | Trigger=aws-sqs-queue | Q_Length=2
# Provider=aws-eks


kubectl get nodepool skills-sqs-nodepool -o jsonpath='NodeClassRef={.spec.template.spec.nodeClassRef.name} | Label={.spec.template.metadata.labels.skills-nodepool} | Consolidation={.spec.disruption.consolidationPolicy}{"\n"}'
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o custom-columns='NODE_NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status'
kubectl get pods -n skills-sqs -l app=sqs-worker -o custom-columns='POD_NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName'
# NodeClassRef=skills-sqs-nodeclass | Label=event-worker | Consolidation=WhenEmptyOrUnderutilized
# No resources found
# No resources found in skills-sqs namespace.


if [ -z "$QUEUE_URL" ] || [ "$QUEUE_URL" = "None" ]; then
  echo "skills-sqs-queue Queue URL 식별 실패"
else
  SENT=0
  RUN_ID="skills-scale-out-$(date +%s)"
  for I in $(seq 1 12); do
    aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "${RUN_ID}-${I}" >/dev/null 2>&1 && SENT=$((SENT + 1))
  done
  echo "sent=${SENT}"
  for T in 60 120 180; do
    sleep 60
    echo "after_${T}s"
    aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --query 'Attributes.[ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible]' --output text | awk '{print "Queue_Messages: "$1" | In_Flight(NotVisible): "$2}'
    kubectl get deployment sqs-worker -n skills-sqs -o custom-columns='DEPLOYMENT:.metadata.name,READY_REPLICAS:.status.readyReplicas'
    kubectl get pods -n skills-sqs -l app=sqs-worker -o custom-columns='POD_NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName'
    kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o custom-columns='EC2_NODE:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status'
  done
fi
# sent=12
# after_60s (또는 after_120s 진행 시점에)
# Queue_Messages: 8 | In_Flight(NotVisible): 4 (처리되면서 숫자 변동)
# DEPLOYMENT   READY_REPLICAS
# sqs-worker   6
# POD_NAME                     STATUS    NODE
# sqs-worker-xxxxxxxxx-xxxxx   Running   ip-10-0-z-z.us-west-2.compute.internal
# sqs-worker-xxxxxxxxx-xxxxx   Running   ip-10-0-z-z.us-west-2.compute.internal
# ... (최대 6개)
# EC2_NODE                             STATUS
# ip-10-0-z-z.us-west-2.compute...     True
#
# after_180s (최종)
# Queue_Messages: 0 | In_Flight(NotVisible): 0







# set -u
# export AWS_PAGER=""
# OUT_TXT="asgmt2_module4_check_result.txt"
# exec > >(tee "$OUT_TXT") 2>&1
# if ! command -v aws >/dev/null 2>&1; then
#   echo "ERROR: required command not found: aws" >&2
#   exit 2
# fi
# if ! command -v kubectl >/dev/null 2>&1; then
#   echo "ERROR: required command not found: kubectl" >&2
#   echo "CloudShell 또는 채점 환경에 kubectl을 준비한 뒤 다시 실행하십시오." >&2
#   exit 2
# fi


# aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,Version:version,Role:roleArn,Vpc:vpcConfig}' --output table
# for FP in skills-sqs-fp-keda skills-sqs-fp-karpenter; do
#   echo "fargate_profile=${FP}"
#   aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name "$FP" --query 'fargateProfile.{Name:fargateProfileName,Status:status,Selectors:selectors,Subnets:subnets}' --output table
# done
# aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
# kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o wide
# # EKS Cluster와 Fargate Profile 2개가 ACTIVE이며 CloudShell에서 kubectl 접근 가능한지 확인합니다.


# QUEUE_URL=$(aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue --query QueueUrl --output text 2>/dev/null || true)
# echo "QUEUE_URL=${QUEUE_URL}"
# if [ -n "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
#   aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names QueueArn VisibilityTimeout --output table
# else
#   echo "skills-sqs-queue Queue URL 식별 실패"
# fi
# for X in "keda keda-operator" "karpenter karpenter" "skills-sqs sqs-worker-sa"; do
#   set -- $X
#   echo -n "$1/$2 role="
#   kubectl get serviceaccount "$2" -n "$1" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
#   echo
# done
# # SQS Queue와 ServiceAccount IRSA annotation이 요구사항과 일치하는지 확인합니다.


# kubectl get deployment,pod -n keda -o wide
# kubectl get deployment,pod -n karpenter -o wide
# # KEDA/Karpenter Controller Pod가 Running 상태이며 Fargate Node에서 실행되는지 확인합니다.


# kubectl get deployment sqs-worker -n skills-sqs -o wide
# kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
# kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o yaml
# kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o yaml
# # Worker Deployment, 환경변수, Node Selector, ScaledObject, TriggerAuthentication 구성이 요구사항과 일치하는지 확인합니다.


# kubectl get nodepool skills-sqs-nodepool -o yaml
# kubectl get ec2nodeclass skills-sqs-nodeclass -o yaml
# kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
# kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
# # NodePool, EC2NodeClass, Worker EC2 Node, Worker Pod 배치가 요구사항과 일치하는지 확인합니다.


# if [ -z "$QUEUE_URL" ] || [ "$QUEUE_URL" = "None" ]; then
#   echo "skills-sqs-queue Queue URL 식별 실패"
# else
#   SENT=0
#   RUN_ID="skills-scale-out-$(date +%s)"
#   for I in $(seq 1 12); do
#     aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "${RUN_ID}-${I}" >/dev/null 2>&1 && SENT=$((SENT + 1))
#   done
#   echo "sent=${SENT}"
#   for T in 60 120 180; do
#     sleep 60
#     echo "after_${T}s"
#     aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --output table
#     kubectl get deployment sqs-worker -n skills-sqs
#     kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
#     kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
#     kubectl get nodeclaims -l karpenter.sh/nodepool=skills-sqs-nodepool
#   done
# fi
# # 180초 이내 Worker Pod와 Karpenter EC2 Worker Node가 증가하고 Queue depth가 감소하는지 확인합니다.