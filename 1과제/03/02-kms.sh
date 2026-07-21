#!/usr/bin/env bash
set -e

REGION="ap-northeast-2"
export AWS_DEFAULT_REGION="$REGION"

KMS_EKS_ALIAS="alias/wsc2026-eks-kms"
KMS_DB_ALIAS="alias/wsc2026-db-kms"
KMS_ECR_ALIAS="alias/wsc2026-ecr-kms"
KMS_FUNCTION_ALIAS="alias/wsc2026-function-kms"
KMS_BUCKET_ALIAS="alias/wsc2026-bucket-kms"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

# 1. CLI를 통해 현재 AWS 계정 ID 동적으로 가져오기
say "AWS 계정 ID 조회 중..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ok "조회된 계정 ID: $ACCOUNT_ID"

# 2. 동적으로 변수가 삽입된 키 정책 JSON 생성 함수
get_key_policy_json() {
    cat <<EOF
{
    "Version": "2012-10-17",
    "Id": "key-consolepolicy-3",
    "Statement": [
        {
            "Sid": "Enable IAM Admin And Root Account Without Saying Root Word",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": [
                "kms:List*",
                "kms:Describe*",
                "kms:Get*",
                "kms:CancelKeyDeletion",
                "kms:ConnectCustomKeyStore",
                "kms:Create*",
                "kms:Delete*",
                "kms:DeriveSharedSecret",
                "kms:Disable*",
                "kms:DisconnectCustomKeyStore",
                "kms:Enable*",
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:Generate*",
                "kms:ImportKeyMaterial",
                "kms:ReEncrypt*",
                "kms:ReplicateKey",
                "kms:RotateKeyOnDemand",
                "kms:ScheduleKeyDeletion",
                "kms:UntagResource",
                "kms:TagResource",
                "kms:RevokeGrant",
                "kms:RetireGrant",
                "kms:PutKeyPolicy",
                "kms:Verify*",
                "kms:Update*",
                "kms:SynchronizeMultiRegionKey",
                "kms:Sign"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalAccount": "$ACCOUNT_ID"
                }
            }
        }
    ]
}
EOF
}

ensure_key() {
  local alias="$1" name="${1#alias/}"
  local keyid
  
  say "KMS 키 확인 중: $alias"
  keyid=$(aws kms list-aliases --query "Aliases[?AliasName=='${alias}'].TargetKeyId" --output text)
  
  if [ -z "$keyid" ] || [ "$keyid" = "None" ]; then
    say "키가 없으므로 새로 생성합니다..."
    keyid=$(aws kms create-key \
      --description "$name" \
      --tags TagKey=Name,TagValue=$name \
      --query 'KeyMetadata.KeyId' --output text)
    aws kms create-alias --alias-name "$alias" --target-key-id "$keyid"
    ok "키 생성 및 별칭 지정 완료: $keyid"
  else
    ok "기존 키 발견: $keyid"
  fi

  # 3. 생성되거나 기존에 있던 키에 동적 JSON 정책 적용
  say "$alias 키에 정책 적용 중..."
  aws kms put-key-policy \
    --key-id "$keyid" \
    --policy-name "default" \
    --policy "$(get_key_policy_json)"
  ok "$alias 정책 적용 완료"

  local arn
  arn=$(aws kms describe-key --key-id "$keyid" --query 'KeyMetadata.Arn' --output text)
  echo "$arn"
}

# 함수 실행
ensure_key "$KMS_EKS_ALIAS"
ensure_key "$KMS_DB_ALIAS"
ensure_key "$KMS_ECR_ALIAS"
ensure_key "$KMS_FUNCTION_ALIAS"
ensure_key "$KMS_BUCKET_ALIAS"