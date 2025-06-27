# Generate Envoy configuration from template
resource "local_file" "envoy_config" {
  content = templatefile("${path.module}/k8s/envoy-config.yaml.tpl", {
    max_tokens             = local.max_tokens
    tokens_per_fill        = local.tokens_per_fill
    fill_interval          = local.fill_interval
    max_connections        = local.max_connections
    max_pending_requests   = local.max_pending_requests
    max_requests           = local.max_requests
    max_retries           = local.max_retries
  })
  filename = "${path.module}/k8s/envoy-config.yaml"
}
