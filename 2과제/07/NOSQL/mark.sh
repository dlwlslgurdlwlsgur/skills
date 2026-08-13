unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
rm -rf ~/.aws
aws sts get-caller-identity | jq .Account


aws dynamodb describe-table --table-name bigbae-nosql-reservation-table --region ap-southeast-1 | jq -r '.Table.TableName, (.Table.KeySchema[] | .KeyType + " " + .AttributeName), (.Table.AttributeDefinitions[] | .AttributeName + " " + .AttributeType), .Table.StreamSpecification.StreamViewType, .Table.BillingModeSummary.BillingMode'
aws dynamodb describe-continuous-backups --table-name bigbae-nosql-reservation-table --region ap-southeast-1 | jq -r .ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus
# bigbae-nosql-reservation-table
# HASH train_id
# RANGE seat_id
# seat_id S
# train_id S
# NEW_AND_OLD_IMAGES
# PAY_PER_REQUEST
# # ENABLED


aws dynamodb describe-table --table-name bigbae-nosql-reservation-table --region ap-southeast-1 | jq -r '.Table.GlobalSecondaryIndexes[] | .IndexName, (.KeySchema[] | .KeyType + " " + .AttributeName), .Projection.ProjectionType'
aws dynamodb describe-table --table-name bigbae-nosql-audit-table --region ap-southeast-1 | jq -r '.Table.TableName, (.Table.KeySchema[] | .KeyType + " " + .AttributeName)'
# gsi-user-reservations
# HASH user_id
# RANGE reserved_at
# ALL
# bigbae-nosql-audit-table
# HASH event_id


aws lambda get-function --function-name bigbae-nosql-reservation-audit --region ap-southeast-1 | jq -r '.Configuration.FunctionName, .Configuration.Runtime, (.Configuration.Timeout | tostring)'
aws lambda list-event-source-mappings --function-name bigbae-nosql-reservation-audit --region ap-southeast-1 | jq -r '.EventSourceMappings[] | (.EventSourceArn | split("/")[1]), .State'
# bigbae-nosql-reservation-audit
# python3.13
# 30
# bigbae-nosql-reservation-table
# Enabled


EC2_IP=$(aws ec2 describe-instances --region ap-southeast-1 --filters "Name=tag:Name,Values=bigbae-nosql-app-ec2"  "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].PublicIpAddress" --output text)
echo "EC2 IP" ${EC2_IP}
curl -s --max-time 10 -o /dev/null -w "healthcheck %{http_code}\n" "http://${EC2_IP}:8080/healthcheck"
# EC2 IP 13.250.1.43
# healthcheck 200


I=$(aws ec2 describe-instances --region ap-southeast-1 --filters Name=tag:Name,Values=bigbae-nosql-app-ec2 Name=instance-state-name,Values=running --query Reservations[].Instances[].PublicIpAddress --output text)
T=train-$(date +%s) S=A1 U=user1 V=user2
R(){ curl -s -w" %{http_code}" -X POST http://$I:8080/$1 -H Content-Type:application/json -d "{\"train_id\":\"$T\",\"seat_id\":\"$S\",\"user_id\":\"$2\"}"; echo; }
R reserve $U; R reserve $V; R cancel $V; R cancel $U
# {"seat_id":"A1","status":"reserved","version":1} 200
# {"error":"already reserved"} 409
# {"error":"not owner"} 409
# {"seat_id":"A1","status":"cancelled"} 200


I=$(aws ec2 describe-instances --region ap-southeast-1 --filters Name=tag:Name,Values=bigbae-nosql-app-ec2 Name=instance-state-name,Values=running --query Reservations[].Instances[].PublicIpAddress --output text)
T=train-$(date +%s) S=B1 U=usr1
P(){ curl -s -X POST http://$I:8080/$1 -H Content-Type:application/json -d "{\"train_id\":\"$T\",\"seat_id\":\"$S\",\"user_id\":\"$U\"}" >/dev/null; }
A(){ aws dynamodb scan --table-name bigbae-nosql-audit-table --region ap-southeast-1|jq "[.Items[]|select(.train_id.S==\"$T\" and .seat_id.S==\"$S\")]|length"; }
P reserve
curl -s http://$I:8080/my-bookings/$U|jq "[.[]|select(.train_id==\"$T\" and .seat_id==\"$S\")]|length"
curl -s http://$I:8080/seats/$T|jq "[.[]|select(.seat_id==\"$S\")]|[.[0].status,.[0].user_id==\"$U\"]"
sleep 30;A
P cancel
curl -s http://$I:8080/my-bookings/$U|jq "[.[]|select(.train_id==\"$T\" and .seat_id==\"$S\")]|length"
sleep 30;A
echo
# 1
# ["reserved", true]
# 1
# 0
# 2