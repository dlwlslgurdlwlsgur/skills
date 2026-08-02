source kubectl-connect skm-eks-cluster
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
rm -rf ~/.aws
aws sts get-caller-identity | jq .Account


aws sqs get-queue-url --queue-name skm-order-queue --region ap-northeast-2 | jq .QueueUrl
# "https://sqs.ap-northeast-2.amazonaws.com/123456787890/skm-order-queue"


aws eks describe-cluster --name skm-eks-cluster --query 'cluster.[name, version, status]' --output text --region ap-northeast-2
aws eks describe-nodegroup --cluster-name skm-eks-cluster --nodegroup-name skm-cluster-addon-ng --query 'nodegroup.[instanceTypes[0], scalingConfig.minSize, scalingConfig.desiredSize, scalingConfig.maxSize]' --output text --region ap-northeast-2
aws ec2 describe-instances --filters "Name=tag:Name,Values=skm-cluster-addon-ng-node" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].Tags[?Key=='Name'].Value | [0]" --output text --region ap-northeast-2
# skm-eks-cluster 1.35 ACTIVE
# t3.medium 1 1 1
# skm-cluster-addon-ng-node


kubectl get pod -n skillsmkt -l app=order-processor -o jsonpath='{.items[0].spec.nodeName}' | xargs -I {} kubectl get node {} -L karpenter.sh/nodepool --no-headers
kubectl get deploy order-processor -n skillsmkt -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].ports[0].containerPort} {.spec.template.spec.containers[0].resources.requests.cpu} {.spec.template.spec.containers[0].resources.requests.memory}{"\n"}'
kubectl get deploy order-processor -n skillsmkt -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | sort
# ip-192-168-133-173.ap-northeast-2.compute.internal   Ready   <none>   57m   v1.35.5-eks-3385e9b   skm-app-nodepool
# 1 8080 500m 512Mi
# AWS_REGION=ap-northeast-2
# PROCESSING_TIME=3
# SQS_QUEUE_URL=https://sqs.ap-northeast-2.amazonaws.com/123456787890/skm-order-queue


kubectl get pod -n keda -l app.kubernetes.io/name=keda-operator -o name
kubectl get scaledobject order-scaler -n skillsmkt -o jsonpath='{.spec.minReplicaCount} {.spec.maxReplicaCount} {.spec.triggers[0].type} {.spec.triggers[0].metadata.queueLength}{"\n"}'
# pod/keda-operator-55db59458d-tp9bj
# 1 5 aws-sqs-queue 5


kubectl get pod -n kube-system -l app.kubernetes.io/name=karpenter -o name
kubectl get nodepool skm-app-nodepool -o jsonpath='{.spec.disruption.consolidationPolicy} {.spec.disruption.consolidateAfter}{"\n"}'
kubectl get nodepool skm-app-nodepool -o json | jq -r '.spec.template.spec.requirements[] | select(.key == "node.kubernetes.io/instance-type") | .values | sort | join(",")'
kubectl get nodepool skm-app-nodepool -o json | jq '.spec.template.spec.taints | length'
kubectl get ec2nodeclass skm-app-nodeclass -o name
# pod/karpenter-8c66dbc4-r4fnp
# WhenEmptyOrUnderutilized 60s
# t3.medium,t3.small
# 1 <- 1 이상이면 정답 인정
# ec2nodeclass.karpenter.k8s.aws/skm-app-nodeclass


for b in $(seq 1 10); do
  E=$(for i in $(seq 1 10); do printf '{"Id":"%d-%d","MessageBody":"order"},' "$b" "$i"; done | sed 's/,$//')
  aws sqs send-message-batch --queue-url "$(aws sqs get-queue-url --queue-name skm-order-queue --region ap-northeast-2 --query QueueUrl --output text)" --entries "[$E]" --region ap-northeast-2 > /dev/null; done

POD_PEAK=0; NODE_PEAK=0
for i in $(seq 1 24); do
  P=$(kubectl get deploy order-processor -n skillsmkt -o jsonpath='{.status.readyReplicas}' 2>/dev/null); P=${P:-0}
  N=$(kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$P" -gt "$POD_PEAK" ] && POD_PEAK=$P
  [ "$N" -gt "$NODE_PEAK" ] && NODE_PEAK=$N
  sleep 5
done
echo "Max Ready Pods $POD_PEAK"
echo "Max App Nodes $NODE_PEAK"
# Max Ready Pods 5 <- 5 이상이면 정답
# Max App Nodes 2 <- 2 이상이면 정답


aws sqs purge-queue --queue-url "$(aws sqs get-queue-url --queue-name skm-order-queue --region ap-northeast-2 --query QueueUrl --output text)" --region ap-northeast-2 2>/dev/null
for i in $(seq 1 30); do
  P=$(kubectl get deploy order-processor -n skillsmkt -o jsonpath='{.status.replicas}' 2>/dev/null); P=${P:-0}
  N=$(kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$P" = "1" ] && [ "$N" = "1" ]; then RESULT=ok; break; fi
  sleep 5
done
echo "Final Pods $P"
echo "Final Nodes $N"
# Final Pods 1
# Final Nodes 1