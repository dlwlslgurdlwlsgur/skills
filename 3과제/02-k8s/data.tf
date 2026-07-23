data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../01-base/terraform.tfstate"
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.base.outputs.cluster_id
}