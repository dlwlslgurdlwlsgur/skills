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

aws ecr create-repository \
    --repository-name "$ECR_NAME" \
    --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=KMS,kmsKey="$KMS_ARN" > /dev/null

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