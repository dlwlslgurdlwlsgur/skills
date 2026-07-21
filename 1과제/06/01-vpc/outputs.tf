output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static.bucket
}

output "ecr_repository_url" {
  value = aws_ecr_repository.book.repository_url
}

output "eks_cluster_name" {
  value = aws_eks_cluster.this.name
}
