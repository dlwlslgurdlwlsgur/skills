ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws configure set region ap-northeast-1
read -p "비번호: " NUM


BUCKET_NAME="wsc2026-sensor-alert-bucket-${NUM}"
CLUSTER_ARN=$(aws kafka list-clusters --cluster-name-filter wsc2026-msk-cluster --query "ClusterInfoList[0].ClusterArn" --output text)
aws dynamodb describe-table --table-name wsc2026-sensor-data --query "Table.[TableName,KeySchema[*].AttributeName]" --output text && aws s3api head-bucket --bucket $BUCKET_NAME 2>&1
# wsc2026-sensor-data
# sensorId        timestamp
# {
#     "BucketArn": "arn:aws:s3:::wsc2026-sensor-alert-bucket-586639730662",
#     "BucketRegion": "ap-northeast-1",
#     "AccessPointAlias": false
# }



for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text; done
# wsc2026-sensor-consumer python3.14
# wsc2026-sensor-alert-consumer   python3.14


aws kafka describe-cluster --cluster-arn $CLUSTER_ARN --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" --output text
# wsc2026-msk-cluster     ACTIVE  3.6.0   kafka.t3.small  True


for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].[State]" --output text; done
# Enabled
# Enabled


aws dynamodb scan --table-name wsc2026-sensor-data --max-items 1 --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" --output json
# {
#     "sensorId": "SENSOR-002",
#     "temperature": "64.6",
#     "status": "NORMAL"
# }


aws dynamodb scan --table-name wsc2026-sensor-data --max-items 3 --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S}" --output table
# {
#     "sensorId": "SENSOR-002",
#     "timestamp": "2026-06-01T18:28:24+09:00" (YYYY-MM-DDTHH:mm:ss±HH:mm)
# }