terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.base.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.base.outputs.cluster_ca_cert)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.base.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.base.outputs.cluster_ca_cert)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}