REGION="ap-northeast-2"
PROJECT="wsc2026"
LIFECYCLE='{"rules":[{"rulePriority":1,"description":"keep last 5 images","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":5},"action":{"type":"expire"}}]}'

for role in user product stress; do
  REPO="${role}"
  aws ecr create-repository --repository-name "${REPO}" \
    --image-scanning-configuration scanOnPush=false \
    --image-tag-mutability IMMUTABLE \
    --encryption-configuration encryptionType=AES256 \
    --tags "Key=Project,Value=${PROJECT}" --region ${REGION} >/dev/null 2>&1 || echo "Repository ${REPO} already exists"
  aws ecr put-lifecycle-policy --repository-name "${REPO}" --lifecycle-policy-text "${LIFECYCLE}" --region ${REGION} >/dev/null 2>&1 || true
done