# Generate client.py from template
resource "local_file" "client_py" {
  content = templatefile("${path.module}/app/client.py.tpl", {
    max_connections      = local.max_connections
    connection_interval  = local.connection_interval
    message_interval_min = local.message_interval_min
    message_interval_max = local.message_interval_max
  })
  filename = "${path.module}/app/client.py"
}

# Generate deployment.yaml from template
resource "local_file" "deployment_yaml" {
  content = templatefile("${path.module}/k8s/deployment.yaml.tpl", {
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
  })
  filename = "${path.module}/k8s/deployment.yaml"
}
