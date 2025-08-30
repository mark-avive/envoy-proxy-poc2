# Redis Service for Atomic Connection Tracking
# Provides direct Redis connectivity for Envoy Lua scripts

resource "kubernetes_deployment" "redis" {
  metadata {
    name      = "redis-atomic"
    namespace = local.namespace
    labels    = local.common_tags
  }
  
  spec {
    replicas = local.redis_replicas
    
    selector {
      match_labels = {
        app = "redis-atomic"
      }
    }
    
    template {
      metadata {
        labels = merge(local.common_tags, {
          app = "redis-atomic"
        })
      }
      
      spec {
        container {
          name  = "redis"
          image = "redis:7-alpine"
          
          port {
            name           = "redis"
            container_port = 6379
            protocol       = "TCP"
          }
          
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = local.redis_cpu_limit
              memory = local.redis_memory_limit
            }
          }
          
          # Basic Redis configuration for development
          command = [
            "redis-server",
            "--maxmemory", "200mb",
            "--maxmemory-policy", "allkeys-lru",
            "--save", "",  # Disable persistence for this POC
            "--appendonly", "no"
          ]
          
          liveness_probe {
            tcp_socket {
              port = 6379
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          
          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = local.redis_service_name
    namespace = local.namespace
    labels    = local.common_tags
  }
  
  spec {
    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
      protocol    = "TCP"
    }
    
    selector = {
      app = "redis-atomic"
    }
  }
}
