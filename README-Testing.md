# Envoy Proxy POC - Testing and Tuning Guide

This document provides comprehensive guidance on testing, monitoring, and tuning the Envoy Proxy POC system. It covers all key configuration parameters, deployment procedures, and monitoring commands needed to validate the system under various load conditions.

## Table of Contents

1. [Configurable Parameters](#configurable-parameters)
2. [Testing Scenarios](#testing-scenarios)
3. [Deployment Commands](#deployment-commands)
4. [Monitoring Commands](#monitoring-commands)
5. [Performance Testing](#performance-testing)
6. [System Tuning](#system-tuning)
7. [Troubleshooting](#troubleshooting)
8. [Expected System Behavior](#expected-system-behavior)

---

## Configurable Parameters

### Section 5: Server Application (`terraform/05-server-application/locals.tf`)

```hcl
locals {
  # Application Configuration
  replicas        = 4           # Number of server pods (1-10)
  
  # Resource Limits - Adjust for load testing
  cpu_request    = "50m"        # CPU request per pod
  memory_request = "64Mi"       # Memory request per pod
  cpu_limit      = "100m"       # CPU limit per pod (increase for high load)
  memory_limit   = "128Mi"      # Memory limit per pod (increase for high load)
  
  # Port Configuration
  container_port  = 8080        # WebSocket server port
  health_port     = 8081        # Health check port
}
```

**Testing Variations:**
- **Low Load**: `replicas = 2`, `cpu_limit = "50m"`, `memory_limit = "64Mi"`
- **High Load**: `replicas = 8`, `cpu_limit = "500m"`, `memory_limit = "512Mi"`
- **Stress Test**: `replicas = 1`, `cpu_limit = "100m"`, `memory_limit = "128Mi"`

### Section 6: Envoy Proxy (`terraform/06-envoy-proxy/locals.tf`)

```hcl
locals {
  # Envoy Configuration
  envoy_replicas = 2                    # Number of Envoy proxy pods (1-5)
  max_connections_per_pod = 2           # Max WebSocket connections per server pod
  connection_rate_limit = "1/s"         # Rate limit for new connections
}
```

**Envoy Rate Limiting Configuration** (`terraform/06-envoy-proxy/k8s/envoy-config.yaml`):

```yaml
# Rate Limiting Configuration
token_bucket:
  max_tokens: 10        # Maximum tokens in bucket (burst capacity)
  tokens_per_fill: 1    # Tokens added per interval
  fill_interval: 1s     # Token refill interval

# Circuit Breaker Configuration  
circuit_breakers:
  thresholds:
  - priority: DEFAULT
    max_connections: 8        # 4 backend pods * 2 connections per pod
    max_pending_requests: 10  # Queue limit for pending requests
    max_requests: 20          # Active request limit
    max_retries: 3           # Retry limit
```

**Testing Variations:**
- **Strict Limits**: `max_tokens: 5`, `max_connections: 4`, `tokens_per_fill: 1`
- **Relaxed Limits**: `max_tokens: 50`, `max_connections: 32`, `tokens_per_fill: 10`
- **Burst Handling**: `max_tokens: 100`, `tokens_per_fill: 1`, `fill_interval: 0.1s`

### Section 7: Client Application (`terraform/07-client-application/locals.tf`)

```hcl
locals {
  # Client Configuration
  replicas = 10             # Number of client pods (1-20)
  
  # Resource Limits - Adjust for connection load
  cpu_request    = "50m"    # CPU request per pod
  memory_request = "64Mi"   # Memory request per pod  
  cpu_limit      = "100m"   # CPU limit per pod
  memory_limit   = "128Mi"  # Memory limit per pod
}
  connection_rate_limit = "1/s" # Rate limit for new connections
  
  # Resource Limits
  cpu_request    = "100m"       # CPU request per Envoy pod
  memory_request = "128Mi"      # Memory request per Envoy pod
  cpu_limit      = "250m"       # CPU limit per Envoy pod
  memory_limit   = "256Mi"      # Memory limit per Envoy pod
}
```

**Key Envoy Configuration** (`terraform/06-envoy-proxy/k8s/envoy-config.yaml`):

```yaml
# Connection Limits
circuit_breakers:
  thresholds:
    max_connections: 2          # Max connections per upstream host
    max_requests: 100           # Max concurrent requests

# Rate Limiting  
rate_limits:
  actions:
    - request_headers:
        descriptor_value: "1"
  local_rate_limit:
    token_bucket:
      max_tokens: 1
      tokens_per_fill: 1
      fill_interval: 1s         # 1 connection per second
```

**Testing Variations:**
- **Restrictive**: `max_connections: 1`, `fill_interval: 2s`
- **Permissive**: `max_connections: 5`, `fill_interval: 0.5s`
- **Stress Test**: `max_connections: 10`, `fill_interval: 0.1s`

### Section 7: Client Application (`terraform/07-client-application/locals.tf`)

```hcl
locals {
  # Client Configuration
  replicas = 10                 # Number of client pods (1-20)
  
  # Resource Limits
  cpu_request    = "50m"        # CPU request per client pod
  memory_request = "64Mi"       # Memory request per client pod
  cpu_limit      = "100m"       # CPU limit per client pod
  memory_limit   = "128Mi"      # Memory limit per client pod
}
```

**Client Behavior Configuration** (`terraform/07-client-application/app/client.py`):

```python
class WebSocketClient:
    def __init__(self, client_id: str, envoy_endpoint: str):
        self.max_connections = 5          # Connections per client pod
        self.connection_interval = 10     # Seconds between connection attempts
        self.message_interval_min = 10    # Min seconds between messages
        self.message_interval_max = 20    # Max seconds between messages
```

**Testing Variations:**
- **Light Load**: `replicas = 5`, `max_connections = 2`, `connection_interval = 30`
- **Heavy Load**: `replicas = 20`, `max_connections = 10`, `connection_interval = 5`
- **Burst Test**: `replicas = 15`, `max_connections = 5`, `connection_interval = 1`

---

## Testing Scenarios

### Scenario 1: Connection Limit Testing
**Objective**: Test Envoy's per-pod connection limits

**Configuration:**
```hcl
# Server: 05-server-application/locals.tf
replicas = 2

# Envoy: 06-envoy-proxy/k8s/envoy-config.yaml
max_connections: 2

# Client: 07-client-application/locals.tf  
replicas = 5
```

**Expected Behavior**: 4 total connections maximum (2 servers × 2 connections each)

### Scenario 2: Rate Limiting Testing
**Objective**: Test Envoy's connection rate limiting

**Configuration:**
```hcl
# Envoy: 06-envoy-proxy/k8s/envoy-config.yaml
fill_interval: 2s  # 1 connection every 2 seconds

# Client: 07-client-application/app/client.py
connection_interval = 1  # Attempt connections every 1 second
```

**Expected Behavior**: Connections queued/rejected due to rate limiting

### Scenario 3: High Load Testing
**Objective**: Test system under heavy load

**Configuration:**
```hcl
# Server: 05-server-application/locals.tf
replicas = 8
cpu_limit = "500m"
memory_limit = "512Mi"

# Client: 07-client-application/locals.tf
replicas = 20
```

**Expected Behavior**: High connection attempts, resource utilization

---

## Deployment Commands

### Apply Configuration Changes

After modifying any `locals.tf` file, deploy the changes:

```bash
# For Server Application changes
cd terraform/05-server-application
terraform plan
terraform apply -auto-approve

# For Envoy Proxy changes  
cd terraform/06-envoy-proxy
terraform plan
terraform apply -auto-approve

# For Client Application changes
cd terraform/07-client-application
terraform plan
terraform apply -auto-approve
```

### Quick Configuration Update Script

Create a script to quickly update and deploy:

```bash
#!/bin/bash
# update-config.sh

SECTION=$1
if [ -z "$SECTION" ]; then
    echo "Usage: ./update-config.sh [05-server|06-envoy|07-client]"
    exit 1
fi

cd terraform/$SECTION-application 2>/dev/null || cd terraform/$SECTION-envoy-proxy 2>/dev/null || cd terraform/$SECTION-server-application

echo "Applying changes to Section $SECTION..."
terraform plan -compact-warnings
read -p "Apply changes? (y/N): " confirm
if [[ $confirm == [yY] ]]; then
    terraform apply -auto-approve
fi
```

### Full System Restart

To apply changes across all components:

```bash
# Deploy in order of dependencies
cd terraform/05-server-application && terraform apply -auto-approve
cd terraform/06-envoy-proxy && terraform apply -auto-approve  
cd terraform/07-client-application && terraform apply -auto-approve
```

---

## Monitoring Commands

### Connection Status Monitoring

#### Check Current Connections Per Pod

```bash
# Monitor client connection attempts
kubectl logs -l app=envoy-poc-client-app --tail=100 | grep -E "(Successfully created|Failed to create|Total:)"

# Check connection count per client pod
kubectl logs -l app=envoy-poc-client-app --tail=50 | grep "Total:" | sort | uniq -c
```

#### Monitor Connection Rejections

```bash
# Check for connection failures in client logs
kubectl logs -l app=envoy-poc-client-app --tail=200 | grep -E "(Failed to create|Error|Connection.*failed)"

# Check Envoy logs for rate limiting
kubectl logs -l app=envoy-proxy --tail=100 | grep -E "(rate_limit|rejected|denied)"

# Monitor connection timeouts
kubectl logs -l app=envoy-poc-client-app --tail=100 | grep -i timeout
```

#### Real-time Connection Monitoring

```bash
# Follow client connection activity
kubectl logs -l app=envoy-poc-client-app -f | grep -E "(Connection|Successfully|Failed)"

# Monitor message exchanges
kubectl logs -l app=envoy-poc-client-app -f | grep "Response from server"

# Watch Envoy access logs
kubectl logs -l app=envoy-proxy -f | grep -E "(GET|POST|WebSocket)"
```

### Resource Utilization

#### Pod Resource Usage

```bash
# Check CPU/Memory usage (requires metrics-server)
kubectl top pods -l app=envoy-poc-client-app
kubectl top pods -l app=envoy-proxy
kubectl top pods -l app=envoy-poc-app-server

# Detailed resource information
kubectl describe pods -l app=envoy-poc-client-app | grep -E "(Requests|Limits|CPU|Memory)"
```

#### System Load Overview

```bash
# Overview of all POC components
kubectl get pods -l 'app in (envoy-poc-client-app,envoy-proxy,envoy-poc-app-server)' -o wide

# Check node resource usage
kubectl describe nodes | grep -E "(Allocated|cpu|memory)" -A 5
```

### Connection Statistics

#### Envoy Proxy Statistics

```bash
# Port forward to Envoy admin interface
kubectl port-forward deployment/envoy-proxy 9901:9901 &

# Query connection statistics
curl -s http://localhost:9901/stats | grep -E "(connection|upstream|rate_limit)"

# Check cluster statistics
curl -s http://localhost:9901/stats | grep cluster.websocket_cluster

# Rate limiting statistics  
curl -s http://localhost:9901/stats | grep rate_limit
```

#### Server Connection Counts

```bash
# Check server logs for active connections
kubectl logs -l app=envoy-poc-app-server --tail=100 | grep -E "(Connection.*established|Client.*connected|WebSocket.*opened)"

# Monitor server response patterns
kubectl logs -l app=envoy-poc-app-server --tail=50 | grep "Received message from" | cut -d' ' -f8 | sort | uniq -c
```

### Load Balancing Analysis

```bash
# Check which server pods are receiving traffic
kubectl logs -l app=envoy-poc-client-app --tail=200 | grep "Response from server" | awk '{print $11}' | sort | uniq -c

# Analyze load distribution over time
kubectl logs -l app=envoy-poc-client-app --since=5m | grep "Response from server" | awk '{print $11}' | sort | uniq -c
```

---

## Performance Testing

### Connection Load Testing

#### Test Connection Limits

```bash
# Scale clients to test connection limits
kubectl scale deployment envoy-poc-client-app --replicas=15

# Monitor connection success/failure rates
watch "kubectl logs -l app=envoy-poc-client-app --tail=100 | grep -c 'Successfully created'"
watch "kubectl logs -l app=envoy-poc-client-app --tail=100 | grep -c 'Failed to create'"
```

#### Test Rate Limiting

```bash
# Monitor rate limiting in real-time
kubectl logs -l app=envoy-poc-client-app -f | grep -E "(connection #|Failed)" | while read line; do
    echo "$(date): $line"
done
```

### Message Throughput Testing

```bash
# Count messages per minute
kubectl logs -l app=envoy-poc-client-app --since=1m | grep "Response from server" | wc -l

# Monitor message latency (approximate)
kubectl logs -l app=envoy-poc-client-app --tail=50 | grep -E "(Sent message|Response from)" | tail -10
```

### System Stress Testing

```bash
# Create high load scenario
kubectl scale deployment envoy-poc-client-app --replicas=25
kubectl scale deployment envoy-poc-app-server --replicas=2

# Monitor system during stress test
watch "kubectl get pods -l 'app in (envoy-poc-client-app,envoy-proxy,envoy-poc-app-server)' --no-headers | awk '{print \$3}' | sort | uniq -c"
```

---

## Troubleshooting

### Common Issues and Diagnostics

#### Connections Not Establishing

```bash
# Check Envoy service accessibility
kubectl exec -it deployment/envoy-poc-client-app -- wget -q --spider http://envoy-proxy-service.default.svc.cluster.local:80

# Verify Envoy configuration
kubectl logs -l app=envoy-proxy | grep -E "(error|failed|config)"

# Check service endpoints
kubectl get endpoints envoy-proxy-service
kubectl get endpoints envoy-poc-app-server-service
```

#### Rate Limiting Issues

```bash
# Check Envoy rate limit configuration
kubectl exec -it deployment/envoy-proxy -- cat /etc/envoy/envoy.yaml | grep -A 10 rate_limit

# Monitor rate limit statistics
kubectl port-forward deployment/envoy-proxy 9901:9901 &
curl -s http://localhost:9901/stats | grep rate_limit
```

#### Resource Constraints

```bash
# Check for resource pressure
kubectl describe nodes | grep -E "(Pressure|OutOf)"

# Monitor pod resource usage
kubectl top pods --sort-by=cpu
kubectl top pods --sort-by=memory

# Check for OOMKilled pods
kubectl get events --field-selector reason=OOMKilling
```

### Reset Testing Environment

```bash
# Reset to baseline configuration
kubectl scale deployment envoy-poc-client-app --replicas=10
kubectl scale deployment envoy-poc-app-server --replicas=4
kubectl scale deployment envoy-proxy --replicas=2

# Clear old logs
kubectl delete pods -l app=envoy-poc-client-app
kubectl delete pods -l app=envoy-proxy
kubectl delete pods -l app=envoy-poc-app-server
```

---

## Quick Reference

### Most Common Commands

```bash
# Check all POC pods status
kubectl get pods -l 'app in (envoy-poc-client-app,envoy-proxy,envoy-poc-app-server)' -o wide

# Monitor connection establishment
kubectl logs -l app=envoy-poc-client-app --tail=50 | grep -E "(Successfully|Failed)" | sort | uniq -c

# Check Envoy proxy stats
kubectl port-forward svc/envoy-proxy-service 9901:9901 &
curl -s http://localhost:9901/stats | grep -E "(rate_limit|circuit_breaker|connection)"

# Monitor resource usage
kubectl top pods -l 'app in (envoy-poc-client-app,envoy-proxy,envoy-poc-app-server)'

# Quick deployment after config changes
cd terraform/0X-section && terraform apply -auto-approve
```

### Configuration File Locations

- **Server Config**: `terraform/05-server-application/locals.tf`
- **Envoy Config**: `terraform/06-envoy-proxy/locals.tf` and `k8s/envoy-config.yaml`
- **Client Config**: `terraform/07-client-application/locals.tf` and `app/client.py`

---

## Testing Checklist

### Pre-Testing Setup
- [ ] Baseline metrics recorded
- [ ] Configuration parameters documented
- [ ] Monitoring commands prepared
- [ ] Expected results defined

### During Testing
- [ ] Connection establishment rates monitored
- [ ] Rate limiting behavior verified
- [ ] Resource utilization tracked
- [ ] Error rates documented
- [ ] Load balancing distribution checked

### Post-Testing Analysis
- [ ] Results compared to expectations
- [ ] Performance bottlenecks identified
- [ ] Configuration adjustments documented
- [ ] Recommendations for optimization noted

### Automated Testing Script Example

```bash
#!/bin/bash
# automated-test.sh

echo "Starting Envoy Proxy POC Testing..."

# Record baseline
echo "=== Baseline Metrics ==="
kubectl get pods -l 'app in (envoy-poc-client-app,envoy-proxy,envoy-poc-app-server)'
kubectl top pods -l 'app in (envoy-poc-client-app,envoy-proxy,envoy-poc-app-server)' 2>/dev/null || echo "Metrics server unavailable"

# Wait for connections to establish
echo "=== Waiting for connections to establish ==="
sleep 60

# Check connection statistics
echo "=== Connection Statistics ==="
kubectl logs -l app=envoy-poc-client-app --tail=200 | grep -c "Successfully created"
kubectl logs -l app=envoy-poc-client-app --tail=200 | grep -c "Failed to create"

# Check message flow
echo "=== Message Flow Statistics ==="
kubectl logs -l app=envoy-poc-client-app --since=5m | grep -c "Response from server"

echo "Testing complete. Review logs for detailed analysis."
```

---

## System Tuning

### Server Application Tuning

#### CPU/Memory Scaling for High Load

```hcl
# In terraform/05-server-application/locals.tf
locals {
  # High Load Configuration
  replicas        = 8           # Scale based on expected connections
  cpu_request     = "100m"      # Increase for connection processing
  memory_request  = "128Mi"     # Increase for WebSocket state
  cpu_limit       = "500m"      # Allow burst CPU usage
  memory_limit    = "512Mi"     # Allow more memory for connections
}
```

#### WebSocket Server Tuning (app/server.py)

Add these environment variables to deployment:

```yaml
# In k8s/deployment.yaml
env:
- name: MAX_CONNECTIONS
  value: "1000"              # Maximum concurrent connections per pod
- name: KEEPALIVE_TIMEOUT  
  value: "300"               # WebSocket keepalive timeout
- name: BUFFER_SIZE
  value: "8192"              # WebSocket message buffer size
```

### Envoy Proxy Tuning

#### Rate Limiting Optimization

```yaml
# In k8s/envoy-config.yaml - Relaxed rate limiting
token_bucket:
  max_tokens: 100           # Large burst capacity
  tokens_per_fill: 10       # Higher connection rate (10/second)
  fill_interval: 1s

# Strict rate limiting for testing
token_bucket:
  max_tokens: 5             # Small burst capacity  
  tokens_per_fill: 1        # Low connection rate (1/second)
  fill_interval: 2s         # Slower refill
```

#### Circuit Breaker Optimization

```yaml
# High throughput configuration
circuit_breakers:
  thresholds:
  - priority: DEFAULT
    max_connections: 64       # 8 backend pods * 8 connections each
    max_pending_requests: 100 # Large request queue
    max_requests: 200         # High concurrent request limit
    max_retries: 5           # More retry attempts

# Conservative configuration  
circuit_breakers:
  thresholds:
  - priority: DEFAULT
    max_connections: 4        # Very limited connections
    max_pending_requests: 5   # Small request queue
    max_requests: 10          # Low concurrent requests
    max_retries: 1           # Minimal retries
```

#### Connection Pool Tuning

```yaml
# Add to cluster configuration for WebSocket optimization
typed_extension_protocol_options:
  envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
    "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
    common_http_protocol_options:
      idle_timeout: 600s          # Keep connections alive longer
      max_connection_duration: 0s # No connection duration limit
    explicit_http_config:
      http_protocol_options:
        accept_http_10: true
        enable_trailers: true     # Support WebSocket trailers
```

### Client Application Tuning

#### Connection Behavior Tuning

```python
# In app/client.py - Aggressive connection testing
class WebSocketClient:
    def __init__(self, client_id: str, envoy_endpoint: str):
        self.max_connections = 10         # More connections per pod
        self.connection_interval = 1      # Faster connection attempts
        self.message_interval_min = 1     # Frequent messaging
        self.message_interval_max = 5
        self.reconnect_delay = 1          # Quick reconnection
        self.connection_timeout = 10      # Connection timeout

# Conservative configuration
class WebSocketClient:
    def __init__(self, client_id: str, envoy_endpoint: str):
        self.max_connections = 2          # Fewer connections per pod
        self.connection_interval = 30     # Slower connection attempts
        self.message_interval_min = 30    # Less frequent messaging
        self.message_interval_max = 60
        self.reconnect_delay = 60         # Slow reconnection
        self.connection_timeout = 30      # Longer timeout
```

#### Resource Allocation for Scale Testing

```hcl
# In terraform/07-client-application/locals.tf
locals {
  # High load client configuration
  replicas        = 20          # Many client pods
  cpu_request     = "100m"      # Higher CPU for many connections
  memory_request  = "256Mi"     # More memory for connection state
  cpu_limit       = "500m"      # Allow CPU bursts
  memory_limit    = "512Mi"     # Allow memory growth
}
```

### System-Wide Tuning Recommendations

#### Load Testing Scenarios

1. **Connection Saturation Test**:
   ```hcl
   # Server: 4 pods, 500m CPU, 512Mi memory
   # Envoy: max_connections: 16, max_tokens: 20
   # Client: 15 pods, 8 connections each = 120 attempts
   ```

2. **Rate Limit Stress Test**:
   ```hcl
   # Envoy: tokens_per_fill: 1, fill_interval: 5s
   # Client: connection_interval: 1s (aggressive)
   ```

3. **Circuit Breaker Test**:
   ```hcl
   # Envoy: max_connections: 2, max_pending_requests: 3
   # Client: 10 pods, 5 connections each = 50 attempts
   ```

4. **High Message Volume Test**:
   ```python
   # Client: message_interval_min: 0.1, message_interval_max: 1
   # Large message payloads
   ```

#### Performance Monitoring During Tuning

```bash
# Monitor key metrics during tuning
kubectl top pods --sort-by=cpu
kubectl port-forward svc/envoy-proxy-service 9901:9901 &

# Key Envoy metrics to watch
curl -s http://localhost:9901/stats | grep -E "(rate_limit|circuit_breaker|upstream_rq_pending|upstream_rq_active)"

# Connection success rates
kubectl logs -l app=envoy-poc-client-app --tail=100 | grep -E "(Successfully|Failed)" | sort | uniq -c
```

---

## Expected System Behavior

### Default Configuration Behavior

With the current default configuration:

**Connection Attempts:** 
- 10 client pods × 5 connections each = 50 total connection attempts

**Connection Limits:**
- Circuit breaker limit: 8 connections (4 server pods × 2 connections per pod)
- Rate limit: 1 connection per second (token bucket)

**Expected Results:**
- ~8 successful persistent WebSocket connections
- ~42 connections will be rate-limited or rejected by circuit breaker
- Connections distributed evenly across 4 server pods (load balancing)
- Continuous bi-directional message exchange on successful connections
- Rate limiting will space out connection establishment over ~10 seconds

### Load Distribution Analysis

```bash
# Check connection distribution across server pods
kubectl logs -l app=envoy-poc-client-app --tail=200 | grep "Response from server" | \
  awk '{print $NF}' | sort | uniq -c

# Expected output (approximately):
#   2 10.42.1.123  # Server pod 1
#   2 10.42.2.456  # Server pod 2  
#   2 10.42.3.789  # Server pod 3
#   2 10.42.4.012  # Server pod 4
```

### Rate Limiting Behavior

```bash
# Monitor rate limiting in action
kubectl logs -l app=envoy-poc-client-app -f | grep -E "(Successfully created|Failed to create)" | \
  while read line; do echo "$(date '+%H:%M:%S'): $line"; done

# Expected pattern: 1 success per second, with failures clustered at start
```

### Circuit Breaker Behavior

```bash
# Check circuit breaker statistics
kubectl port-forward svc/envoy-proxy-service 9901:9901 &
curl -s http://localhost:9901/stats | grep -E "circuit_breakers.*open|upstream_rq_pending"

# Expected: circuit_breakers should show open state when limit exceeded
```

### Message Flow Patterns

```bash
# Monitor message exchange rate
kubectl logs -l app=envoy-poc-client-app --since=1m | grep "Response from server" | wc -l

# Expected: ~24-48 messages per minute (8 connections × 1 message every 10-20s)
```

This testing guide provides comprehensive coverage for validating, tuning, and monitoring the Envoy Proxy POC system under various load conditions and configuration scenarios.
