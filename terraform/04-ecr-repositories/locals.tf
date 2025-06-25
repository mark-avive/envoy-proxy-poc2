locals {
  # Project Configuration
  project_name = "envoy-poc"
  environment  = "dev"
  
  # ECR Repository Configuration
  app_repository_name    = "cfndev-envoy-proxy-poc-app"
  client_repository_name = "cfndev-envoy-proxy-poc-client"
  
  # Repository Settings
  image_tag_mutability = "MUTABLE"
  scan_on_push        = true
  lifecycle_policy_days = 30  # Keep images for 30 days
  
  # AWS Region and Profile
  aws_region  = "us-west-2"
  aws_profile = "avive-cfndev-k8s"
  
  # Common Tags
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Purpose     = "envoy-proxy-poc"
    Section     = "04-ecr-repositories"
  }
}
