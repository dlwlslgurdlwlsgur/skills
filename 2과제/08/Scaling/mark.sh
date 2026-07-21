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


echo "cluster: $(aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.status' --output text)"
for FP in skills-sqs-fp-keda skills-sqs-fp-karpenter; do
  status=$(aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name "$FP" --query 'fargateProfile.status' --output text)
  echo "fargate_profile-${FP}: ${status}"
done
echo "fargate_nodes_count: $(kubectl get nodes -l eks.amazonaws.com/compute-type=fargate --no-headers | wc -l)"
# cluster: ACTIVE
# fargate_profile-skills-sqs-fp-keda: ACTIVE
# fargate_profile-skills-sqs-fp-karpenter: ACTIVE
# fargate_nodes_count: 2


QUEUE_URL=$(aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue --query QueueUrl --output text 2>/dev/null)
if [ -n "$QUEUE_URL" ]; then
  QUEUE_ARN=$(aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
  V_TIMEOUT=$(aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names VisibilityTimeout --query 'Attributes.VisibilityTimeout' --output text)
  echo "sqs_queue_url: $QUEUE_URL"
  echo "sqs_queue_arn: $QUEUE_ARN"
  echo "sqs_visibility_timeout: ${V_TIMEOUT}s"
else
  echo "sqs_queue: NOT_FOUND"
fi
for X in "keda keda-operator" "karpenter karpenter" "skills-sqs sqs-worker-sa"; do
  set -- $X
  role=$(kubectl get serviceaccount "$2" -n "$1" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
  echo "${1}/${2}_role: ${role:-NOT_BOUND}"
done
# sqs_queue_url: https://sqs.us-west-2.amazonaws.com/1234/skills-sqs-queue
# sqs_queue_arn: arn:aws:sqs:us-west-2:1234/skills-sqs-queue
# sqs_visibility_timeout: 30s
# keda/keda-operator_role: arn:aws:iam::1234:role/eksctl-skills-sqs-cluster-addon-iamserviceac-Role
# karpenter/karpenter_role: arn:aws:iam::1234:role/eksctl-skills-sqs-cluster-addon-iamserviceac-Role
# skills-sqs/sqs-worker-sa_role: arn:aws:iam::1234:role/eksctl-skills-sqs-cluster-addon-iamserviceacc-Role1-Z1cfHjJ1EwoZ


echo "=== KEDA Controller ==="
kubectl get pod -n keda -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\tNODE: "}{.spec.nodeName}{"\n"}{end}'
echo -e "\n=== Karpenter Controller ==="
kubectl get pod -n karpenter -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\tNODE: "}{.spec.nodeName}{"\n"}{end}'
# keda/deployment.apps/keda-admission-webhooks          1/1 Running   NODE: fargate-10.0.x.x
# keda/deployment.apps/keda-operator                    1/1 Running   NODE: fargate-10.0.x.y
# keda/deployment.apps/keda-operator-metrics-apiserver  1/1 Running   NODE: fargate-10.0.x.z

# karpenter/deployment.apps/karpenter                  1/1 Running   NODE: fargate-10.0.y.x


kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
# serviceAccountName=sqs-worker-sa
# selector={"app":"sqs-worker"}
# podLabels={"app":"sqs-worker"}
# nodeSelector={"karpenter.sh/nodepool":"skills-sqs-nodepool","skills-nodepool":"event-worker"}
# env=[{"name":"SQS_QUEUE_URL","value":"https://sqs.us-west-2.amazonaws.com/..."},{"name":"AWS_REGION","value":"us-west-2"},{"name":"PROCESSING_SECONDS","value":"5"}]
# image=[본인의 ECR 리포지토리 주소/이미지명:태그]


kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
# NAME                                           STATUS   ROLES    VERSION   INTERNAL-IP
# ip-10-0-x-x.us-west-2.compute.internal         Ready    <none>   v1.30.x   10.0.x.x

# NAME                          READY   STATUS    RESTARTS   NODE
# sqs-worker-5458757c5f-ccdlh   1/1     Running   0          ip-10-0-x-x.us-west-2.compute.internal
# sqs-worker-5458757c5f-qnh52   1/1     Running   0          ip-10-0-x-x.us-west-2.compute.internal


echo "[4-6] SQS 기반 Scale Out 및 처리 기능 검증 (1.25점)"
echo "주의: 본 항목은 채점기준표에 따라 SQS 메시지 12개를 생성합니다."
if [ -z "$QUEUE_URL" ] || [ "$QUEUE_URL" = "None" ]; then
  echo "skills-sqs-queue Queue URL 식별 실패"
else
  SENT=0
  RUN_ID="skills-scale-out-$(date +%s)"
  for I in $(seq 1 12); do
    aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "${RUN_ID}-${I}" >/dev/null 2>&1 && SENT=$((SENT + 1))
  done
  echo "sent=${SENT}"
  # 180초 루프 모니터링 수행
  for T in 60 120 180; do
    sleep 60
    echo "after_${T}s"
    aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --output table
    kubectl get deployment sqs-worker -n skills-sqs
    kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
    kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
    kubectl get nodeclaims -l karpenter.sh/nodepool=skills-sqs-nodepool
  done
  # 180초 루프가 끝난 시점의 최종 상태 수집 및 자동 판정
  check_pod_count=$(kubectl get pods -n skills-sqs -l app=sqs-worker --no-headers 2>/dev/null | wc -l)
  check_pod_running=$(kubectl get pods -n skills-sqs -l app=sqs-worker --no-headers 2>/dev/null | grep -c "Running")
  check_ec2_node=$(kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker --no-headers 2>/dev/null | wc -l)

  if [ "$check_pod_count" -ge 1 ] && [ "$check_pod_running" -ge 1 ] && [ "$check_ec2_node" -ge 1 ]; then
    echo "true"
  else
    echo "false"
  fi
fi
# sent=12
# true