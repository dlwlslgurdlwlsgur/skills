#!/bin/bash
set -x

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-northeast-2"

ECR_REPO_NAME=skm-order-processor
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"

aws ecr create-repository \
  --repository-name $ECR_REPO_NAME \
  --region $REGION \
  --output text 2>/dev/null || echo "ECR repo already exists"
echo

cat > Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
RUN pip install flask
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]

EOF
export ACCT=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $ACCT.dkr.ecr.ap-northeast-2.amazonaws.com
docker build -t skm-order-processor .
docker tag skm-order-processor:latest $ACCT.dkr.ecr.ap-northeast-2.amazonaws.com/skm-order-processor:latest
docker push $ACCT.dkr.ecr.ap-northeast-2.amazonaws.com/skm-order-processor:latest