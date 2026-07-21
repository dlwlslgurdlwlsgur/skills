# 요구사항 3: "App이 구동되는 Subnet은 컨테이너 이미지 다운로드 및 로그/메트릭 export 시
# 외부 인터넷을 경유하지 않아야 합니다." NAT는 일반 아웃바운드용이고, ECR/CloudWatch Logs/Metrics
# 트래픽은 VPC 엔드포인트로만 흐르도록 인터페이스/게이트웨이 엔드포인트를 별도로 둔다.

resource "aws_security_group" "vpc_endpoints" {
  name        = "unicorn-vpce-sg"
  description = "Allow HTTPS from within the VPC to interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "unicorn-vpce-sg" })
}

locals {
  interface_endpoints = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "monitoring",
    "sts",
    "ec2",
    "elasticloadbalancing",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "unicorn-vpce-${each.key}" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]

  tags = merge(local.common_tags, { Name = "unicorn-vpce-s3" })
}
