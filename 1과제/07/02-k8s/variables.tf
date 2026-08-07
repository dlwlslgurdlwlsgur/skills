variable "aws_region" {
  description = "test1"
  type        = string
  default     = "ap-northeast-2"
}

variable "contestant_number" {
  description = "비번호"
  type        = string
  default     = "999"
}

variable "grafana_admin_password" {
  description = "HelloKrSkills!<비번호>@"
  type        = string
  default     = null
  sensitive   = true
}

locals {
  name_prefix            = "unicorn"
  grafana_admin_username = "skills${var.contestant_number}"
  grafana_admin_password = coalesce(var.grafana_admin_password, "HelloKrSkills!${var.contestant_number}@")
}