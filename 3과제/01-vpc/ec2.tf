# 1. 최신 Amazon Linux 2023 AMI 자동 검색
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 2. Any Open 보안 그룹 생성 (모든 인바운드/아웃바운드 허용)
resource "aws_security_group" "ec2_anyopen" {
  name        = "${var.project_name}-ec2-anyopen-sg"
  description = "Allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.main.id # network.tf에 있는 VPC 자동 참조

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1은 모든 프로토콜을 의미
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-anyopen-sg"
  }
}

# 3. EC2가 사용할 IAM 역할(Role) 생성 (이름을 admin으로 변경)
resource "aws_iam_role" "ec2_admin_role" {
  name = "${var.project_name}-bastion-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# 4. AWS 관리형 정책인 AdministratorAccess 연결
resource "aws_iam_role_policy_attachment" "ec2_admin_attach" {
  role       = aws_iam_role.ec2_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 5. 역할을 EC2에 붙이기 위한 인스턴스 프로파일 생성
resource "aws_iam_instance_profile" "ec2_admin_profile" {
  name = "${var.project_name}-bastion-profile"
  role = aws_iam_role.ec2_admin_role.name
}

# 6. Bastion EC2 인스턴스 생성
resource "aws_instance" "main_ec2" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public[0].id # 퍼블릭 서브넷 1번에 배치
  vpc_security_group_ids      = [aws_security_group.ec2_anyopen.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_admin_profile.name
  associate_public_ip_address = true

  # 사용자 데이터(User Data)를 통한 초기 스크립트 실행
  user_data = <<-EOF
              #!/bin/bash
              sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
              echo "ec2-user:1234" | chpasswd
              systemctl restart sshd
              EOF

  tags = {
    Name = "${var.project_name}-bastion"
  }
}