output "client_application_status" {
  description = "Status of the client application deployment"
  value       = "deployed"
  depends_on  = [null_resource.check_deployment_status]
}

output "client_image_uri" {
  description = "URI of the client application Docker image"
  value       = "${data.terraform_remote_state.ecr.outputs.client_repository_url}:${local.image_tag}"
}

output "client_service_name" {
  description = "Name of the client application Kubernetes service"
  value       = local.service_name
}

output "client_replicas" {
  description = "Number of client application replicas"
  value       = local.replicas
}

output "envoy_endpoint" {
  description = "Envoy endpoint that clients connect to"
  value       = "ws://envoy-proxy-service.default.svc.cluster.local:80"
}

output "access_instructions" {
  description = "Instructions for accessing and monitoring the client application"
  value = <<-EOT
    Client Application has been deployed to your EKS cluster.
    
    Monitoring commands:
    
    1. Check client pod status:
       kubectl get pods -l app=envoy-poc-client-app
    
    2. View client logs:
       kubectl logs -l app=envoy-poc-client-app -f
    
    3. Check service status:
       kubectl get service ${local.service_name}
    
    4. Monitor WebSocket connections:
       kubectl logs -l app=envoy-poc-client-app | grep "Connection"
    
    5. Monitor message exchanges:
       kubectl logs -l app=envoy-poc-client-app | grep "Response from server"
    
    6. Check resource usage:
       kubectl top pods -l app=envoy-poc-client-app
    
    7. Describe client deployment:
       kubectl describe deployment envoy-poc-client-app
    
    Configuration:
    - Replicas: ${local.replicas}
    - Connections per pod: 5
    - Connection interval: 10 seconds
    - Message interval: 10-20 seconds
    - Target: ${data.terraform_remote_state.envoy_proxy.outputs.envoy_service_name}
  EOT
}
