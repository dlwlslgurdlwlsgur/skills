#!/bin/bash
set -x
set -e
export AWS_PAGER=""
export AWS_DEFAULT_REGION="$REGION"

REGION="ap-northeast-2"
ECR_NAME="wskorea26-book-repo"
KMS_ALIAS="alias/wskorea26-ecr-key"
IMAGE_TAG="stable"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
KMS_ARN=$(aws kms describe-key --key-id "$KMS_ALIAS" --query 'KeyMetadata.Arn' --output text)
REPOSITORY_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_NAME}"

say "ECR 리포지토리 생성 중: $ECR_NAME"
if aws ecr describe-repositories --repository-names "$ECR_NAME" 2>/dev/null; then
    ok "ECR 리포지토리가 이미 존재합니다."
else
    aws ecr create-repository \
        --repository-name "$ECR_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=KMS,kmsKey="$KMS_ARN" > /dev/null
    ok "ECR 리포지토리 생성 완료"
fi

cat <<EOF > Dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --chmod=755 ./book ./book
ENV AWS_REGION="ap-northeast-2"
ENV TABLE_NAME="wskorea26-data-table"
EXPOSE 8080
CMD ["./book"]
EOF

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
docker build -t "${ECR_NAME}:${IMAGE_TAG}" .
docker tag "${ECR_NAME}:${IMAGE_TAG}" "${REPOSITORY_URI}:${IMAGE_TAG}"
docker push "${REPOSITORY_URI}:${IMAGE_TAG}"