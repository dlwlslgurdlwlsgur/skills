data "aws_caller_identity" "current" {}

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = ["unicorn-vpc"]
  }
}

data "aws_lb" "this" {
  name = "unicorn-alb"
}

data "aws_lb_target_group" "book" {
  name = "unicorn-tg"
}

data "aws_lb_target_group" "grafana" {
  name = "unicorn-grafana-tg"
}