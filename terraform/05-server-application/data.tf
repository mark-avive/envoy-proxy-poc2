# Data sources to reference other sections
data "terraform_remote_state" "ecr" {
  backend = "s3"
  config = {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "04-ecr-repositories/terraform.tfstate"
    region  = local.aws_region
    profile = local.aws_profile
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "03-eks-cluster/terraform.tfstate"
    region  = local.aws_region
    profile = local.aws_profile
  }
}

# EKS cluster data for kubectl provider
data "aws_eks_cluster" "cluster" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = local.cluster_name
}
