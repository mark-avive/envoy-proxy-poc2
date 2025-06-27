# Build and push Docker image
resource "null_resource" "build_and_push_client" {
  triggers = {
    dockerfile_hash       = filemd5("${path.module}/app/Dockerfile")
    client_py_tpl_hash    = filemd5("${path.module}/app/client.py.tpl")
    requirements_hash     = filemd5("${path.module}/app/requirements.txt")
    ecr_repository_url    = data.terraform_remote_state.ecr.outputs.client_repository_url
    client_py_generated   = local_file.client_py.id
    client_config_hash    = md5(jsonencode({
      max_connections      = local.max_connections
      connection_interval  = local.connection_interval
      message_interval_min = local.message_interval_min
      message_interval_max = local.message_interval_max
    }))
  }

  provisioner "local-exec" {
    command     = "./scripts/build-and-push.sh"
    working_dir = path.module
    environment = {
      AWS_REGION     = local.aws_region
      AWS_PROFILE    = local.aws_profile
      ECR_REPOSITORY = data.terraform_remote_state.ecr.outputs.client_repository_url
      IMAGE_TAG      = local.image_tag
    }
  }

  depends_on = [
    data.terraform_remote_state.ecr,
    local_file.client_py
  ]
}

# Deploy client application to Kubernetes
resource "null_resource" "deploy_client_app" {
  triggers = {
    deployment_tpl_hash    = filemd5("${path.module}/k8s/deployment.yaml.tpl")
    image_pushed           = null_resource.build_and_push_client.id
    cluster_name           = local.cluster_name
    deployment_generated   = local_file.deployment_yaml.id
    deployment_config_hash = md5(jsonencode({
      app_name             = local.app_name
      app_version          = local.app_version
      namespace            = local.namespace
      replicas             = local.replicas
      container_port       = local.container_port
      service_name         = local.service_name
      service_port         = local.service_port
      max_connections      = local.max_connections
      connection_interval  = local.connection_interval
      message_interval_min = local.message_interval_min
      message_interval_max = local.message_interval_max
      cpu_request          = local.cpu_request
      memory_request       = local.memory_request
      cpu_limit            = local.cpu_limit
      memory_limit         = local.memory_limit
    }))
  }

  provisioner "local-exec" {
    command     = "./scripts/deploy-k8s.sh"
    working_dir = path.module
    environment = {
      AWS_REGION     = local.aws_region
      AWS_PROFILE    = local.aws_profile
      CLUSTER_NAME   = local.cluster_name
      ECR_REPOSITORY = data.terraform_remote_state.ecr.outputs.client_repository_url
      IMAGE_TAG      = local.image_tag
      NAMESPACE      = local.namespace
      APP_NAME       = local.app_name
      REPLICAS       = local.replicas
    }
  }

  depends_on = [
    null_resource.build_and_push_client,
    data.terraform_remote_state.eks,
    data.terraform_remote_state.envoy_proxy,
    local_file.deployment_yaml
  ]
}

# Check deployment status
resource "null_resource" "check_deployment_status" {
  triggers = {
    deployment_ready = null_resource.deploy_client_app.id
  }

  provisioner "local-exec" {
    command     = "./scripts/status-check.sh"
    working_dir = path.module
    environment = {
      AWS_REGION   = local.aws_region
      AWS_PROFILE  = local.aws_profile
      CLUSTER_NAME = local.cluster_name
      NAMESPACE    = local.namespace
      APP_NAME     = local.app_name
    }
  }

  depends_on = [
    null_resource.deploy_client_app
  ]
}
