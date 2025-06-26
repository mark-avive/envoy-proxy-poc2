# Data sources for remote state
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "02-networking/terraform.tfstate"
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

data "terraform_remote_state" "ecr" {
  backend = "s3"
  config = {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "04-ecr-repositories/terraform.tfstate"
    region  = local.aws_region
    profile = local.aws_profile
  }
}

data "terraform_remote_state" "server_app" {
  backend = "s3"
  config = {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "05-server-application/terraform.tfstate"
    region  = local.aws_region
    profile = local.aws_profile
  }
}

data "terraform_remote_state" "envoy_proxy" {
  backend = "s3"
  config = {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "06-envoy-proxy/terraform.tfstate"
    region  = local.aws_region
    profile = local.aws_profile
  }
}

# AWS data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# EKS cluster data
data "aws_eks_cluster" "cluster" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = local.cluster_name
}
