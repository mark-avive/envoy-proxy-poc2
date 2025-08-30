locals {
  # Project Configuration
  project_name = "envoy-poc-atomic"
  environment  = "dev"
  
  # AWS Configuration
  aws_region   = "us-west-2"
  aws_profile  = "avive-cfndev-k8s"
  
  # EKS Configuration
  cluster_name = "envoy-poc"
  namespace    = "default"
  
  # Envoy Configuration
  envoy_replicas = 2
  envoy_image    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${local.aws_region}.amazonaws.com/cfndev-envoy-proxy-poc-envoy:latest"
  
  # Connection Limits (from requirements)
  max_connections_per_pod = 2
  rate_limit_requests_per_minute = 60  # 1 per second = 60 per minute
  
  # Service Names (reference from data sources where available)
  envoy_service_name = "envoy-proxy-atomic-service"
  backend_service_name = try(data.terraform_remote_state.server_app.outputs.service_name, "envoy-poc-app-server-service")
  redis_service_name = "redis-atomic-service"
  
  # Redis Configuration
  redis_replicas = 1
  redis_memory_limit = "256Mi"
  redis_cpu_limit = "200m"
  
  # Resource Limits
  envoy_cpu_request = "125m"
  envoy_memory_request = "128Mi"
  envoy_cpu_limit = "250m"
  envoy_memory_limit = "256Mi"
  
  # Common Tags
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Purpose     = "envoy-proxy-atomic-poc"
    Section     = "06a-envoy-proxy"
  }
}
