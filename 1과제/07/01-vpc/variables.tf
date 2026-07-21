variable "aws_region" {
  description = "모든 리소스는 서울 리전에 구성 (유의사항 7)"
  type        = string
  default     = "ap-northeast-2"
}

variable "contestant_number" {
  description = "선수등번호"
  type        = string
  default     = "999"
}

variable "vpc_cidr" {
  description = "unicorn-vpc CIDR (요구사항 3)"
  type        = string
  default     = "10.97.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.97.0.0/24", "10.97.1.0/24", "10.97.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.97.10.0/24", "10.97.11.0/24", "10.97.12.0/24"]
}

variable "eks_cluster_version" {
  type    = string
  default = "1.35"
}

variable "eks_bootstrap_public_access" {
  type    = bool
  default = true
}

variable "eks_bootstrap_public_access_cidrs" {
  type    = list(string)
  default = []
}

locals {
  name_prefix            = "unicorn"
  audit_role_external_id = "unicorn-audit-2026${var.contestant_number}"

  common_tags = {
    Project = "unicorn-tickets"
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}