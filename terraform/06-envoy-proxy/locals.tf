locals {
  # Project Configuration
  project_name = var.project_name
  environment  = var.environment
  
  # Enhanced Envoy Configuration with Custom Image
  envoy_replicas = var.envoy_replicas
  
  # Custom Envoy image with lua-resty-redis support
  envoy_image = var.custom_envoy_image != "" ? var.custom_envoy_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/cfndev-envoy-proxy-poc-envoy:latest"
  
  # AWS Load Balancer Controller Configuration
  alb_controller_version = "1.7.2"
  alb_controller_chart_version = "1.7.2"
  
  # AWS Region and Profile
  aws_region  = var.aws_region
  aws_profile = var.aws_profile
  
  # Kubernetes Configuration
  namespace = var.namespace
  
  # Service Names
  envoy_service_name = "envoy-proxy-service"
  backend_service_name = "envoy-poc-app-server-service"
  
  # Enhanced Connection Management Configuration
  max_connections_per_pod = var.max_connections_per_pod
  rate_limit_requests_per_minute = var.rate_limit_requests_per_minute
  
  # Rate Limiting Token Bucket Settings - For WebSocket connection establishment rate only
  max_tokens      = 10    # Allow burst of 10 new connections 
  tokens_per_fill = 1     # Requirements: 1 new connection per second
  fill_interval   = "1s"  # Token refill interval
  
  # Circuit Breaker Configuration - AS PER REQUIREMENTS  
  max_connections      = var.max_connections_per_pod  # Requirements: max 2 connections per pod
  max_pending_requests = 5   # Small queue for pending requests
  max_requests         = 10  # Active request limit 
  max_retries          = 3   # Retry limit
  
  # Redis Configuration
  redis_service_name = var.redis_service_name
  redis_port = var.redis_port
  
  # Server Service Configuration for DNS Discovery
  server_service_name = "envoy-poc-app-server-service"
  server_service_port = 8080
  
  # Common Tags
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Purpose     = "envoy-proxy-poc"
    Section     = "06-envoy-proxy"
  }
}
