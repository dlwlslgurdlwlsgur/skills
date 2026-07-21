provider "aws" {
  region  = var.aws_region
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
}

# data.aws_eks_cluster_auth 로 미리 계산한 토큰은 credential_process 기반 프로필(root 세션 갱신)에서
# apply 도중 만료/불일치가 나는 경우가 있어, kubectl과 동일하게 매 호출 시점에 exec로 토큰을 새로 발급받는다.
provider "kubernetes" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.aws_region, "--profile", var.aws_profile]
  }
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.aws_region, "--profile", var.aws_profile]
    }
  }
}
