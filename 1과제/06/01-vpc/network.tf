resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "gj2026-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "gj2026-igw"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = var.azs[0]

  tags = {
    Name = "gj2026-private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = var.azs[1]

  tags = {
    Name = "gj2026-private-subnet-b"
  }
}

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "gj2026-private-rtb-a"
  }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "gj2026-private-rtb-b"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}
