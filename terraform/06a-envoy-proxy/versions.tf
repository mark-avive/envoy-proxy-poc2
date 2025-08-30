# Envoy Proxy with Direct Redis Connection - Clean Implementation
# Based on docs2/ atomic design patterns

terraform {
  required_version = ">= 1.5"
  
  backend "s3" {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "06a-envoy-proxy-atomic/terraform.tfstate"
    region  = "us-west-2"
    profile = "avive-cfndev-k8s"
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile
  
  default_tags {
    tags = local.common_tags
  }
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Helm Provider Configuration
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
