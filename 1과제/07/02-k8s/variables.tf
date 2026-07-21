variable "aws_region" {
  description = "모든 리소스는 서울 리전에 구성 (유의사항 7)"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "실배포에 사용할 AWS CLI 프로필"
  type        = string
  default     = "new-profile-name"
}

variable "contestant_number" {
  description = "선수등번호"
  type        = string
  default     = "999"
}

variable "grafana_admin_password" {
  description = "HelloKrSkills!<선수등번호>@ (요구사항 12)"
  type        = string
  default     = null
  sensitive   = true
}

locals {
  name_prefix            = "unicorn"
  grafana_admin_username = "skills${var.contestant_number}"
  grafana_admin_password = coalesce(var.grafana_admin_password, "HelloKrSkills!${var.contestant_number}@")
}