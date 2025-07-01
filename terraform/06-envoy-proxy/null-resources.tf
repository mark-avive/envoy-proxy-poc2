# Deploy Envoy Proxy to Kubernetes
resource "null_resource" "deploy_envoy" {
  depends_on = [
    helm_release.aws_load_balancer_controller,
    data.terraform_remote_state.server_app,
    local_file.envoy_config,
    local_file.envoy_deployment
  ]

  triggers = {
    envoy_config_hash = local_file.envoy_config.content_md5
    envoy_deployment_hash = local_file.envoy_deployment.content_md5
    alb_controller_deployed = helm_release.aws_load_balancer_controller.status
    locals_hash = sha256(jsonencode({
      max_connections = local.max_connections
      max_tokens = local.max_tokens
      tokens_per_fill = local.tokens_per_fill
      envoy_image = local.envoy_image
      redis_service_name = local.redis_service_name
    }))
  }

  provisioner "local-exec" {
    command = "./scripts/deploy-envoy.sh"
    working_dir = path.module
  }

  provisioner "local-exec" {
    when    = destroy
    command = "./scripts/cleanup-envoy.sh"
    working_dir = path.module
  }
}

# Wait for ALB to be provisioned and get endpoint
resource "null_resource" "wait_for_alb" {
  depends_on = [null_resource.deploy_envoy]

  triggers = {
    deployment_hash = null_resource.deploy_envoy.id
  }

  provisioner "local-exec" {
    command = "./scripts/wait-for-alb.sh"
    working_dir = path.module
  }
}

# Status check for Envoy deployment
resource "null_resource" "envoy_status_check" {
  depends_on = [null_resource.wait_for_alb]

  triggers = {
    alb_ready = null_resource.wait_for_alb.id
  }

  provisioner "local-exec" {
    command = "./scripts/status-check.sh"
    working_dir = path.module
  }
}
