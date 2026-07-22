data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "unicorn-alb-sg"
  description = "Internal ALB - only reachable via CloudFront VPC Origin"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "CloudFront VPC Origin"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "unicorn-alb-sg" })
}

resource "aws_lb" "this" {
  name               = "unicorn-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id, aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]
  subnets            = [for s in aws_subnet.private : s.id]

  tags = merge(local.common_tags, { Name = "unicorn-alb" })
}

resource "aws_lb_target_group" "book" {
  name        = "unicorn-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, { Name = "unicorn-tg" })
}

resource "aws_lb_target_group" "lambda" {
  name        = "unicorn-tg-lambda"
  target_type = "lambda"

  tags = merge(local.common_tags, { Name = "unicorn-tg-lambda" })
}

resource "aws_lambda_permission" "alb_invoke" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_booking.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.get_booking.arn

  depends_on = [aws_lambda_permission.alb_invoke]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }
}

resource "aws_lb_listener_rule" "health" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    http_request_method {
      values = ["GET"]
    }
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

resource "aws_lb_listener_rule" "post_to_book" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.book.arn
  }

  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}

resource "aws_security_group" "grafana_alb" {
  name        = "unicorn-grafana-alb-sg"
  description = "Internet-facing ALB for Grafana"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "unicorn-grafana-alb-sg" })
}

resource "aws_lb" "grafana" {
  name               = "unicorn-grafana-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.grafana_alb.id, aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = merge(local.common_tags, { Name = "unicorn-grafana-alb" })
}

resource "aws_lb_target_group" "grafana" {
  name        = "unicorn-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path                = "/api/health"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, { Name = "unicorn-grafana-tg" })
}

resource "aws_lb_listener" "grafana_http" {
  load_balancer_arn = aws_lb.grafana.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}
