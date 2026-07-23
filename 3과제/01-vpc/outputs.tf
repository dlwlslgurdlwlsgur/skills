output "cluster_id" {
  value = aws_eks_cluster.main.id
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_ca_cert" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "ecr_product_url" {
  value = aws_ecr_repository.product.repository_url
}

output "ecr_stress_url" {
  value = aws_ecr_repository.stress.repository_url
}

output "ecr_user_url" {
  value = aws_ecr_repository.user.repository_url
}