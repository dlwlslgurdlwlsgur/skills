## Region
- 오레곤/us-west-2

<br> 

## shell
- 01-vpc.sh
- 02-cluster.sh


## ECR
- 03-ecr.sh
```bash
chmod 777 worker.py
cat <<EOF >> Dockerfile
FROM python:3.9-slim
RUN pip install boto3
COPY worker.py /app/worker.py
WORKDIR /app
CMD ["python", "worker.py"]
EOF
```
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com
docker build -t skills-sqs-ecr .
docker tag skills-sqs-ecr:latest $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/skills-sqs-ecr:latest
docker push $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/skills-sqs-ecr:latest
```

<br> 

## shell
- 04-manifest.sh

<br> 

## test
```bash
SQS_URL=$(aws sqs get-queue-url --queue-name skills-sqs-queue --region us-west-2 --query "QueueUrl" --output text)
for i in {1..12}; do aws sqs send-message --queue-url $SQS_URL --message-body "test-$i" --region us-west-2; done
kubectl get scaledobject -n skills-sqs
kubectl get pods -n skills-sqs
```











rm -f asgmt2_module4_check_result.txt
echo "✅ 채점 로그 파일 삭제 완료"
QUEUE_URL=$(aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue --query QueueUrl --output text 2>/dev/null)
if [ -n "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
  aws sqs purge-queue --region us-west-2 --queue-url "$QUEUE_URL"
  echo "✅ SQS 큐(skills-sqs-queue) 메시지 Purge 완료"
else
  echo "⚠️ SQS 큐를 찾을 수 없습니다."
fi
kubectl scale deployment sqs-worker -n skills-sqs --replicas=0 2>/dev/null
echo "✅ Worker Pod 복구 및 초기화 완료"