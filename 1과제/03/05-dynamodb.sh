REGION="ap-northeast-2"
export AWS_DEFAULT_REGION="$REGION"

TABLE_NAME="wsc2026-book-table"
KMS_ALIAS="alias/wsc2026-db-kms"

LAMBDA_POLICY_NAME="wsc2026-book-function-policy"
LAMBDA_ROLE_NAME="wsc2026-book-function-role"
POD_ROLE_NAME="wsc2026-book-pod-role"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
KMS_ARN=$(aws kms describe-key --key-id "$KMS_ALIAS" --query 'KeyMetadata.Arn' --output text)

say "DynamoDB 테이블 생성 중: $TABLE_NAME"

if aws dynamodb describe-table --table-name "$TABLE_NAME" 2>/dev/null; then
    ok "DynamoDB 테이블이 이미 존재합니다."
else
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=client_id,AttributeType=S \
            AttributeName=booking_id,AttributeType=S \
        --key-schema \
            AttributeName=client_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --global-secondary-indexes '[
            {
                "IndexName": "booking_id-index",
                "KeySchema": [
                    {"AttributeName": "booking_id", "KeyType": "HASH"}
                ],
                "Projection": {
                    "ProjectionType": "ALL"
                }
            }
        ]' \
        --sse-specification Enabled=true,SSEType=KMS,KMSMasterKeyId="$KMS_ARN" \
        --deletion-protection-enabled \
        > /dev/null

    ok "DynamoDB 테이블 생성 요청 완료"
    
    say "테이블 활성화 대기 중..."
    aws dynamodb wait table-exists --table-name "$TABLE_NAME"
    ok "테이블 활성화 완료"
fi

say "PITR(최상 기간 복구) 설정 활성화 중..."
aws dynamodb update-continuous-backups \
    --table-name "$TABLE_NAME" \
    --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true > /dev/null
ok "PITR 활성화 완료"





REGION="ap-northeast-2"
TABLE_NAME="wsc2026-book-table"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
TABLE_ARN="arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${TABLE_NAME}"
FIXED_POLICY_JSON=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPodWrite",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/wsc2026-book-pod-role"
      },
      "Action": "dynamodb:PutItem",
      "Resource": "${TABLE_ARN}"
    },
    {
      "Sid": "AllowLambdaQuery",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/wsc2026-book-function-role"
      },
      "Action": "dynamodb:Query",
      "Resource": "${TABLE_ARN}"
    }
  ]
}
EOF
)
aws dynamodb put-resource-policy \
    --resource-arn "$TABLE_ARN" \
    --policy "$FIXED_POLICY_JSON" > /dev/null




say "EKS Pod용 IAM 정책(데이터 삽입 전용) 생성 중..."
TABLE_ARN="arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${TABLE_NAME}"

EKS_POLICY_JSON=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DynamoDBWriteOnly",
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": "$TABLE_ARN"
        },
        {
            "Sid": "KMSAccessForWrite",
            "Effect": "Allow",
            "Action": [
                "kms:Encrypt",
                "kms:GenerateDataKey*"
            ],
            "Resource": "$KMS_ARN"
        }
    ]
}
EOF
)

EKS_POLICY_ARN=$(aws iam create-policy \
    --policy-name "wsc2026-book-pod-policy" \
    --policy-document "$EKS_POLICY_JSON" \
    --query "Policy.Arn" --output text 2>/dev/null || aws iam list-policies --query "Policies[?PolicyName=='wsc2026-book-pod-policy'].Arn" --output text)
ok "EKS용 정책 ARN: $EKS_POLICY_ARN"


say "Lambda용 IAM 정책(데이터 조회 전용) 생성 중: $LAMBDA_POLICY_NAME"
LAMBDA_POLICY_JSON=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DynamoDBReadOnly",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:BatchGetItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": [
                "$TABLE_ARN",
                "$TABLE_ARN/index/*"
            ]
        },
        {
            "Sid": "KMSAccessForRead",
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt"
            ],
            "Resource": "$KMS_ARN"
        }
    ]
}
EOF
)

LAMBDA_POLICY_ARN=$(aws iam create-policy \
    --policy-name "$LAMBDA_POLICY_NAME" \
    --policy-document "$LAMBDA_POLICY_JSON" \
    --query "Policy.Arn" --output text 2>/dev/null || aws iam list-policies --query "Policies[?PolicyName=='${LAMBDA_POLICY_NAME}'].Arn" --output text)
ok "Lambda용 정책 ARN: $LAMBDA_POLICY_ARN"


say "Lambda 서비스 역할(Role) 생성 중: $LAMBDA_ROLE_NAME"
LAMBDA_TRUST_JSON=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)

LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query "Role.Arn" --output text 2>/dev/null || \
aws iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document "$LAMBDA_TRUST_JSON" \
    --query "Role.Arn" --output text)
ok "Lambda 역할 ARN: $LAMBDA_ROLE_ARN"

aws iam attach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "$LAMBDA_POLICY_ARN"
ok "Lambda 역할 정책 연결 완료"


say "EKS Pod Identity 역할(Role) 생성 중: $POD_ROLE_NAME"
POD_TRUST_JSON=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "pods.eks.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession"
            ]
        }
    ]
}
EOF
)

POD_ROLE_ARN=$(aws iam get-role --role-name "$POD_ROLE_NAME" --query "Role.Arn" --output text 2>/dev/null || \
aws iam create-role \
    --role-name "$POD_ROLE_NAME" \
    --assume-role-policy-document "$POD_TRUST_JSON" \
    --query "Role.Arn" --output text)
ok "Pod Identity 역할 ARN: $POD_ROLE_ARN"

aws iam attach-role-policy --role-name "$POD_ROLE_NAME" --policy-arn "$EKS_POLICY_ARN"
ok "EKS Pod Identity 역할 정책 연결 완료"






KMS_KEY_ID=$(aws kms list-aliases \
  --query "Aliases[?AliasName=='alias/wsc2026-function-kms'].TargetKeyId" \
  --output text)
echo "조회된 Key ID: $KMS_KEY_ID"
aws kms get-key-policy \
  --key-id "$KMS_KEY_ID" \
  --policy-name "default" \
  --query "Policy" \
  --output text | jq '.Statement' > temp_statements.json
cat <<EOF > lambda_statement.json
[
  {
    "Sid": "AllowLambdaToUseKey",
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ],
    "Resource": "*"
  }
]
EOF
jq -n --slurpfile orig temp_statements.json --slurpfile lamb lambda_statement.json \
  '{Version: "2012-10-17", Id: "key-consolepolicy-3", Statement: ($orig[0] + $lamb[0])}' > final_policy.json
aws kms put-key-policy \
  --key-id "$KMS_KEY_ID" \
  --policy-name "default" \
  --policy file://final_policy.json
rm -f temp_statements.json lambda_statement.json final_policy.json
echo "[OK] KMS 키 정책이 성공적으로 업데이트되었습니다!"