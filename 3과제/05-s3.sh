REGION="ap-northeast-2"
PROJECT="wsc2026"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${PROJECT}-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "${BUCKET}" \
    --create-bucket-configuration "LocationConstraint=${REGION}" --region ${REGION} >/dev/null 2>&1 || echo "Bucket ${BUCKET} already exists"
aws s3api put-bucket-tagging --bucket "${BUCKET}" \
    --tagging "TagSet=[{Key=Project,Value=${PROJECT}}]" --region ${REGION}