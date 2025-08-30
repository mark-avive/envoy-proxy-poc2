# Envoy Proxy Deployment with Atomic Connection Tracking
# Uses direct Redis connections for atomic state management

resource "kubernetes_config_map" "envoy_lua_scripts" {
  metadata {
    name      = "envoy-lua-scripts-atomic"
    namespace = local.namespace
    labels    = local.common_tags
  }
  
  data = {
    "redis-connection-tracker-native.lua" = file("${path.module}/k8s/redis-connection-tracker-native.lua")
    "test-lua-simple.lua" = file("${path.module}/k8s/test-lua-simple.lua")
  }
}

resource "kubernetes_config_map" "envoy_config" {
  metadata {
    name      = "envoy-config-atomic"
    namespace = local.namespace
    labels    = local.common_tags
  }
  
  data = {
    "envoy.yaml" = templatefile("${path.module}/k8s/envoy-config.yaml", {
      backend_service_name = local.backend_service_name
      redis_service_name   = local.redis_service_name
      max_connections_per_pod = local.max_connections_per_pod
      rate_limit_requests_per_minute = local.rate_limit_requests_per_minute
    })
  }
}

resource "kubernetes_deployment" "envoy_proxy" {
  metadata {
    name      = "envoy-proxy-atomic"
    namespace = local.namespace
    labels    = local.common_tags
  }
  
  spec {
    replicas = local.envoy_replicas
    
    selector {
      match_labels = {
        app = "envoy-proxy-atomic"
      }
    }
    
    template {
      metadata {
        labels = merge(local.common_tags, {
          app = "envoy-proxy-atomic"
        })
      }
      
      spec {
        container {
          name  = "envoy"
          image = local.envoy_image
          
          port {
            name           = "admin"
            container_port = 9901
            protocol       = "TCP"
          }
          
          port {
            name           = "proxy"
            container_port = 10000
            protocol       = "TCP"
          }
          
          port {
            name           = "redis"
            container_port = 6380
            protocol       = "TCP"
          }
          
          volume_mount {
            name       = "envoy-config"
            mount_path = "/etc/envoy"
            read_only  = true
          }
          
          volume_mount {
            name       = "lua-scripts"
            mount_path = "/etc/envoy/lua"
            read_only  = true
          }
          
          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          
          env {
            name = "HOSTNAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          
          resources {
            requests = {
              cpu    = local.envoy_cpu_request
              memory = local.envoy_memory_request
            }
            limits = {
              cpu    = local.envoy_cpu_limit
              memory = local.envoy_memory_limit
            }
          }
          
          liveness_probe {
            http_get {
              path = "/ready"
              port = 9901
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          
          readiness_probe {
            http_get {
              path = "/ready"
              port = 9901
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
        
        volume {
          name = "envoy-config"
          config_map {
            name = kubernetes_config_map.envoy_config.metadata[0].name
          }
        }
        
        volume {
          name = "lua-scripts"
          config_map {
            name = kubernetes_config_map.envoy_lua_scripts.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "envoy_proxy" {
  metadata {
    name      = local.envoy_service_name
    namespace = local.namespace
    labels    = local.common_tags
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
    }
  }
  
  spec {
    type = "LoadBalancer"
    
    port {
      name        = "proxy"
      port        = 80
      target_port = 10000
      protocol    = "TCP"
    }
    
    port {
      name        = "admin"
      port        = 9901
      target_port = 9901
      protocol    = "TCP"
    }
    
    port {
      name        = "redis"
      port        = 6380
      target_port = 6380
      protocol    = "TCP"
    }
    
    selector = {
      app = "envoy-proxy-atomic"
    }
  }
}
