#!/bin/bash
set -x
REGION="ap-northeast-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="skills-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "${BUCKET}" \
    --create-bucket-configuration "LocationConstraint=${REGION}" --region ${REGION} >/dev/null 2>&1 || echo "Bucket ${BUCKET} already exists"