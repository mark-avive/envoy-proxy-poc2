# AWS Load Balancer Controller Outputs
output "alb_controller_status" {
  description = "Status of the AWS Load Balancer Controller deployment"
  value       = helm_release.aws_load_balancer_controller.status
}

output "alb_controller_version" {
  description = "Version of the AWS Load Balancer Controller"
  value       = helm_release.aws_load_balancer_controller.version
}

# IAM Role Outputs
output "alb_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "alb_controller_service_account" {
  description = "Name of the Kubernetes service account for AWS Load Balancer Controller"
  value       = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
}

# Envoy Deployment Outputs
output "envoy_deployment_status" {
  description = "Status of Envoy proxy deployment"
  value       = null_resource.deploy_envoy.id
}

output "envoy_config_hash" {
  description = "Hash of the Envoy configuration"
  value       = sha256(file("${path.module}/k8s/deployment.yaml"))
}

# Service Information
output "envoy_service_name" {
  description = "Name of the Envoy proxy service"
  value       = local.envoy_service_name
}

output "backend_service_name" {
  description = "Name of the backend service"
  value       = local.backend_service_name
}

# ALB Endpoint for Client Applications
output "envoy_alb_endpoint" {
  description = "ALB endpoint for WebSocket connections"
  value       = data.kubernetes_ingress_v1.envoy_proxy_ingress.status[0].load_balancer[0].ingress[0].hostname
  depends_on  = [null_resource.deploy_envoy]
}

output "envoy_websocket_endpoint" {
  description = "Complete WebSocket endpoint URL for client applications"
  value       = "ws://${data.kubernetes_ingress_v1.envoy_proxy_ingress.status[0].load_balancer[0].ingress[0].hostname}:80"
  depends_on  = [null_resource.deploy_envoy]
}

# Deployment Configuration
output "envoy_replicas" {
  description = "Number of Envoy proxy replicas"
  value       = local.envoy_replicas
}

output "envoy_image" {
  description = "Envoy proxy image used"
  value       = local.envoy_image
}

# Rate Limiting Configuration
output "connection_limits" {
  description = "Connection limiting configuration"
  value = {
    max_connections_per_pod = local.max_connections_per_pod
    rate_limit_requests_per_minute = local.rate_limit_requests_per_minute
  }
}

# Instructions for accessing services
output "access_instructions" {
  description = "Instructions for accessing the deployed services"
  value = <<-EOT
  
  Envoy Proxy has been deployed to your EKS cluster.
  
  To access the services:
  
  1. Get ALB endpoint:
     kubectl get ingress envoy-proxy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
  
  2. Test WebSocket connection:
     Use the ALB endpoint with ws:// protocol
  
  3. Monitor Envoy admin interface:
     kubectl port-forward deployment/envoy-proxy 9901:9901
     Then access: http://localhost:9901
  
  4. Check Envoy logs:
     kubectl logs -l app=envoy-proxy
  
  5. Check deployment status:
     kubectl get all -l app=envoy-proxy
  
  EOT
}
