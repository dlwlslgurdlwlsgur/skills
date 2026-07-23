resource "aws_ecr_repository" "product" {
  name                 = "${var.project_name}-product"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "stress" {
  name                 = "${var.project_name}-stress"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "user" {
  name                 = "${var.project_name}-user"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}