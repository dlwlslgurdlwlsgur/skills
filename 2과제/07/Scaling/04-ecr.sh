ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-northeast-2"

ECR_REPO_NAME=skm-order-processor
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"
# ==============================

aws ecr create-repository \
  --repository-name $ECR_REPO_NAME \
  --region $REGION \
  --output text 2>/dev/null || echo "ECR repo already exists"

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker build -t $ECR_REPO_NAME:latest .
docker tag $ECR_REPO_NAME:latest "${ECR_URI}:latest"
docker push "${ECR_URI}:latest"
echo "Image pushed: ${ECR_URI}:latest"