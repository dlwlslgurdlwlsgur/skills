## Region
- 오레곤/us-west-2

<br> 

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/08/Scaling/01-vpc.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/08/Scaling/02-cluster.sh
```

<br>

## ECR
- 배포파일/worker.py
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/08/Scaling/03-ecr.sh
```

<br> 

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/08/Scaling/04-iam.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/08/Scaling/05-karpenter.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/08/Scaling/06-keda.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/08/Scaling/07-deploy.sh
```

<br> 

## test
```bash
SQS_URL=$(aws sqs get-queue-url --queue-name skills-sqs-queue --region us-west-2 --query "QueueUrl" --output text)
for i in {1..12}; do aws sqs send-message --queue-url $SQS_URL --message-body "test-$i" --region us-west-2; done
kubectl get scaledobject -n skills-sqs
kubectl get pods -n skills-sqs
```