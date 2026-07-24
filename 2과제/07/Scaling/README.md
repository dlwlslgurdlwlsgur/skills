## shell
- 01-vpc.sh
- 02-cluster.sh
- 03-sqs.sh

<br>

## ECR
- 04-ecr.sh
- docker build

<br>

## EKS
```bash
CLUSTER_NAME="skm-eks-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
eksctl utils write-kubeconfig --name $CLUSTER_NAME --region ap-northeast-2
eksctl utils associate-iam-oidc-provider --approve --cluster $CLUSTER_NAME --region ap-northeast-2
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root"
aws eks associate-access-policy \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

<br>

## shell
- 05-iam.sh
- 06-karpenter.sh
- 07-keda.sh
- 08-deploy.sh
```bash
kubectl get scaledobject order-scaler -n skillsmkt
```