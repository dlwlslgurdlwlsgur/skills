variable "aws_region" {
  type        = string
  default     = "ap-northeast-2"
}

variable "badge_number" {
  type        = string
  default     = "999"
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
