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