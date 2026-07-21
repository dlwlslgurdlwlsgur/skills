export REGION=ap-northeast-1
export ACCT=$(aws sts get-caller-identity --query Account --output text)

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
aws ecr create-repository --repository-name o11y-log-generator --region $REGION 2>/dev/null
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCT.dkr.ecr.$REGION.amazonaws.com
docker buildx build --platform linux/amd64 -t $ACCT.dkr.ecr.$REGION.amazonaws.com/o11y-log-generator:v1 --push .