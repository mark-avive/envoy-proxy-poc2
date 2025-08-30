output "envoy_service_name" {
  description = "Name of the Envoy proxy service"
  value       = kubernetes_service.envoy_proxy.metadata[0].name
}

output "envoy_load_balancer_ingress" {
  description = "Load balancer ingress for Envoy proxy service"
  value       = kubernetes_service.envoy_proxy.status[0].load_balancer[0].ingress
}

output "redis_service_name" {
  description = "Name of the Redis service"
  value       = kubernetes_service.redis.metadata[0].name
}

output "envoy_deployment_name" {
  description = "Name of the Envoy deployment"
  value       = kubernetes_deployment.envoy_proxy.metadata[0].name
}

output "redis_deployment_name" {
  description = "Name of the Redis deployment"
  value       = kubernetes_deployment.redis.metadata[0].name
}

output "envoy_admin_url" {
  description = "URL for Envoy admin interface (via load balancer)"
  value       = "http://${try(kubernetes_service.envoy_proxy.status[0].load_balancer[0].ingress[0].hostname, "pending")}:9901"
}

output "envoy_proxy_url" {
  description = "URL for Envoy proxy (via load balancer)"
  value       = "http://${try(kubernetes_service.envoy_proxy.status[0].load_balancer[0].ingress[0].hostname, "pending")}"
}

output "envoy_websocket_endpoint" {
  description = "Complete WebSocket endpoint URL for client applications"
  value       = "ws://${try(kubernetes_service.envoy_proxy.status[0].load_balancer[0].ingress[0].hostname, "pending")}:80"
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = local.namespace
}
