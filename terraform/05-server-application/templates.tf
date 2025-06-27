# Generate deployment manifest from template
resource "local_file" "deployment_manifest" {
  content = templatefile("${path.module}/k8s/deployment.yaml.tpl", {
    app_name           = local.app_name
    app_version        = local.app_version
    namespace          = local.namespace
    replicas           = local.replicas
    ecr_repository_url = data.terraform_remote_state.ecr.outputs.app_repository_url
    image_tag          = local.image_tag
    container_port     = local.container_port
    health_port        = local.health_port
    service_name       = local.service_name
    service_port       = local.service_port
    cpu_request        = local.cpu_request
    memory_request     = local.memory_request
    cpu_limit          = local.cpu_limit
    memory_limit       = local.memory_limit
  })
  filename = "${path.module}/k8s/deployment.yaml"
}
