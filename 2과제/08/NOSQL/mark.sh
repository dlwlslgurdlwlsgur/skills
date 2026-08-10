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