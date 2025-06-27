# ENVOY PROXY POC - QUICK REFERENCE

## 🚀 Essential Commands

### Setup Monitoring
```bash
# Required: Set up port-forward for Envoy admin access
kubectl port-forward svc/envoy-proxy-service 9901:9901

# Run monitoring (keep port-forward running in another terminal)
./envoy-monitor.sh          # One-time comprehensive report
./envoy-monitor.sh -w       # Continuous monitoring (refreshes every 5s)
./config-summary.sh         # View all Terraform configurations
```

### Quick Metrics Queries
```bash
# Max connections per pod (Circuit Breaker setting)
curl -s http://localhost:9901/config_dump | jq -r '.configs[1].static_clusters[0].cluster.circuit_breakers.thresholds[0].max_connections'

# Current active WebSocket connections
curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_active:" | awk '{print $2}'

# Rate limiting status
curl -s http://localhost:9901/stats | grep "websocket_rate_limiter.http_local_rate_limit.rate_limited:" | awk '{print $2}'

# Circuit breaker status (0 = closed/good, >0 = open/blocking)
curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.circuit_breakers.default.cx_open:" | awk '{print $2}'
```

### Configuration Changes
```bash
# Envoy: Circuit breaker & rate limits
vim terraform/06-envoy-proxy/locals.tf
cd terraform/06-envoy-proxy && terraform apply

# Client: Behavior & scaling
vim terraform/07-client-application/locals.tf  
cd terraform/07-client-application && terraform apply

# Server: Scaling & resources
vim terraform/05-server-application/locals.tf
cd terraform/05-server-application && terraform apply
```

### Kubernetes Monitoring
```bash
# Pod status
kubectl get pods -o wide

# Client logs (WebSocket connection attempts)
kubectl logs -l app=envoy-poc-client-app -f

# Server logs (WebSocket message handling)  
kubectl logs -l app=envoy-poc-app-server -f

# Envoy logs
kubectl logs -l app=envoy-proxy -f
```

## 🧪 Load Testing Scenarios

### Scenario 1: Test Rate Limiting
```bash
# Edit terraform/06-envoy-proxy/locals.tf:
max_connections = 20        # High limit
max_tokens = 5             # Low rate limit
tokens_per_fill = 1
fill_interval = "2s"

# Apply and monitor rate_limited metric
```

### Scenario 2: Test Circuit Breaker
```bash
# Edit terraform/06-envoy-proxy/locals.tf:
max_connections = 5         # Low limit
max_tokens = 50            # High rate limit

# Edit terraform/07-client-application/locals.tf:
max_connections = 10       # Each client tries 10 connections
replicas = 3               # 3 clients = 30 total connection attempts

# Apply and monitor circuit_breaker metrics
```

### Scenario 3: Scale Test
```bash
# Edit terraform/07-client-application/locals.tf:
replicas = 20              # Scale up clients
max_connections = 3        # Moderate connections per client

# Monitor total connection distribution across server pods
```

## 📊 Key Metrics to Watch

| Metric | Location | Meaning |
|--------|----------|---------|
| `upstream_cx_active` | Envoy stats | Current WebSocket connections |
| `circuit_breakers.cx_open` | Envoy stats | Circuit breaker triggered (0=good) |
| `local_rate_limit.rate_limited` | Envoy stats | Requests blocked by rate limiting |
| `upstream_cx_connect_fail` | Envoy stats | Failed connection attempts |
| `max_connections` | Envoy config | Circuit breaker limit per server pod |
| `max_tokens` | Envoy config | Rate limiting token bucket size |

## 🔧 Troubleshooting

### No connections working?
1. Check port-forward: `curl http://localhost:9901/ready`
2. Check Envoy pod: `kubectl get pods -l app=envoy-proxy`
3. Check server pods: `kubectl get pods -l app=envoy-poc-app-server`

### Circuit breaker always open?
- Lower `max_connections` in client locals.tf
- Check server pod count vs connection attempts

### Rate limiting too aggressive?
- Increase `max_tokens` or `tokens_per_fill`
- Decrease `fill_interval`

### Clients not connecting?
- Check client logs: `kubectl logs -l app=envoy-poc-client-app`
- Verify Envoy service: `kubectl get svc envoy-proxy-service`
