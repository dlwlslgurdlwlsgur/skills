#!/bin/bash
set -x
REGION="ap-northeast-2"
CLUSTER_NAME="skills-cluster"
APP_NAMESPACE="skills"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=skills-vpc" --query "Vpcs[0].VpcId" --output text --region ${REGION})
PUB_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*public*" --query 'Subnets[*].SubnetId' --output text --region ${REGION} | tr '\t' ',')
DB_HOST=$(aws rds describe-db-instances --db-instance-identifier "skills-mysql80" --query "DBInstances[0].Endpoint.Address" --output text --region ${REGION} 2>/dev/null)
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}



# =====================
# =====================
# =====================
# =====================
# =====================
# 3. ALB Controller 설치 (Helm)
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
# =====================
# =====================
# =====================
# =====================
# =====================





# namespace
kubectl create namespace ${APP_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

for APP in product stress user; do
cat <<EOF >> deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP}-deployment
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
        image: ${ECR_REGISTRY}/${APP}:latest
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
EOF

cat <<EOF >> service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ${APP}-svc
  namespace: ${APP_NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: ${APP}
  ports:
  - port: 8080
    targetPort: 8080
---
EOF

cat <<EOF >> hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${APP}-hpa
  namespace: ${APP_NAMESPACE}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${APP}-deployment
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
EOF
done

# ingress
cat <<EOF > ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: skills-ingress
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
                name: user-svc
                port:
                  number: 8080
          - path: /v1/product
            pathType: Prefix
            backend:
              service:
                name: product-svc
                port:
                  number: 8080
          - path: /v1/stress
            pathType: Prefix
            backend:
              service:
                name: stress-svc
                port:
                  number: 8080
EOF

kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f hpa.yaml
kubectl apply -f ingress.yaml