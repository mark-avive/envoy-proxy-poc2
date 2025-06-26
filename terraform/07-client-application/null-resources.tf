# Build and push Docker image
resource "null_resource" "build_and_push_client" {
  triggers = {
    dockerfile_hash = filemd5("${path.module}/app/Dockerfile")
    client_py_hash  = filemd5("${path.module}/app/client.py")
    requirements_hash = filemd5("${path.module}/app/requirements.txt")
    ecr_repository_url = data.terraform_remote_state.ecr.outputs.client_repository_url
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
    data.terraform_remote_state.ecr
  ]
}

# Deploy client application to Kubernetes
resource "null_resource" "deploy_client_app" {
  triggers = {
    deployment_hash = filemd5("${path.module}/k8s/deployment.yaml")
    image_pushed    = null_resource.build_and_push_client.id
    cluster_name    = local.cluster_name
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
    data.terraform_remote_state.envoy_proxy
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
