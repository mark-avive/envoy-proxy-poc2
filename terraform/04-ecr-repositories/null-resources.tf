# Null resource to perform ECR login after repositories are created
resource "null_resource" "ecr_login" {
  depends_on = [
    aws_ecr_repository.envoy_poc_app_repository,
    aws_ecr_repository.envoy_poc_client_repository
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/ecr-login.sh ${local.aws_region} ${local.aws_profile}"
  }

  # Trigger re-run if repositories change
  triggers = {
    app_repository_uri    = aws_ecr_repository.envoy_poc_app_repository.repository_url
    client_repository_uri = aws_ecr_repository.envoy_poc_client_repository.repository_url
    timestamp            = timestamp()
  }
}

# Null resource to check ECR repository status
resource "null_resource" "ecr_status_check" {
  depends_on = [
    aws_ecr_repository.envoy_poc_app_repository,
    aws_ecr_repository.envoy_poc_client_repository,
    null_resource.ecr_login
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/ecr-status.sh ${local.aws_region} ${local.aws_profile} ${local.app_repository_name} ${local.client_repository_name}"
  }

  # Always run status check
  triggers = {
    always_run = timestamp()
  }
}

# Null resource for ECR cleanup (runs on destroy)
resource "null_resource" "ecr_cleanup" {
  provisioner "local-exec" {
    when    = destroy
    command = "CLEANUP_MODE=true ${path.module}/scripts/ecr-cleanup.sh us-west-2 avive-cfndev-k8s cfndev-envoy-proxy-poc-app cfndev-envoy-proxy-poc-client"
    
    # Use hardcoded environment variables for destroy-time
    environment = {
      AWS_REGION  = "us-west-2"
      AWS_PROFILE = "avive-cfndev-k8s"
    }
  }

  # Trigger cleanup when repositories are destroyed
  triggers = {
    app_repository_name    = local.app_repository_name
    client_repository_name = local.client_repository_name
  }
}
