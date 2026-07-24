## module 설치
```bash
aws configure
```
```bash
winget install Kubernetes.kubectl
winget install Helm.Helm
winget install HashiCorp.Terraform
```

<br>

## 01-vpc
```bash
cd ./01-vpc
```
```bash
terraform init
terraform plan
terraform apply
```

<br>

## ECR
 



## 02-k8s
```bash
aws eks update-kubeconfig --region ap-northeast-2 --name gj2026-eks-cluster
kubectl get all -A
```
```bash
cd ./02-k8s
```
```bash
terraform init
terraform apply -target="helm_release.aws_load_balancer_controller" -auto-approve
terraform apply -auto-approve
```