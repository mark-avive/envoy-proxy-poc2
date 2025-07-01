# Data sources for remote state from previous sections
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

data "terraform_remote_state" "server_app" {
  backend = "s3"
  config = {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "05-server-application/terraform.tfstate"
    region  = local.aws_region
    profile = local.aws_profile
  }
}

# AWS caller identity for ECR repository URL
data "aws_caller_identity" "current" {}

# EKS cluster data
data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

# AWS Region data
data "aws_region" "current" {}

# Get server service endpoints for validation
data "kubernetes_endpoints_v1" "server_endpoints" {
  metadata {
    name      = local.backend_service_name
    namespace = local.namespace
  }
  
  depends_on = [data.terraform_remote_state.server_app]
}
