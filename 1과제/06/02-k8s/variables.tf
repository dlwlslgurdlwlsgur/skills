variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "private_subnet_a_cidr" {
  type    = string
  default = "10.0.10.0/24"
}

variable "private_subnet_b_cidr" {
  type    = string
  default = "10.0.11.0/24"
}

variable "azs" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "eks_cluster_version" {
  type    = string
  default = "1.35"
}

variable "grafana_admin_password" {
  type      = string
  default   = "Skills53#"
  sensitive = true
}

variable "eks_cluster_name" {
  type    = string
  default = "gj2026-eks-cluster"
}

variable "iam_role_name_book_app" {
  type    = string
  default = "gj2026-book-app-role"
}

variable "iam_role_name_lbc" {
  type    = string
  default = "gj2026-aws-lb-controller-role"
}

variable "iam_role_name_fluent_bit" {
  type    = string
  default = "gj2026-fluent-bit-role"
}

variable "iam_role_name_grafana" {
  type    = string
  default = "gj2026-grafana-role"
}

variable "ecr_repository_name" {
  type    = string
  default = "book"
}

variable "dynamodb_table_name" {
  type    = string
  default = "books"
}

variable "alb_target_group_book_name" {
  type    = string
  default = "gj2026-book-tg"
}

variable "alb_target_group_grafana_name" {
  type    = string
  default = "gj2026-grafana-tg" 
}