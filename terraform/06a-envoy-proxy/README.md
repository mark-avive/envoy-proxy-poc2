# 06a-envoy-proxy: Atomic Connection Tracking Implementation

This directory contains a **clean, from-scratch implementation** of the Envoy proxy with **atomic connection tracking** using direct Redis connections. This implementation addresses all critical gaps identified in the multi-envoy architecture analysis.

## 🎯 Key Features

### ✅ Atomic Operations
- **Direct Redis connections** from Envoy Lua scripts (no HTTP proxy layer)
- **Atomic Lua scripts** for check-and-increment operations
- **Race condition prevention** through Redis-native atomicity
- **Distributed state consistency** across multiple Envoy proxies

### ✅ Connection Limiting
- **Per-pod limit**: 2 WebSocket connections maximum
- **Global rate limiting**: 60 requests/minute (1 per second)
- **Real-time enforcement** with immediate rejection
- **Accurate connection tracking** with cleanup on disconnect

### ✅ Monitoring & Metrics
- **Prometheus-compatible metrics** endpoint
- **Per-pod connection counts**
- **Global connection statistics**
- **Rate limiting metrics**
- **Real-time monitoring** tools

## 📁 Directory Structure

```
06a-envoy-proxy/
├── envoy.tf                    # Envoy deployment with atomic Lua scripts
├── redis.tf                   # Redis service for atomic operations
├── outputs.tf                 # Terraform outputs
├── locals.tf                  # Configuration variables
├── data.tf                    # Data sources
├── versions.tf                # Terraform providers
├── k8s/
│   ├── envoy-config.yaml      # Envoy configuration with direct Redis cluster
│   └── redis-connection-tracker-atomic.lua  # Atomic Lua implementation
├── scripts/
│   └── deploy.sh             # Deployment script
└── query-atomic-metrics.sh   # Monitoring dashboard
```

## 🚀 Deployment

### Prerequisites
- EKS cluster running
- Custom Envoy image with Lua libraries available
- Backend server application deployed
- Configuration file at `../../config.env`

### Deploy the Stack
```bash
cd terraform/06a-envoy-proxy
./scripts/deploy.sh
```

### Monitor the Implementation
```bash
# Real-time metrics dashboard
./query-atomic-metrics.sh

# Watch metrics in real-time
watch -n 2 ./query-atomic-metrics.sh

# Monitor Redis operations
kubectl exec -it -n default deployment/redis-atomic -- redis-cli monitor

# View Envoy logs
kubectl logs -f -n default -l app=envoy-proxy-atomic
```

## 🏗️ Architecture

### Atomic Connection Tracking Flow

1. **WebSocket Request** arrives at Envoy
2. **Rate Limiting Check** (atomic, fail-fast)
3. **Request forwarded** to backend server
4. **Response intercepted** by Envoy
5. **Pod ID extracted** from upstream routing
6. **Atomic Connection Check** via Redis Lua script:
   - GET current count for pod
   - IF count >= limit: REJECT
   - ELSE: INCR count + store metadata
7. **Connection established** or **rejected** based on atomic result
8. **Cleanup on disconnect** via connection termination handler

### Redis Key Schema

```
ws:pod_conn:<pod-ip>          # Per-pod connection count
ws:all_connections            # Set of all active connection IDs
ws:conn:<connection-id>       # Connection metadata (hash)
ws:rate_limit:<minute>        # Rate limiting window
ws:rejected                   # Total rejected connections
ws:proxy:<proxy-id>:connections  # Per-proxy tracking
ws:active_pods               # Set of active pod IDs
```

### Atomic Lua Scripts

1. **Connection Enforcement Script**:
   - Atomically checks and increments pod connection count
   - Stores connection metadata with TTL
   - Updates global registries

2. **Connection Cleanup Script**:
   - Atomically decrements pod connection count
   - Removes connection metadata
   - Updates global registries

3. **Rate Limiting Script**:
   - Sliding window rate limiting
   - Atomic increment with TTL

## 🔧 Configuration

Key configuration values (in `locals.tf`):

```hcl
max_connections_per_pod = 2           # Per-pod WebSocket limit
rate_limit_requests_per_minute = 60   # Global rate limit (1/sec)
redis_replicas = 1                    # Redis instances
envoy_replicas = 2                    # Envoy proxy instances
```

## 📊 Monitoring

### Metrics Endpoint
Access Prometheus-compatible metrics:
```bash
curl http://<load-balancer>/websocket/metrics
```

### Redis Monitoring
Direct Redis command monitoring:
```bash
# Current pod connections
redis-cli KEYS "ws:pod_conn:*"
redis-cli GET "ws:pod_conn:<pod-ip>"

# Global statistics
redis-cli SCARD "ws:all_connections"
redis-cli GET "ws:rejected"

# Rate limiting
redis-cli GET "ws:rate_limit:$(date +%s | awk '{print int($1/60)}')"
```

### Kubernetes Monitoring
```bash
# Pod status
kubectl get pods -l app=envoy-proxy-atomic
kubectl get pods -l app=redis-atomic

# Service endpoints
kubectl get svc envoy-proxy-atomic-service
kubectl get svc redis-atomic-service

# Logs
kubectl logs -f -l app=envoy-proxy-atomic
kubectl logs -f -l app=redis-atomic
```

## 🧪 Testing

### Test Connection Limiting
```bash
# Get load balancer URL
LB_URL=$(kubectl get svc envoy-proxy-atomic-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test WebSocket connections (should allow first 2, reject 3rd+)
wscat -c ws://$LB_URL/  # Connection 1
wscat -c ws://$LB_URL/  # Connection 2  
wscat -c ws://$LB_URL/  # Connection 3 (should be rejected)
```

### Test Rate Limiting
```bash
# Rapid requests to trigger rate limiting
for i in {1..70}; do
  curl -H "Connection: Upgrade" -H "Upgrade: websocket" http://$LB_URL/ &
done
```

## 🔍 Troubleshooting

### Common Issues

1. **Redis Connection Failed**
   - Check Redis pod status: `kubectl get pods -l app=redis-atomic`
   - Verify service: `kubectl get svc redis-atomic-service`
   - Test connectivity: `kubectl exec -it deployment/redis-atomic -- redis-cli ping`

2. **Envoy Lua Errors**
   - Check Envoy logs: `kubectl logs -l app=envoy-proxy-atomic`
   - Verify Lua script ConfigMap: `kubectl get configmap envoy-lua-scripts-atomic -o yaml`

3. **Load Balancer Not Ready**
   - Wait for provisioning: `kubectl get svc envoy-proxy-atomic-service -w`
   - Check AWS NLB status in AWS Console

4. **Connection Tracking Not Working**
   - Monitor Redis: `kubectl exec -it deployment/redis-atomic -- redis-cli monitor`
   - Check upstream pod detection in Envoy logs
   - Verify WebSocket upgrade headers

### Debug Commands
```bash
# Check atomic script execution
kubectl exec -it deployment/redis-atomic -- redis-cli EVAL "return 'atomic-test'" 0

# Verify Envoy configuration
kubectl exec -it deployment/envoy-proxy-atomic -- cat /etc/envoy/envoy.yaml

# Test Redis connectivity from Envoy pod
kubectl exec -it deployment/envoy-proxy-atomic -- nc -zv redis-atomic-service 6379
```

## 📋 Differences from 06-envoy-proxy

This `06a-envoy-proxy` implementation differs from the original `06-envoy-proxy` in several key ways:

1. **Direct Redis**: No HTTP proxy layer - Lua scripts connect directly to Redis
2. **Atomic Scripts**: All operations use Redis Lua scripts for atomicity
3. **Clean Architecture**: Built from scratch with lessons learned
4. **Enhanced Monitoring**: Comprehensive metrics and monitoring tools
5. **Better Error Handling**: Fail-safe approaches with proper error logging
6. **Simplified Deployment**: Single deployment script with status checking

## 🎯 Success Criteria

- ✅ **Atomic Operations**: All connection tracking uses atomic Redis operations
- ✅ **Connection Limiting**: Enforces 2 connections per pod maximum
- ✅ **Rate Limiting**: Enforces 1 request/second globally
- ✅ **Monitoring**: Provides comprehensive metrics and monitoring
- ✅ **Multi-Proxy**: Supports multiple Envoy instances with shared state
- ✅ **Production Ready**: Includes error handling, logging, and monitoring

This implementation represents the **definitive solution** for atomic, distributed connection tracking in a multi-Envoy proxy environment.
