ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-west-2"

ECR_REPO_NAME=skills-sqs-ecr
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"

sudo yum install docker -y
sudo usermod -aG docker ec2-user
sudo systemctl enable --now docker
sudo chmod 666 /var/run/docker.sock

aws ecr create-repository \
  --repository-name $ECR_REPO_NAME \
  --region $REGION \
  --output text 2>/dev/null || echo "ECR repo already exists"

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

cat <<EOF >> worker.py
import os
import signal
import time
import boto3

running = True

def stop(_signum, _frame):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

region = os.environ.get("AWS_REGION", "us-west-2")
queue_url = os.environ["SQS_QUEUE_URL"]
processing_seconds = int(os.environ.get("PROCESSING_SECONDS", "20"))

sqs = boto3.client("sqs", region_name=region)

while running:
    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=10,
        VisibilityTimeout=max(processing_seconds + 30, 60),
    )
    messages = response.get("Messages", [])
    if not messages:
        time.sleep(1)
        continue

    for message in messages:
        print(f"received message_id={message.get('MessageId')}", flush=True)
        time.sleep(processing_seconds)
        sqs.delete_message(
            QueueUrl=queue_url,
            ReceiptHandle=message["ReceiptHandle"],
        )
        print(f"deleted message_id={message.get('MessageId')}", flush=True)
EOF

chmod 777 worker.py
cat <<EOF >> Dockerfile
FROM python:3.9-slim
RUN pip install boto3
COPY worker.py /app/worker.py
WORKDIR /app
CMD ["python", "worker.py"]
EOF

docker build -t $ECR_REPO_NAME:latest .
docker tag $ECR_REPO_NAME:latest "${ECR_URI}:latest"
docker push "${ECR_URI}:latest"