terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
  
  backend "s3" {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "04-ecr-repositories/terraform.tfstate"
    region  = "us-west-2"
    profile = "avive-cfndev-k8s"
  }
}

provider "aws" {
  region  = local.aws_region
  profile = local.aws_profile
  
  default_tags {
    tags = local.common_tags
  }
}
