# Outputs for Server Application section

# Application Information
output "application_name" {
  description = "Name of the deployed application"
  value       = local.app_name
}

output "application_version" {
  description = "Version of the deployed application"
  value       = local.app_version
}

output "application_image" {
  description = "Full Docker image URL used for deployment"
  value       = "${data.terraform_remote_state.ecr.outputs.app_repository_url}:${local.image_tag}"
}

# Kubernetes Deployment Information
output "deployment_name" {
  description = "Name of the Kubernetes deployment"
  value       = "${local.project_name}-${local.app_name}-deployment"
}

output "service_name" {
  description = "Name of the Kubernetes service"
  value       = local.service_name
}

output "namespace" {
  description = "Kubernetes namespace where the application is deployed"
  value       = local.namespace
}

output "replicas" {
  description = "Number of application replicas"
  value       = local.replicas
}

output "container_port" {
  description = "Port exposed by the application container"
  value       = local.container_port
}

output "service_port" {
  description = "Port exposed by the Kubernetes service"
  value       = local.service_port
}

# Resource Configuration
output "resource_limits" {
  description = "Resource limits and requests configured for the application"
  value = {
    cpu_request    = local.cpu_request
    memory_request = local.memory_request
    cpu_limit      = local.cpu_limit
    memory_limit   = local.memory_limit
  }
}

# EKS Cluster Information (from remote state)
output "cluster_name" {
  description = "Name of the EKS cluster where the application is deployed"
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = data.aws_eks_cluster.cluster.endpoint
}

output "cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = data.aws_eks_cluster.cluster.version
}

# ECR Repository Information (from remote state)
output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = local.ecr_repository_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = data.terraform_remote_state.ecr.outputs.app_repository_url
}

# Deployment Status
output "build_status" {
  description = "Status of the Docker build and push operation"
  value       = "Build and push completed: ${null_resource.build_and_push.id}"
}

output "deployment_status" {
  description = "Status of the Kubernetes deployment"
  value       = "Deployment completed: ${null_resource.deploy_k8s.id}"
}

# Commands for manual operations
output "kubectl_commands" {
  description = "Useful kubectl commands for managing the deployment"
  value = {
    get_pods     = "kubectl get pods -l app=${local.app_name}"
    get_service  = "kubectl get service ${local.service_name}"
    describe_deployment = "kubectl describe deployment ${local.project_name}-${local.app_name}-deployment"
    logs         = "kubectl logs -l app=${local.app_name}"
    port_forward = "kubectl port-forward service/${local.service_name} 8080:${local.service_port}"
  }
}

# Scripts for manual execution
output "management_scripts" {
  description = "Available management scripts"
  value = {
    build_and_push = "./scripts/build-and-push.sh ${local.aws_region} ${local.aws_profile} ${local.ecr_repository_name} ${local.image_tag}"
    deploy_k8s     = "./scripts/deploy-k8s.sh ${local.aws_region} ${local.aws_profile} ${local.cluster_name} ${local.ecr_repository_name} ${local.image_tag}"
    status_check   = "./scripts/status-check.sh ${local.aws_region} ${local.aws_profile} ${local.cluster_name}"
  }
}
