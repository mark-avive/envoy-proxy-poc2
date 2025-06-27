# Null resources for automating Docker build/push and Kubernetes deployment

# Build and push Docker image to ECR
resource "null_resource" "build_and_push" {
  # Trigger re-run when any of these change
  triggers = {
    dockerfile_hash    = filemd5("${path.module}/app/Dockerfile")
    server_py_hash     = filemd5("${path.module}/app/server.py")
    requirements_hash  = filemd5("${path.module}/app/requirements.txt")
    build_script_hash  = filemd5("${path.module}/scripts/build-and-push.sh")
    
    # Static values for reference
    ecr_repository     = local.ecr_repository_name
    image_tag         = local.image_tag
    aws_region        = local.aws_region
    aws_profile       = local.aws_profile
  }

  # Build and push the Docker image
  provisioner "local-exec" {
    command = "${path.module}/scripts/build-and-push.sh"
    environment = {
      AWS_REGION       = local.aws_region
      AWS_PROFILE      = local.aws_profile
      ECR_REPO_NAME    = local.ecr_repository_name
      IMAGE_TAG        = local.image_tag
    }
    working_dir = path.module
  }

  # Depends on ECR repository being available
  depends_on = [
    data.terraform_remote_state.ecr
  ]
}

# Deploy application to Kubernetes
resource "null_resource" "deploy_k8s" {
  # Trigger re-run when any of these change
  triggers = {
    deployment_yaml_hash = local_file.deployment_manifest.content_md5
    deploy_script_hash   = filemd5("${path.module}/scripts/deploy-k8s.sh")
    
    # Reference the build output to ensure proper ordering
    build_completed      = null_resource.build_and_push.id
    
    # Locals hash to trigger on configuration changes
    locals_hash = sha256(jsonencode({
      replicas     = local.replicas
      cpu_limit    = local.cpu_limit
      memory_limit = local.memory_limit
    }))
    
    # Static values for reference
    cluster_name         = local.cluster_name
    ecr_repository       = local.ecr_repository_name
    image_tag           = local.image_tag
    aws_region          = local.aws_region
    aws_profile         = local.aws_profile
  }

  # Deploy to Kubernetes
  provisioner "local-exec" {
    command = "${path.module}/scripts/deploy-k8s.sh"
    environment = {
      AWS_REGION       = local.aws_region
      AWS_PROFILE      = local.aws_profile
      CLUSTER_NAME     = local.cluster_name
      ECR_REPO_NAME    = local.ecr_repository_name
      IMAGE_TAG        = local.image_tag
    }
    working_dir = path.module
  }

  # Cleanup on destroy (undeploy from Kubernetes)
  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete -f k8s/deployment.yaml --ignore-not-found=true"
    on_failure = continue
  }

  # Depends on the build being completed and EKS cluster being available
  depends_on = [
    null_resource.build_and_push,
    data.terraform_remote_state.eks,
    data.aws_eks_cluster.cluster,
    local_file.deployment_manifest
  ]
}

# Status check resource (can be run manually or on changes)
resource "null_resource" "status_check" {
  # Trigger when deployment changes
  triggers = {
    deployment_completed = null_resource.deploy_k8s.id
  }

  # Check deployment status
  provisioner "local-exec" {
    command = "${path.module}/scripts/status-check.sh"
    environment = {
      AWS_REGION       = local.aws_region
      AWS_PROFILE      = local.aws_profile
      CLUSTER_NAME     = local.cluster_name
    }
    working_dir = path.module
  }

  depends_on = [
    null_resource.deploy_k8s
  ]
}
