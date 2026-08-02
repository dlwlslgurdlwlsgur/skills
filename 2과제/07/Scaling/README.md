## Region
- 서울/ap-northeast-2

<br>

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/07/Scaling/01-vpc.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/07/Scaling/02-cluster.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/07/Scaling/03-sqs.sh
```

<br>

## ECR
- 배포파일/app.py
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/07/Scaling/04-ecr.sh
```

<br>

## EKS
```bash
CLUSTER_NAME="skm-eks-cluster"
eksctl utils write-kubeconfig --name $CLUSTER_NAME --region ap-northeast-2
eksctl utils associate-iam-oidc-provider --approve --cluster $CLUSTER_NAME --region ap-northeast-2
```

<br>

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/07/Scaling/05-iam.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/07/Scaling/06-karpenter.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/07/Scaling/07-keda.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/07/Scaling/08-deploy.sh
```
```bash
kubectl get scaledobject order-scaler -n skillsmkt
```