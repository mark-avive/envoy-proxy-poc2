# ECR Repository Outputs
output "app_repository_name" {
  description = "Name of the ECR repository for server application"
  value       = aws_ecr_repository.envoy_poc_app_repository.name
}

output "app_repository_url" {
  description = "URL of the ECR repository for server application"
  value       = aws_ecr_repository.envoy_poc_app_repository.repository_url
}

output "app_repository_arn" {
  description = "ARN of the ECR repository for server application"
  value       = aws_ecr_repository.envoy_poc_app_repository.arn
}

output "client_repository_name" {
  description = "Name of the ECR repository for client application"
  value       = aws_ecr_repository.envoy_poc_client_repository.name
}

output "client_repository_url" {
  description = "URL of the ECR repository for client application"
  value       = aws_ecr_repository.envoy_poc_client_repository.repository_url
}

output "client_repository_arn" {
  description = "ARN of the ECR repository for client application"  
  value       = aws_ecr_repository.envoy_poc_client_repository.arn
}

# Registry Information
output "registry_id" {
  description = "Registry ID where the repositories were created"
  value       = aws_ecr_repository.envoy_poc_app_repository.registry_id
}

output "registry_url" {
  description = "URL of the ECR registry"
  value       = "${aws_ecr_repository.envoy_poc_app_repository.registry_id}.dkr.ecr.${local.aws_region}.amazonaws.com"
}

# Docker Commands
output "docker_login_command" {
  description = "Command to login to ECR with Docker"
  value       = "aws ecr get-login-password --region ${local.aws_region} --profile ${local.aws_profile} | docker login --username AWS --password-stdin ${aws_ecr_repository.envoy_poc_app_repository.registry_id}.dkr.ecr.${local.aws_region}.amazonaws.com"
}

output "app_docker_build_command" {
  description = "Example Docker build command for server application"
  value       = "docker build -t ${aws_ecr_repository.envoy_poc_app_repository.repository_url}:latest ."
}

output "client_docker_build_command" {
  description = "Example Docker build command for client application"
  value       = "docker build -t ${aws_ecr_repository.envoy_poc_client_repository.repository_url}:latest ."
}

output "app_docker_push_command" {
  description = "Example Docker push command for server application"
  value       = "docker push ${aws_ecr_repository.envoy_poc_app_repository.repository_url}:latest"
}

output "client_docker_push_command" {
  description = "Example Docker push command for client application"
  value       = "docker push ${aws_ecr_repository.envoy_poc_client_repository.repository_url}:latest"
}

# Repository Configuration
output "repositories_config" {
  description = "ECR repositories configuration summary"
  value = {
    app_repository = {
      name                 = aws_ecr_repository.envoy_poc_app_repository.name
      url                  = aws_ecr_repository.envoy_poc_app_repository.repository_url
      image_tag_mutability = aws_ecr_repository.envoy_poc_app_repository.image_tag_mutability
    }
    client_repository = {
      name                 = aws_ecr_repository.envoy_poc_client_repository.name
      url                  = aws_ecr_repository.envoy_poc_client_repository.repository_url
      image_tag_mutability = aws_ecr_repository.envoy_poc_client_repository.image_tag_mutability
    }
    registry = {
      id     = aws_ecr_repository.envoy_poc_app_repository.registry_id
      region = local.aws_region
      url    = "${aws_ecr_repository.envoy_poc_app_repository.registry_id}.dkr.ecr.${local.aws_region}.amazonaws.com"
    }
  }
}
