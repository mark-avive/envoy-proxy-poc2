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
  
  # Rate Limiting Configuration - RELAXED for testing
  max_connections_per_pod = 100  # Increased for testing
  connection_rate_limit = "1/s"  # 1 connection per second
  
  # Rate Limiting Token Bucket Settings - For WebSocket connection establishment rate only
  max_tokens      = 50    # Allow burst of 50 new connections
  tokens_per_fill = 10    # 10 new connections per second
  fill_interval   = "1s"  # Token refill interval
  
  # Circuit Breaker Configuration - RELAXED for testing
  max_connections      = 100  # Increased for testing
  max_pending_requests = 50   # Increased queue limit for pending requests
  max_requests         = 200  # Increased active request limit
  max_retries          = 3    # Retry limit
  
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
