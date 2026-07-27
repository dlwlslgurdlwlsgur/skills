ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "ACCOUNT ID: $ACCOUNT_ID"
aws configure set region ap-southeast-1
read -p "비번호: " NUM
BUCKET_NAME="wsc2026-student-score-bucket-${NUM}"


aws s3api head-bucket --bucket $BUCKET_NAME 2>&1 > /dev/null && aws s3 ls s3://$BUCKET_NAME/
# PRE error/
# PRE input/
# PRE processed/


aws dynamodb describe-table --table-name wsc2026-student-score --query "Table.[TableName,KeySchema]" --output json
# [
#   "wsc2026-student-score",
#   [
#     {
#       "AttributeName": "studentId",
#       "KeyType": "HASH"
#     },
#     {
#       "AttributeName": "examDate",
#       "KeyType": "RANGE"
#     }
#   ]
# ]



aws lambda get-function-configuration --function-name wsc2026-student-score-function --query "[FunctionName,Runtime,Environment.Variables]" --output json
# [
#     "wsc2026-student-score-function",
#     "python3.12",
#     {
#         "S3_BUCKET": "wsc2026-student-score-bucket-103",
#         "DDB_TABLE": "wsc2026-student-score"
#     }
# ]


SM_ARN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text)
aws stepfunctions describe-state-machine --state-machine-arn $SM_ARN --query "[name,type]" --output text
# wsc2026-student-score-workflow  STANDARD


aws dynamodb get-item --table-name wsc2026-student-score --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' --query "Item.[studentId.S,average.N,grade.S]" --output text; aws s3 ls s3://$BUCKET_NAME/processed/
# STU1020 96.6  A
# 2026-05-31 22:58:16        497 test.csv


aws s3 ls s3://$BUCKET_NAME/error/
# 2026-05-31 13:58:16        267 error_(timestamp)_STU2001.json
# 2026-05-31 13:58:15        274 error_(timestamp)_STU2002.json
# 2026-05-31 13:58:15        260 error_(timestamp)_STU2004.json
# 2026-05-31 13:58:16        262 error_(timestamp)_unknown.json