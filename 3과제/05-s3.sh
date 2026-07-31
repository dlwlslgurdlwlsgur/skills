#!/bin/bash
set -x
REGION="ap-northeast-2"
CLUSTER_NAME="skills-cluster"
APP_NAMESPACE="skills"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="skills-bucket-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "${BUCKET}" \
    --create-bucket-configuration "LocationConstraint=${REGION}" --region ${REGION} >/dev/null 2>&1 || echo "Bucket ${BUCKET} already exists"

aws s3api put-public-access-block --bucket "${BUCKET}" \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

cat <<EOF > s3-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket "${BUCKET}" --policy file://s3-policy.json
rm -f s3-policy.json