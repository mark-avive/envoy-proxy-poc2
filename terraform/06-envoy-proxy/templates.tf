# Generate Envoy configuration from template
resource "local_file" "envoy_config" {
  content = templatefile("${path.module}/k8s/envoy-config.yaml.tpl", {
    max_tokens               = local.max_tokens
    tokens_per_fill          = local.tokens_per_fill
    fill_interval            = local.fill_interval
    max_connections_per_pod  = local.max_connections_per_pod
    max_pending_requests     = local.max_pending_requests
    max_requests             = local.max_requests
    max_retries             = local.max_retries
    server_service_name     = local.server_service_name
    server_service_port     = local.server_service_port
    namespace               = local.namespace
  })
  filename = "${path.module}/k8s/envoy-config.yaml"
}

# Generate Envoy deployment from template with custom image and Redis config
resource "local_file" "envoy_deployment" {
  content = templatefile("${path.module}/k8s/deployment.yaml.tpl", {
    envoy_image                      = local.envoy_image
    envoy_replicas                   = local.envoy_replicas
    redis_service_name              = local.redis_service_name
    redis_port                      = local.redis_port
    namespace                       = local.namespace
    max_connections_per_pod         = local.max_connections_per_pod
    rate_limit_requests_per_minute  = local.rate_limit_requests_per_minute
    path                            = path.module
  })
  filename = "${path.module}/k8s/deployment.yaml"
}
