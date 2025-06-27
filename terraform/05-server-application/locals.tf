locals {
  # Project Configuration
  project_name = "envoy-poc"
  environment  = "dev"
  
  # Application Configuration
  app_name        = "envoy-poc-app-server"
  app_version     = "1.0.0"
  container_port  = 8080
  health_port     = 8081
  replicas        = 5
  
  # ECR Configuration
  ecr_repository_name = "cfndev-envoy-proxy-poc-app"
  image_tag          = "latest"
  
  # EKS Configuration
  cluster_name = "envoy-poc"
  namespace    = "default"
  
  # Service Configuration
  service_name = "envoy-poc-app-server-service"
  service_port = 80
  
  # Resource Limits (from requirements)
  cpu_request    = "50m"
  memory_request = "64Mi"
  cpu_limit      = "100m"
  memory_limit   = "128Mi"
  
  # AWS Configuration
  aws_region  = "us-west-2"
  aws_profile = "avive-cfndev-k8s"
  
  # Common Tags
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    Application = local.app_name
    ManagedBy   = "terraform"
    Purpose     = "envoy-proxy-poc"
    Section     = "05-server-application"
  }
}
