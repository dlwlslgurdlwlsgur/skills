# 채점 전 S3 버킷과 DynamoDB의 데이터 클렌징이 완료된지 확인하며, 클렌징이 안되었다면
# 1-1과 1-5, 1-6은 틀린 것으로 간주합니다. 이후 S3 버킷에 input/test.csv 파일을 업로드
# 하며 60초 이후에 아래 명령어 들을 수행하여 워크플로가 정상 동작 하였는지 확인합니다.


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