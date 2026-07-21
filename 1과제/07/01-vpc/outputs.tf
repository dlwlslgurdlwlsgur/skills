output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "grafana_alb_dns_name" {
  value = aws_lb.grafana.dns_name
}

output "unicorn_alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.web.bucket
}

output "ecr_repository_url" {
  value = aws_ecr_repository.book.repository_url
}

output "eks_cluster_name" {
  value = aws_eks_cluster.this.name
}

output "audit_role_external_id" {
  value = local.audit_role_external_id
}