# Data sources to reference networking resources from Section 2
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket  = "cfndev-envoy-proxy-poc-terraform-state"
    key     = "02-networking/terraform.tfstate"
    region  = local.aws_region
    profile = local.aws_profile
  }
}
