resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "unicorn-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "unicorn-igw" })
}

locals {
  az_suffixes = ["a", "b", "c"]
}

resource "aws_subnet" "public" {
  for_each = { for idx, suffix in local.az_suffixes : suffix => idx }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[each.value]
  availability_zone       = var.azs[each.value]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "unicorn-subnet-pub-${each.key}" })
}

resource "aws_subnet" "private" {
  for_each = { for idx, suffix in local.az_suffixes : suffix => idx }

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[each.value]
  availability_zone = var.azs[each.value]

  tags = merge(local.common_tags, { Name = "unicorn-subnet-priv-${each.key}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "unicorn-rt-pub" })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = local.az_suffixes_map
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "unicorn-eip-nat-${each.key}" })
}

locals {
  az_suffixes_map = { for idx, suffix in local.az_suffixes : suffix => idx }
}

resource "aws_nat_gateway" "this" {
  for_each = local.az_suffixes_map

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.common_tags, { Name = "unicorn-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  for_each = local.az_suffixes_map

  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "unicorn-rt-priv-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = local.az_suffixes_map

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/unicorn/vpc/flow-log"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform_replica.arn
  tags              = local.common_tags
}

data "aws_iam_policy_document" "flow_log_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_log" {
  name               = "unicorn-vpc-flow-log-role"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "flow_log_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_log.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "unicorn-vpc-flow-log-policy"
  role   = aws_iam_role.flow_log.id
  policy = data.aws_iam_policy_document.flow_log_policy.json
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_log.arn
  iam_role_arn         = aws_iam_role.flow_log.arn

  tags = merge(local.common_tags, { Name = "unicorn-vpc-flow-log" })
}
