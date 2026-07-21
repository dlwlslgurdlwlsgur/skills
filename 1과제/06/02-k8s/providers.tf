terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.aws_eks_cluster.this.name
}

data "aws_ecr_repository" "book" {
  name = var.ecr_repository_name
}

data "aws_lb_target_group" "book" {
  name = var.alb_target_group_book_name
}

data "aws_lb_target_group" "grafana" {
  name = var.alb_target_group_grafana_name
}

data "aws_iam_role" "book_app" {
  name = var.iam_role_name_book_app
}

data "aws_iam_role" "lbc" {
  name = var.iam_role_name_lbc
}

data "aws_iam_role" "fluent_bit" {
  name = var.iam_role_name_fluent_bit
}

data "aws_iam_role" "grafana" {
  name = var.iam_role_name_grafana
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}