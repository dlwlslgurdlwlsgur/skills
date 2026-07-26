## Region
- 도쿄/ap-northeast-1

<br>

## shell
- 01-vpc.sh
- 02-cluster.sh

<br>

## ECR
- 03-ecr.sh
```bash
echo "flask>=3.0.0" > requirements.txt
cat > Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
ENV PYTHONUNBUFFERED=1
CMD ["python", "app.py"]
EOF
```
```bash
export ACCT=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $ACCT.dkr.ecr.ap-northeast-1.amazonaws.com
docker build -t o11y-log-generator .
docker tag o11y-log-generator:latest $ACCT.dkr.ecr.ap-northeast-1.amazonaws.com/o11y-log-generator:v1
docker push $ACCT.dkr.ecr.ap-northeast-1.amazonaws.com/o11y-log-generator:v1
```


<br>

## shell
```bash
export BNUM=<비번호>
```
- 04-monitoring.sh