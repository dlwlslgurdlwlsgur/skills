#!/bin/bash
REGION="ap-northeast-2"
PROJECT="wsc2026"
CLUSTER_NAME="${PROJECT}-eks"
APP_NAMESPACE="app-namespace"

# 1. 독립적으로 리소스 조회
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT}-vpc" --query "Vpcs[0].VpcId" --output text --region ${REGION})
PUB_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*public*" --query 'Subnets[*].SubnetId' --output text --region ${REGION} | tr '\t' ',')
DB_HOST=$(aws rds describe-db-instances --db-instance-identifier "${PROJECT}-mysql80" --query "DBInstances[0].Endpoint.Address" --output text --region ${REGION} 2>/dev/null)

# 2. EKS 접속 설정
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}

# 3. ALB Controller 설치 (Helm)
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# 4. K8s 리소스 배포 (User, Product, Stress)
kubectl create namespace ${APP_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

for APP in user product stress; do
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP}
  namespace: ${APP_NAMESPACE}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${APP}
  template:
    metadata:
      labels:
        app: ${APP}
    spec:
      containers:
      - name: ${APP}
        image: ${ECR_REGISTRY}/${PROJECT}/${APP}:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        env:
        - name: APP_ROLE
          value: "${APP}"
        - name: MYSQL_HOST
          value: "${DB_HOST}"
        - name: MYSQL_USER
          value: "admin"
        - name: MYSQL_DBNAME
          value: "wsc2026db"
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP}
  namespace: ${APP_NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: ${APP}
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${APP}-hpa
  namespace: ${APP_NAMESPACE}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${APP}
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF
done

# 5. Ingress (단일 엔드포인트 구성)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: main-ingress
  namespace: ${APP_NAMESPACE}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/subnets: ${PUB_SUBNETS}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /v1/user
            pathType: Prefix
            backend:
              service:
                name: user
                port:
                  number: 8080
          - path: /v1/product
            pathType: Prefix
            backend:
              service:
                name: product
                port:
                  number: 8080
          - path: /v1/stress
            pathType: Prefix
            backend:
              service:
                name: stress
                port:
                  number: 8080
EOF