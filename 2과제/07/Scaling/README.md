## Region
- 서울/ap-northeast-2

<br>

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
eksctl utils write-kubeconfig --name $CLUSTER_NAME --region ap-northeast-2
eksctl utils associate-iam-oidc-provider --approve --cluster $CLUSTER_NAME --region ap-northeast-2
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