ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-northeast-2"

ECR_REPO_NAME=skm-order-processor
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"

aws ecr create-repository \
  --repository-name $ECR_REPO_NAME \
  --region $REGION \
  --output text 2>/dev/null || echo "ECR repo already exists"
echo