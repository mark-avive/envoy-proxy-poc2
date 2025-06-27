locals {
  # Project Configuration
  project_name = "envoy-poc"
  environment  = "dev"
  
  # Envoy Configuration
  envoy_replicas = 2
  envoy_image    = "envoyproxy/envoy:v1.29-latest"  # Use latest stable Envoy
  
  # AWS Load Balancer Controller Configuration
  alb_controller_version = "1.7.2"
  alb_controller_chart_version = "1.7.2"
  
  # AWS Region and Profile
  aws_region  = "us-west-2"
  aws_profile = "avive-cfndev-k8s"
  
  # Kubernetes Configuration
  namespace = "default"
  
  # Service Names
  envoy_service_name = "envoy-proxy-service"
  backend_service_name = "envoy-poc-app-server-service"
  
  # Rate Limiting Configuration
  max_connections_per_pod = 2
  connection_rate_limit = "1/s"  # 1 connection per second
  
  # Rate Limiting Token Bucket Settings
  max_tokens      = 10    # Maximum tokens in bucket
  tokens_per_fill = 1     # Tokens added per interval  
  fill_interval   = "1s"  # Token refill interval
  
  # Circuit Breaker Configuration
  max_connections      = 10   # 5 backend pods * 2 connections per pod
  max_pending_requests = 10   # Queue limit for pending requests
  max_requests         = 20   # Active request limit
  max_retries          = 3    # Retry limit
  
  # Common Tags
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Purpose     = "envoy-proxy-poc"
    Section     = "06-envoy-proxy"
  }
}
