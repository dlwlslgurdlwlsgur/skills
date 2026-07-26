# 1. AWS 계정 정보 호출 (ACCOUNT_ID 등이 필요할 때 사용)
data "aws_caller_identity" "current" {}

# 2. 클러스터 이름 하드코딩 (실제 이름에 맞게 수정 가능)
locals {
  cluster_name = "contest-cluster"
}

# 3. AWS에 배포된 EKS 클러스터 정보 직접 호출
data "aws_eks_cluster" "cluster" {
  name = local.cluster_name
}

# 4. EKS 클러스터 인증 정보 직접 호출
data "aws_eks_cluster_auth" "cluster" {
  name = local.cluster_name
}