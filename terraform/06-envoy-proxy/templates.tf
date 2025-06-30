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
