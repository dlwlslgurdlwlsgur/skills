## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/01-vpc.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/02-ec2.sh
```

<br>

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/03-cluster.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/04-rds.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/05-s3.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/06-ecr.sh
```

<br>

## RDS
```bash
CREATE DATABASE skills CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
```
```bash
CREATE TABLE IF NOT EXISTS user (
  id       VARCHAR(255) NOT NULL,
  username VARCHAR(255) NOT NULL,
  email    VARCHAR(255) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_username (username)
);

CREATE TABLE IF NOT EXISTS product (
  id         VARCHAR(255) NOT NULL,
  name       VARCHAR(255) NOT NULL,
  price      FLOAT(8) NOT NULL,
  image_path VARCHAR(500) DEFAULT NULL,
  PRIMARY KEY (id)
);
CREATE INDEX idx_user_email_cover ON user (email, username);
```

<br>

## dump
```bash
mysql -h <DB_HOST> -P 3306 -u admin -p skills < load_user.dump
```

<br>

## manifest
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/07-manifest.sh
```
```bash
kubectl apply -f manifest/deployment.yaml
kubectl apply -f manifest/service.yaml
kubectl apply -f manifest/ingress.yaml
kubectl apply -f manifest/hpa.yaml
```

<br>

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/08-ca.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/09-waf.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/10-monitoring.sh
```

<br>

## CloudFront
- WAF 연결
- ALB: *
- ALB: http
- ALB: Caching Disabled, AllViewer
- S3: /images/*

<br>

## cluster
```bash
CLUSTER_NAME="skills-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root"
aws eks associate-access-policy \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```
```bash
CLUSTER_NAME="skills-cluster"
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl utils write-kubeconfig --name $CLUSTER_NAME
eksctl utils associate-iam-oidc-provider --approve --cluster $CLUSTER_NAME
```

<br>

## user
```bash
export URL=""
```
```bash
curl -X POST "$URL/v1/user" \
  -H "Content-Type: application/json" \
  -d '{
    "requestid": "999999999999",
    "uuid": "7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729",
    "username": "dbdump500001",
    "email": "dbdump500001@example.org"
  }'
```
```bash
curl -X GET "$URL/v1/user?email=dbdump500001@example.org&requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
```

<br>

## product
```bash
curl -X POST "$URL/v1/product" \
  -H "Content-Type: application/json" \
  -d '{
    "requestid": "999999999999",
    "uuid": "7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729",
    "id": "dbdump500001",
    "name": "dbdump500001",
    "price": 1234
  }'
```
```bash
curl -X GET "$URL/v1/product?id=dbdump500001&requestid=999999999999&uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729"
```
```bash
echo "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=" | base64 -d > image.jpg
curl -X PUT "$URL/v1/product" \
  -F "requestid=999999999999" \
  -F "uuid=7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729" \
  -F "id=dbdump500001" \
  -F "image=@./image.jpg;type=image/jpeg"
```

<br>

## stress
```bash
curl -X POST "$URL/v1/stress" \
  -H "Content-Type: application/json" \
  -d '{
    "requestid": "999999999999",
    "uuid": "7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729",
    "length": 256
  }'
```