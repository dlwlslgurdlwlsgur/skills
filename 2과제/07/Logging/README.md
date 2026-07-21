## shell
- app.py
- requirements.txt
- 03-ecr.sh

<br>

## EKS
```bash
CLUSTER_NAME="o11y-cluster"
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
- 비번호 설정
- 04-monitoring.sh
```bash
export BNUM=<비번호>
```