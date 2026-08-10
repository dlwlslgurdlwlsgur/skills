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
CLIENT_IP=$(aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
echo "CLIENT_IP=${CLIENT_IP}"
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# |                                                                                                DescribeSecret                                                                                                 |
# +---------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------+----------------------------+
# |                                             ARN                                             |                                     KmsKeyId                                       |           Name             |
# +---------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------+----------------------------+
# |  arn:aws:secretsmanager:ap-northeast-2:106143941813:secret:skills-nosql-docdb-secret-QNLil4 |  arn:aws:kms:ap-northeast-2:106143941813:key/0750003c-b53a-4750-b122-c90b9189387e  |  skills-nosql-docdb-secret |
# +---------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------+----------------------------+
# {
#   "username": "skills",
#   "host": "skills-nosql-docdb-cluster.cluster-cxcqo8goazcr.ap-northeast-2.docdb.amazonaws.com",
#   "password_set": true
# }
# ------------------------------------------------------------------------------------------
# |                                    DescribeInstances                                   |
# +----------------------+---------------------------+--------------+----------+-----------+
# |      InstanceId      |           Name            |  PublicIp    |  State   |   Type    |
# +----------------------+---------------------------+--------------+----------+-----------+
# |  i-0513de344d91b3386 |  skills-nosql-client-ec2  |  3.34.187.75 |  running |  t3.micro |
# +----------------------+---------------------------+--------------+----------+-----------+
# CLIENT_IP=3.34.187.75


if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/health"; echo
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/admin/summary"; echo
else
  echo "Client EC2 Public IP 식별 실패"
fi
# {"status": "ok", "database": "skills_retail", "port": 27017, "tls": true}
# http_code=200
# {"database": "skills_retail", "counts": {"orders": 8, "products": 6, "sessions": 3}, "dateFieldTypes": {"orders": {"createdAt": "datetime", "dueAt": "datetime"}, "products": {"updatedAt": "datetime"}, "sessions": {"lastSeen": "datetime", "expiresAt": "datetime"}}}
# http_code=200


if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/admin/indexes"; echo
else
  echo "Client EC2 Public IP 식별 실패"
fi
# {"indexes": {
# "orders": [
#   {"v": 4, "key": {"_id": 1}, "name": "_id_", "ns": "skills_retail.orders"}, 
#   {"v": 4, "unique": true, "key": {"orderId": 1}, "name": "orderId_1", "ns": "skills_retail.orders"}, 
#   {"v": 4, "key": {"customerId": 1, "createdAt": -1}, "name": "customerId_1_createdAt_-1", "ns": "skills_retail.orders"}, 
#   {"v": 4, "key": {"status": 1, "dueAt": 1}, "name": "status_1_dueAt_1", "ns": "skills_retail.orders"}
# ], 
# "products": [
#   {"v": 4, "key": {"_id": 1}, "name": "_id_", "ns": "skills_retail.products"}, 
#   {"v": 4, "unique": true, "key": {"productId": 1}, "name": "productId_1", "ns": "skills_retail.products"}, 
#   {"v": 4, "key": {"warehouseId": 1, "stock": 1}, "name": "warehouseId_1_stock_1", "ns": "skills_retail.products"}
# ], 
# "sessions": [
#   {"v": 4, "key": {"_id": 1}, "name": "_id_", "ns": "skills_retail.sessions"}, 
#   {"v": 4, "unique": true, "key": {"sessionId": 1}, "name": "sessionId_1", "ns": "skills_retail.sessions"}, 
#   {"v": 4, "key": {"expiresAt": 1}, "name": "expiresAt_1", "ns": "skills_retail.sessions", "expireAfterSeconds": 0}, 
#   {"v": 4, "key": {"customerId": 1, "lastSeen": -1}, "name": "customerId_1_lastSeen_-1", "ns": "skills_retail.sessions"}
# ]
# }}
# http_code=200


if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/orders/O-1001"; echo
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/customers/C001/orders"; echo
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"; echo
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/products/low-stock?warehouseId=W-A"; echo
else
  echo "Client EC2 Public IP 식별 실패"
fi
# {"order": {"orderId": "O-1001", "customerId": "C001", "status": "PENDING", "warehouseId": "W-A", "createdAt": "2026-06-01T09:10:00Z", "dueAt": "2026-06-04T00:00:00Z", "totalAmount": 135.5, "items": [{"productId": "P-RED-001", "qty": 2, "price": 45.0}, {"productId": "P-GRN-002", "qty": 1, "price": 45.5}]}}
# http_code=200

# {"customerId": "C001", "items": [{"orderId": "O-1006", "customerId": "C001", "status": "PENDING", "warehouseId": "W-A", "createdAt": "2026-06-03T08:00:00Z", "dueAt": "2026-06-07T00:00:00Z", "totalAmount": 56.0, "items": [{"productId": "P-BLK-005", "qty": 2, "price": 28.0}]}, {"orderId": "O-1001", "customerId": "C001", "status": "PENDING", "warehouseId": "W-A", "createdAt": "2026-06-01T09:10:00Z", "dueAt": "2026-06-04T00:00:00Z", "totalAmount": 135.5, "items": [{"productId": "P-RED-001", "qty": 2, "price": 45.0}, {"productId": "P-GRN-002", "qty": 1, "price": 45.5}]}, {"orderId": "O-1004", "customerId": "C001", "status": "CANCELLED", "warehouseId": "W-C", "createdAt": "2026-05-20T10:30:00Z", "dueAt": "2026-05-25T00:00:00Z", "totalAmount": 32.0, "items": [{"productId": "P-BLK-005", "qty": 1, "price": 32.0}]}]}
# http_code=200

# {"items": [{"orderId": "O-1001", "customerId": "C001", "status": "PENDING", "warehouseId": "W-A", "createdAt": "2026-06-01T09:10:00Z", "dueAt": "2026-06-04T00:00:00Z", "totalAmount": 135.5, "items": [{"productId": "P-RED-001", "qty": 2, "price": 45.0}, {"productId": "P-GRN-002", "qty": 1, "price": 45.5}]}, {"orderId": "O-1003", "customerId": "C003", "status": "PENDING", "warehouseId": "W-A", "createdAt": "2026-06-02T11:00:00Z", "dueAt": "2026-06-06T00:00:00Z", "totalAmount": 210.0, "items": [{"productId": "P-YLW-004", "qty": 3, "price": 70.0}]}, {"orderId": "O-1006", "customerId": "C001", "status": "PENDING", "warehouseId": "W-A", "createdAt": "2026-06-03T08:00:00Z", "dueAt": "2026-06-07T00:00:00Z", "totalAmount": 56.0, "items": [{"productId": "P-BLK-005", "qty": 2, "price": 28.0}]}]}
# http_code=200
# {"warehouseId": "W-A", "items": [{"productId": "P-BLU-003", "warehouseId": "W-A", "name": "Blue Widget", "category": "widget", "stock": 1, "reorderPoint": 5, "updatedAt": "2026-06-03T00:00:00Z"}, {"productId": "P-RED-001", "warehouseId": "W-A", "name": "Red Widget", "category": "widget", "stock": 4, "reorderPoint": 10, "updatedAt": "2026-06-03T00:00:00Z"}]}
# http_code=200




# #!/usr/bin/env bash
# set -u
# export AWS_PAGER=""
# OUT_TXT="asgmt2_module1_check_result.txt"
# exec > >(tee "$OUT_TXT") 2>&1
# for CMD in aws jq curl; do
#   if ! command -v "$CMD" >/dev/null 2>&1; then
#     echo "ERROR: required command not found: $CMD" >&2
#     exit 2
#   fi
# done


# aws docdb describe-db-clusters --region ap-northeast-2 --db-cluster-identifier skills-nosql-docdb-cluster --query 'DBClusters[0].{Cluster:DBClusterIdentifier,Status:Status,Engine:Engine,Version:EngineVersion,Encrypted:StorageEncrypted,KmsKeyId:KmsKeyId,BackupRetention:BackupRetentionPeriod,Endpoint:Endpoint,Port:Port}' --output table
# aws docdb describe-db-instances --region ap-northeast-2 --db-instance-identifier skills-nosql-docdb-instance-1 --query 'DBInstances[0].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass,Engine:Engine,Cluster:DBClusterIdentifier,AZ:AvailabilityZone}' --output table
# aws kms describe-key --region ap-northeast-2 --key-id alias/skills-nosql-docdb --query 'KeyMetadata.{Arn:Arn,Enabled:Enabled,KeyManager:KeyManager,KeyUsage:KeyUsage}' --output table
# # DocumentDB Cluster/Instance와 KMS Key가 요구사항과 일치하는지 확인합니다.


# aws secretsmanager describe-secret --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query '{Name:Name,ARN:ARN,KmsKeyId:KmsKeyId}' --output table
# aws secretsmanager get-secret-value --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query SecretString --output text | jq -r '{username, host, password_set:(.password != null and .password != "")}'
# aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],InstanceId:InstanceId,State:State.Name,Type:InstanceType,PublicIp:PublicIpAddress}' --output table
# CLIENT_IP=$(aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
# echo "CLIENT_IP=${CLIENT_IP}"
# # Secret에 username, password, host가 있고 Client EC2가 running 상태이며 Public IP가 있는지 확인합니다.


# if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/health"; echo
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/admin/summary"; echo
# else
#   echo "Client EC2 Public IP 식별 실패"
# fi
# # /health, /v1/admin/summary가 HTTP 200을 반환하고 데이터 적재 상태가 요구사항과 일치하는지 확인합니다.


# if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/admin/indexes"; echo
# else
#   echo "Client EC2 Public IP 식별 실패"
# fi
# # 컬렉션별 Index와 TTL 구성이 요구사항과 일치하는지 확인합니다.


# if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "None" ]; then
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/orders/O-1001"; echo
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/customers/C001/orders"; echo
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"; echo
#   curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/v1/products/low-stock?warehouseId=W-A"; echo
# else
#   echo "Client EC2 Public IP 식별 실패"
# fi
# # 각 조회 API가 HTTP 200을 반환하고 조건에 맞는 데이터가 포함되는지 확인합니다.














#!/usr/bin/env bash
set -u
export AWS_PAGER=""


export PATH="$HOME/.local/bin:$PATH"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    KUBECTL_ARCH="amd64"
    AWSCLI_ARCH="x86_64"
    ;;
  aarch64|arm64)
    KUBECTL_ARCH="arm64"
    AWSCLI_ARCH="aarch64"
    ;;
  *)
    echo "지원하지 않는 CPU 아키텍처입니다: $ARCH"
    exit 2
    ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v grep >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  sudo dnf install -y curl jq grep unzip
fi

if ! command -v kubectl >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  curl -L -o "$HOME/.local/bin/kubectl" "https://dl.k8s.io/release/v1.35.0/bin/linux/${KUBECTL_ARCH}/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
fi

if ! command -v aws >/dev/null 2>&1; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-${AWSCLI_ARCH}.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install --install-dir "$HOME/usr/local/aws-cli" --bin-dir "$HOME/.local/bin" --update
fi

aws --version
curl --version
jq --version
grep --version
unzip -v | head -n 1
kubectl version --client
aws sts get-caller-identity --output table


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
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/health"
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/summary"
# /health의 http_code=200이고 status=ok, database=skills_retail, port=27017, tls=true가 출력되어야 합니다.
# /v1/admin/summary의 http_code=200이고 counts.orders>=8, counts.products>=6, counts.sessions>=3이어야 합니다.
# dateFieldTypes에 orders.createdAt, orders.dueAt, products.updatedAt, sessions.lastSeen, sessions.expiresAt이 날짜 타입으로 표시되어야 합니다.


curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/indexes"
# http_code=200이어야 합니다.
# orders에는 {orderId:1} unique, {customerId:1, createdAt:-1}, {status:1, dueAt:1} Index가 있어야 합니다.
# products에는 {productId:1} unique, {warehouseId:1, stock:1} Index가 있어야 합니다.
# sessions에는 {sessionId:1} unique, {expiresAt:1} TTL expireAfterSeconds=0, {customerId:1, lastSeen:-1} Index가 있어야 합니다.
# Index 이름은 채점하지 않습니다.


curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/O-1001"
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/customers/C001/orders"
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/products/low-stock?warehouseId=W-A"
# 모든 조회 API의 http_code=200이어야 합니다.
# 응답 데이터는 retail_dataset.json 기준으로 다음을 만족해야 합니다.
# O-1001 조회: orderId=O-1001, customerId=C001, status=PENDING, warehouseId=W-A
# C001 주문 조회: O-1006, O-1001, O-1004 포함
# 기간 내 PENDING 조회: O-1001, O-1003, O-1006 포함
# W-A Low Stock 조회: P-BLU-003, P-RED-001 포함 및 P-GRN-002 미포함