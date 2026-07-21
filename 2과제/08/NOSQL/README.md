## Vpc
- pub: 2
- priv: 2


## Kms
- 이름: skills-nosql-docdb


## DocuemntDB
- user 이름: skills
- 고급 설정 KMS
- 클러스티, 인스턴스 이름 각각 지정


## Python
```
sudo yum install python3-pip -y
pip3 install pymongo boto3 Flask
```


## Python 경로 설정
- 배포파일을 가져온 후에 실행
```
sudo mkdir -p /opt/skills-nosql
sudo chown -R ec2-user:ec2-user /opt/skills-nosql
wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -O /opt/skills-nosql/global-bundle.pem
cp retail_dataset.json /opt/skills-nosql/retail_dataset.json
```


## Python INDEX 설정
```
python3 ./docdb_client.py seed
# {"counts": {"orders": 8, "products": 6, "sessions": 3}}
```
```
python3 ./docdb_client.py counts
# {"counts": {"orders": 8, "products": 6, "sessions": 3}, "dateFieldTypes": {"orders": {"createdAt": "datetime", "dueAt": "datetime"}, "products": {"updatedAt": "datetime"}, "sessions": {"lastSeen": "datetime", "expiresAt": "datetime"}}}
```
```
cat << 'EOF' > make_index.py
import json
import boto3
from pymongo import MongoClient

# 1. 암호 읽어오기
secret_client = boto3.client("secretsmanager", region_name="ap-northeast-2")
res = secret_client.get_secret_value(SecretId="skills-nosql-docdb-secret")
secret = json.loads(res["SecretString"])

# 2. 데이터베이스 연결
uri = f"mongodb://{secret['username']}:{secret['password']}@{secret['host']}:27017/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
client = MongoClient(uri, tls=True, tlsCAFile="/opt/skills-nosql/global-bundle.pem")
db = client["skills_retail"]

# 3. orders 인덱스 생성
db.orders.create_index([("orderId", 1)], unique=True)
db.orders.create_index([("customerId", 1), ("createdAt", -1)])
db.orders.create_index([("status", 1), ("dueAt", 1)])

# 4. products 인덱스 생성
db.products.create_index([("productId", 1)], unique=True)
db.products.create_index([("warehouseId", 1), ("stock", 1)])

# 5. sessions 인덱스 생성 (만료용 TTL 포함)
db.sessions.create_index([("sessionId", 1)], unique=True)
db.sessions.create_index([("expiresAt", 1)], expireAfterSeconds=0)
db.sessions.create_index([("customerId", 1), ("lastSeen", -1)])

print(">>> [OK] 모든 인덱스가 완벽하게 생성되었습니다! <<<")
EOF
python3 make_index.py
```


## Python RUN
```
nohup python3 ./docdb_client.py serve > app.log 2>&1 &
```