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
terraform apply -auto-approve
```

<br>

## 02-k8s
```bash
cd ./02-k8s
```
```bash
terraform init
terraform plan
terraform apply -target="helm_release.aws_load_balancer_controller" -auto-approve
terraform apply -auto-approve
```










<br>

## EC2
```bash
export AWS_DEFAULT_REGION="ap-northeast-2"
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.35.3/2026-04-08/bin/linux/amd64/kubectl
sudo chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin
sudo yum install docker -y
sudo usermod -aG docker ec2-user
sudo systemctl enable --now docker
sudo chmod 666 /var/run/docker.sock
CLUSTER_NAME="contest-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root" \
  --region ap-northeast-2
aws eks associate-access-policy \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:root" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region ap-northeast-2
eksctl utils write-kubeconfig --cluster $CLUSTER_NAME --region ap-northeast-2
eksctl utils associate-iam-oidc-provider --approve --cluster $CLUSTER_NAME --region ap-northeast-2
sudo yum install mariadb105 -y
```

<br>

## RDS
```bash
CREATE TABLE IF NOT EXISTS user (
    id       VARCHAR(255) NOT NULL,
    username VARCHAR(255) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username)
);

CREATE TABLE IF NOT EXISTS product (
    id         VARCHAR(255) NOT NULL,
    name       VARCHAR(255) NOT NULL,
    price      FLOAT(8) NOT NULL,
    image_path VARCHAR(500) DEFAULT NULL,
    PRIMARY KEY (id)
);
```