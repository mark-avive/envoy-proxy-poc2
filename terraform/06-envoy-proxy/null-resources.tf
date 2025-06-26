# Deploy Envoy Proxy to Kubernetes
resource "null_resource" "deploy_envoy" {
  depends_on = [
    helm_release.aws_load_balancer_controller,
    data.terraform_remote_state.server_app
  ]

  triggers = {
    envoy_config_hash = sha256(file("${path.module}/k8s/deployment.yaml"))
    alb_controller_deployed = helm_release.aws_load_balancer_controller.status
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
