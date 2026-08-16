#!/usr/bin/env bash
set -u
export AWS_PAGER=""


aws docdb describe-db-clusters --region ap-northeast-2 --db-cluster-identifier skills-nosql-docdb-cluster --query 'DBClusters[0].{Cluster:DBClusterIdentifier,Status:Status,Engine:Engine,Version:EngineVersion,Encrypted:StorageEncrypted,KmsKeyId:KmsKeyId,BackupRetention:BackupRetentionPeriod,Endpoint:Endpoint,Port:Port}' --output table
aws docdb describe-db-instances --region ap-northeast-2 --db-instance-identifier skills-nosql-docdb-instance-1 --query 'DBInstances[0].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass,Engine:Engine,Cluster:DBClusterIdentifier,AZ:AvailabilityZone}' --output table
aws kms describe-key --region ap-northeast-2 --key-id alias/skills-nosql-docdb --query 'KeyMetadata.{Arn:Arn,Enabled:Enabled,KeyManager:KeyManager,KeyUsage:KeyUsage}' --output table
# Cluster=skills-nosql-docdb-cluster, Status=available, Engine=docdb, Encrypted=True, Port=27017, BackupRetention>=1인지 확인합니다.
# Instance=skills-nosql-docdb-instance-1, Status=available, Class=db.t3.medium, Cluster=skills-nosql-docdb-cluster인지 확인합니다.
# KMS Key는 alias/skills-nosql-docdb로 조회되며 Enabled=True, KeyManager=CUSTOMER인지 확인합니다.


aws secretsmanager describe-secret --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query '{Name:Name,ARN:ARN,KmsKeyId:KmsKeyId}' --output table
aws secretsmanager get-secret-value --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query SecretString --output text | jq -r '{username, host, password_set:(.password != null and .password != "")}'
aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],InstanceId:InstanceId,State:State.Name,Type:InstanceType,PublicIp:PublicIpAddress}' --output table
# Secret Name=skills-nosql-docdb-secret이고 SecretString 출력에 username, host, password_set=true가 있어야 합니다.
# host는 DocumentDB Cluster Endpoint Hostname이어야 하며 Scheme 또는 Port가 포함되면 안 됩니다.
# Client EC2 Name=skills-nosql-client-ec2, State=running, PublicIp가 존재해야 합니다.


NOSQL_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
curl -s -o /dev/null -m 10 -w "http_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/health"
curl -s -m 10 "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/health" | jq -r '
"status=\(.status)
database=\(.database)
port=\(.port)
tls=\(.tls)"'
curl -s -m 10 "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/summary" | jq -r '
"counts.orders=\(.counts.orders)
counts.products=\(.counts.products)
counts.sessions=\(.counts.sessions)
orders.createdAt=\(.dateFieldTypes.orders.createdAt)
orders.dueAt=\(.dateFieldTypes.orders.dueAt)
products.updatedAt=\(.dateFieldTypes.products.updatedAt)
sessions.lastSeen=\(.dateFieldTypes.sessions.lastSeen)
sessions.expiresAt=\(.dateFieldTypes.sessions.expiresAt)"'
# /health의 http_code=200이고 status=ok, database=skills_retail, port=27017, tls=true가 출력되어야 합니다.
# /v1/admin/summary의 http_code=200이고 counts.orders>=8, counts.products>=6, counts.sessions>=3이어야 합니다.
# dateFieldTypes에 orders.createdAt, orders.dueAt, products.updatedAt, sessions.lastSeen, sessions.expiresAt이 날짜 타입으로 표시되어야 합니다.


curl -s -o /dev/null -m 10 -w "http_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/indexes"
curl -s -m 10 "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/indexes" | jq -r '
.indexes |
"orders:",
(.orders[] | select(.key.orderId or .key.customerId or .key.status) | "  key=\(.key) unique=\(.unique // false)"),
"products:",
(.products[] | select(.key.productId or .key.warehouseId) | "  key=\(.key) unique=\(.unique // false)"),
"sessions:",
(.sessions[] | select(.key.sessionId or .key.expiresAt or .key.customerId) | "  key=\(.key) unique=\(.unique // false) expireAfterSeconds=\(.expireAfterSeconds // "N/A")")'
# http_code=200이어야 합니다.
# orders에는 {orderId:1} unique, {customerId:1, createdAt:-1}, {status:1, dueAt:1} Index가 있어야 합니다.
# products에는 {productId:1} unique, {warehouseId:1, stock:1} Index가 있어야 합니다.
# sessions에는 {sessionId:1} unique, {expiresAt:1} TTL expireAfterSeconds=0, {customerId:1, lastSeen:-1} Index가 있어야 합니다.
# Index 이름은 채점하지 않습니다.


curl -s -o /dev/null -m 10 -w "http_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/O-1001"
echo
curl -s -m 10 "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/O-1001" |
jq -r '.order | "orderId=\(.orderId)\ncustomerId=\(.customerId)\nstatus=\(.status)\nwarehouseId=\(.warehouseId)"'
echo
curl -s -m 10 "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/customers/C001/orders" |
jq -r '.items[].orderId'
echo
curl -s -m 10 "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z" |
jq -r '.items[].orderId'
echo
curl -s -m 10 "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/products/low-stock?warehouseId=W-A" |
jq -r '.items[].productId'
# 모든 조회 API의 http_code=200이어야 합니다.
# 응답 데이터는 retail_dataset.json 기준으로 다음을 만족해야 합니다.
# O-1001 조회: orderId=O-1001, customerId=C001, status=PENDING, warehouseId=W-A
# C001 주문 조회: O-1006, O-1001, O-1004 포함
# 기간 내 PENDING 조회: O-1001, O-1003, O-1006 포함
# W-A Low Stock 조회: P-BLU-003, P-RED-001 포함 및 P-GRN-002 미포함
