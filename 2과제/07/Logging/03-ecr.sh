export REGION=ap-northeast-1
export ACCT=$(aws sts get-caller-identity --query Account --output text)

aws ecr create-repository --repository-name o11y-log-generator --region $REGION 2>/dev/null