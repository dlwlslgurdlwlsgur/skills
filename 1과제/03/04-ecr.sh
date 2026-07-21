REGION="ap-northeast-2"
export AWS_DEFAULT_REGION="$REGION"

ECR_NAME="wsc2026-book-ecr"
KMS_ALIAS="alias/wsc2026-ecr-kms"
IMAGE_TAG="v1.0.0"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
KMS_ARN=$(aws kms describe-key --key-id "$KMS_ALIAS" --query 'KeyMetadata.Arn' --output text)
REPOSITORY_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_NAME}"

if aws ecr describe-repositories --repository-names "$ECR_NAME" 2>/dev/null; then
else
    aws ecr create-repository \
        --repository-name "$ECR_NAME" \
        --image-tag-mutability IMMUTABLE \
        --tag-mutability-exception-filters "filterType=WILDCARD,filterRule=v1*" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=KMS,kmsKey="$KMS_ARN" > /dev/null
fi

LIFECYCLE_POLICY=$(cat <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep v1 prefixed images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["v1"],
                "countType": "imageCountMoreThan",
                "countNumber": 999
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Expire other images older than 14 days",
            "selection": {
                "tagStatus": "any",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 14
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
)

aws ecr put-lifecycle-policy \
    --repository-name "$ECR_NAME" \
    --lifecycle-policy-text "$LIFECYCLE_POLICY" > /dev/null

say "Dockerfile 생성 중..."
cat <<EOF > Dockerfile
FROM alpine:latest
WORKDIR /app
COPY ./book /app/main
RUN apk update && \\
    apk add --no-cache libc6-compat libstdc++ libgcc curl openssl && \\
    apk upgrade --no-cache busybox && \\
    chmod +x /app/main
EXPOSE 8080
CMD ["/app/main"]
EOF

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker build -t "${ECR_NAME}:${IMAGE_TAG}" .
docker tag "${ECR_NAME}:${IMAGE_TAG}" "${REPOSITORY_URI}:${IMAGE_TAG}"

docker push "${REPOSITORY_URI}:${IMAGE_TAG}"