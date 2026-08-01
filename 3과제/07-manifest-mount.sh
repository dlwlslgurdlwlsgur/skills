#!/bin/bash
set -x
REGION="ap-northeast-2"
CLUSTER_NAME="skills-cluster"
APP_NAMESPACE="skills"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
BUCKET="skills-bucket-${ACCOUNT_ID}"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=skills-vpc" --query "Vpcs[0].VpcId" --output text --region ${REGION})
PUB_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*public*" --query 'Subnets[*].SubnetId' --output text --region ${REGION} | tr '\t' ',')
DB_HOST=$(aws rds describe-db-proxies --db-proxy-name "skills-rds-proxy" --query "DBProxies[0].Endpoint" --output text --region ${REGION} 2>/dev/null)
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}

aws s3api create-bucket --bucket "${BUCKET}" \
    --create-bucket-configuration "LocationConstraint=${REGION}" --region ${REGION} >/dev/null 2>&1 || echo "Bucket ${BUCKET} already exists"

aws s3api put-public-access-block --bucket "${BUCKET}" \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

cat <<EOF > s3-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
EOF
aws s3api put-bucket-policy --bucket "${BUCKET}" --policy file://s3-policy.json
rm -f s3-policy.json

aws s3 website s3://${BUCKET}/ --index-document index.html --error-document error.html
S3_WEBSITE_ENDPOINT="${BUCKET}.s3-website.${REGION}.amazonaws.com"

# 2. ALB Controller 및 S3 CSI 드라이버 설치
ROLE_NAME="${CLUSTER_NAME}-LBControllerRole"
POLICY_NAME="${CLUSTER_NAME}-LBControllerPolicy"
SKILLS_ROLE_NAME="${CLUSTER_NAME}-skills-role"
SKILLS_SA_NAME="skills-sa"

CLUSTER_OIDC=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | sed 's/https:\/\///')

aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Federated": "arn:aws:iam::'"$ACCOUNT_ID"':oidc-provider/'"$CLUSTER_OIDC"'"}, "Action": "sts:AssumeRoleWithWebIdentity", "Condition": {"StringEquals": {"'"$CLUSTER_OIDC"':aud": "sts.amazonaws.com", "'"$CLUSTER_OIDC"':sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"}}}]}' >/dev/null 2>&1 || true

curl -s -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
POLICY_ARN=$(aws iam create-policy --policy-name $POLICY_NAME --policy-document file://iam_policy.json --query 'Policy.Arn' --output text 2>/dev/null || aws iam list-policies --query 'Policies[?PolicyName==`'"$POLICY_NAME"'`].Arn' --output text)
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN

cat <<EOF > service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}
EOF
kubectl apply -f service-account.yaml

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 && chmod +x get_helm.sh && ./get_helm.sh && rm -f get_helm.sh
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=$CLUSTER_NAME --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller

aws eks create-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-s3-csi-driver --region ${REGION} 2>/dev/null || true
sleep 15

kubectl create namespace ${APP_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
mkdir -p manifest && rm -f manifest/*.yaml

aws iam create-role --role-name $SKILLS_ROLE_NAME --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Federated": "arn:aws:iam::'"$ACCOUNT_ID"':oidc-provider/'"$CLUSTER_OIDC"'"}, "Action": "sts:AssumeRoleWithWebIdentity", "Condition": {"StringEquals": {"'"$CLUSTER_OIDC"':aud": "sts.amazonaws.com", "'"$CLUSTER_OIDC"':sub": "system:serviceaccount:'"$APP_NAMESPACE"':'"$SKILLS_SA_NAME"'"}}}]}' >/dev/null 2>&1 || true
aws iam attach-role-policy --role-name $SKILLS_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

cat <<EOF > manifest/skills-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SKILLS_SA_NAME}
  namespace: ${APP_NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${ACCOUNT_ID}:role/${SKILLS_ROLE_NAME}
EOF

cat <<EOF > manifest/s3-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: s3-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  mountOptions:
    - allow-delete
    - region=${REGION}
  csi:
    driver: s3.csi.aws.com
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      bucketName: ${BUCKET}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-pvc
  namespace: ${APP_NAMESPACE}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 100Gi
EOF

for APP in product stress user; do
if [ "$APP" == "product" ]; then
  MOUNT_CONFIG="
        volumeMounts:
        - name: s3-volume
          mountPath: /images
      volumes:
      - name: s3-volume
        persistentVolumeClaim:
          claimName: s3-pvc"
else
  MOUNT_CONFIG=""
fi

cat <<EOF >> manifest/deployment.yaml
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
      serviceAccountName: ${SKILLS_SA_NAME}
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
          value: "skills"
        - name: MYSQL_PASSWORD
          value: "Skills2024**"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi${MOUNT_CONFIG}
---
EOF

cat <<EOF >> manifest/service.yaml
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
done

cat <<EOF > manifest/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: skills-ingress
  namespace: ${APP_NAMESPACE}
  annotations:
    alb.ingress.kubernetes.io/load-balancer-name: skills-alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/subnets: ${PUB_SUBNETS}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/healthcheck-path: "/healthcheck"
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

kubectl wait --namespace kube-system --for=condition=ready pod --selector=app.kubernetes.io/name=aws-load-balancer-controller --timeout=120s
kubectl apply -f manifest/skills-sa.yaml
kubectl apply -f manifest/s3-pv.yaml
# kubectl apply -f manifest/deployment.yaml
# kubectl apply -f manifest/service.yaml
# kubectl apply -f manifest/ingress.yaml