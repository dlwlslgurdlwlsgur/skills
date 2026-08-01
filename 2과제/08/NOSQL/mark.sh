#!/usr/bin/env bash
set -u
export AWS_PAGER=""


aws docdb describe-db-clusters --region ap-northeast-2 --db-cluster-identifier skills-nosql-docdb-cluster --query 'DBClusters[0].{Cluster:DBClusterIdentifier,Status:Status,Engine:Engine,Version:EngineVersion,Encrypted:StorageEncrypted,KmsKeyId:KmsKeyId,BackupRetention:BackupRetentionPeriod,Endpoint:Endpoint,Port:Port}' --output table
aws docdb describe-db-instances --region ap-northeast-2 --db-instance-identifier skills-nosql-docdb-instance-1 --query 'DBInstances[0].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass,Engine:Engine,Cluster:DBClusterIdentifier,AZ:AvailabilityZone}' --output table
aws kms describe-key --region ap-northeast-2 --key-id alias/skills-nosql-docdb --query 'KeyMetadata.{Arn:Arn,Enabled:Enabled,KeyManager:KeyManager,KeyUsage:KeyUsage}' --output table
# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# |                                                                                                                                DescribeDBClusters                                                                                                                                 |
# +-----------------+-----------------------------+------------+--------------------------------------------------------------------------------------+---------+------------------------------------------------------------------------------------+--------+------------+----------+
# | BackupRetention |           Cluster           | Encrypted  |                                      Endpoint                                        | Engine  |                                     KmsKeyId                                       | Port   |  Status    | Version  |
# +-----------------+-----------------------------+------------+--------------------------------------------------------------------------------------+---------+------------------------------------------------------------------------------------+--------+------------+----------+
# |  1              |  skills-nosql-docdb-cluster |  True      |  skills-nosql-docdb-cluster.cluster-cxcqo8goazcr.ap-northeast-2.docdb.amazonaws.com  |  docdb  |  arn:aws:kms:ap-northeast-2:106143941813:key/0750003c-b53a-4750-b122-c90b9189387e  |  27017 |  available |  5.0.0   |
# +-----------------+-----------------------------+------------+--------------------------------------------------------------------------------------+---------+------------------------------------------------------------------------------------+--------+------------+----------+
# ---------------------------------------------------------------------------------------------------------------------------
# |                                                   DescribeDBInstances                                                   |
# +-----------------+---------------+-----------------------------+---------+---------------------------------+-------------+
# |       AZ        |     Class     |           Cluster           | Engine  |            Instance             |   Status    |
# +-----------------+---------------+-----------------------------+---------+---------------------------------+-------------+
# |  ap-northeast-2b|  db.t3.medium |  skills-nosql-docdb-cluster |  docdb  |  skills-nosql-docdb-instance-1  |  available  |
# +-----------------+---------------+-----------------------------+---------+---------------------------------+-------------+
# ----------------------------------------------------------------------------------------------------------------------------------
# |                                                           DescribeKey                                                          |
# +-----------------------------------------------------------------------------------+----------+-------------+-------------------+
# |                                        Arn                                        | Enabled  | KeyManager  |     KeyUsage      |
# +-----------------------------------------------------------------------------------+----------+-------------+-------------------+
# |  arn:aws:kms:ap-northeast-2:106143941813:key/0750003c-b53a-4750-b122-c90b9189387e |  True    |  CUSTOMER   |  ENCRYPT_DECRYPT  |
# +-----------------------------------------------------------------------------------+----------+-------------+-------------------+


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