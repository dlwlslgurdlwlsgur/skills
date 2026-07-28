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
WORKDIR /app
COPY worker.py .
RUN pip install boto3
CMD ["python", "worker.py"]
EOF
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com
docker build -t skills-sqs-ecr .
docker tag skills-sqs-ecr:latest $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/skills-sqs-ecr:latest
docker push $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/skills-sqs-ecr:latest
echo
```

<br> 

## shell
```bash
aws configure
```
- 04-manifest.sh

<br> 

## test
```bash
SQS_URL=$(aws sqs get-queue-url --queue-name skills-sqs-queue --region us-west-2 --query "QueueUrl" --output text)
for i in {1..12}; do aws sqs send-message --queue-url $SQS_URL --message-body "test-$i" --region us-west-2; done
kubectl get scaledobject -n skills-sqs
kubectl get pods -n skills-sqs
```