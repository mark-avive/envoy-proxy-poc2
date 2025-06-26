# Section 6: Envoy Proxy Setup

This section implements the Envoy proxy as a reverse proxy to manage and rate-limit WebSocket connections for the Envoy Proxy POC.

## Overview

This terraform module deploys:
- **AWS Load Balancer Controller** via Helm chart for ALB integration
- **Envoy Proxy** with 2 replicas configured for WebSocket handling
- **Application Load Balancer (ALB)** for external access via Kubernetes Ingress
- **Rate limiting and connection management** for WebSocket connections

## Architecture

```
Internet → ALB → Envoy Proxy (2 replicas) → WebSocket Server (4 replicas)
```

## Features Implemented

### Envoy Configuration
- **WebSocket Support**: Handles WebSocket upgrade requests
- **Rate Limiting**: 1 connection per second global rate limit
- **Connection Limiting**: Maximum 8 connections (2 per backend pod)
- **Health Checks**: Active health checks to backend servers
- **Access Logging**: Comprehensive request logging to stdout
- **Metrics**: Admin interface on port 9901 for monitoring

### AWS Load Balancer Controller
- **ALB Integration**: Automatically provisions ALB via Kubernetes Ingress
- **IAM Roles**: IRSA (IAM Roles for Service Accounts) configuration
- **Security Groups**: Integrated with VPC security groups
- **Health Checks**: ALB health checks to Envoy admin endpoint

### Connection Management
- **Circuit Breaker**: Protects backend services from overload
- **Load Balancing**: Round-robin distribution across backend pods
- **Service Discovery**: Uses Kubernetes DNS for backend discovery

## Deployment

### Prerequisites
- Section 2 (Networking) must be deployed
- Section 3 (EKS Cluster) must be deployed  
- Section 5 (Server Application) must be deployed
- kubectl configured for the EKS cluster

### Deploy
```bash
./deploy.sh apply
```

### Check Status
```bash
./deploy.sh status
```

### Clean Up
```bash
./deploy.sh destroy
```

## Configuration

### Envoy Proxy
- **Image**: `envoyproxy/envoy:v1.29-latest`
- **Replicas**: 2
- **Resources**: 250m CPU, 256Mi memory limit
- **Ports**: 80 (HTTP/WebSocket), 9901 (admin)

### Rate Limiting
- **Connection Rate**: 1 connection per second
- **Max Connections**: 8 total (2 per backend pod)
- **Token Bucket**: 10 max tokens, 1 token per second refill

### Health Checks
- **Liveness**: HTTP GET to `/ready` on port 9901
- **Readiness**: HTTP GET to `/ready` on port 9901
- **Backend Health**: HTTP GET to `/health` on backend port 8081

## Access Points

### External Access (via ALB)
```bash
# Get ALB endpoint
kubectl get ingress envoy-proxy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# WebSocket endpoint
ws://<ALB_ENDPOINT>

# HTTP endpoint  
http://<ALB_ENDPOINT>
```

### Internal Access
```bash
# Envoy service (cluster internal)
envoy-proxy-service.default.svc.cluster.local:80

# Admin interface (port-forward required)
kubectl port-forward deployment/envoy-proxy 9901:9901
# Then access: http://localhost:9901
```

## Monitoring

### Envoy Admin Interface
```bash
kubectl port-forward deployment/envoy-proxy 9901:9901
```
Access `http://localhost:9901` for:
- Configuration dump
- Statistics and metrics  
- Cluster status
- Health check status

### Logs
```bash
# Envoy access logs
kubectl logs -l app=envoy-proxy

# AWS Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Metrics Endpoints
- **Envoy Stats**: `http://localhost:9901/stats`
- **Envoy Config**: `http://localhost:9901/config_dump`
- **Cluster Status**: `http://localhost:9901/clusters`

## Testing

### Basic Connectivity
```bash
# Test HTTP connectivity
curl http://<ALB_ENDPOINT>

# Test WebSocket upgrade
curl -H "Connection: Upgrade" -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
     -H "Sec-WebSocket-Version: 13" \
     http://<ALB_ENDPOINT>
```

### Rate Limiting Test
```bash
# Multiple rapid connections should trigger rate limiting
for i in {1..5}; do curl -H "Connection: Upgrade" -H "Upgrade: websocket" http://<ALB_ENDPOINT> & done
```

## Troubleshooting

### Common Issues

1. **ALB Not Provisioning**
   ```bash
   kubectl describe ingress envoy-proxy-ingress
   kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   ```

2. **Envoy Pods Not Ready**
   ```bash
   kubectl describe pods -l app=envoy-proxy
   kubectl logs -l app=envoy-proxy
   ```

3. **Backend Health Check Failures**
   ```bash
   kubectl port-forward deployment/envoy-proxy 9901:9901
   # Check http://localhost:9901/clusters for backend health
   ```

### Debug Commands
```bash
# Check all resources
kubectl get all -l app=envoy-proxy

# Check ingress annotations
kubectl describe ingress envoy-proxy-ingress

# Test backend connectivity
kubectl run debug --image=curlimages/curl -it --rm -- sh
# From inside: curl envoy-poc-app-server-service.default.svc.cluster.local/health
```

## Security

- **Non-root containers**: Envoy runs as user 1000
- **Read-only filesystem**: Security context enforced
- **Resource limits**: CPU and memory limits applied
- **Security groups**: ALB integrated with VPC security groups
- **Network policies**: Can be applied for additional security

## Next Steps

After successful deployment:
1. **Test WebSocket connections** through the ALB endpoint
2. **Monitor Envoy metrics** via the admin interface
3. **Deploy client application** (Section 7) for comprehensive testing
4. **Configure additional rate limiting** if needed
5. **Set up monitoring and alerting** for production use
