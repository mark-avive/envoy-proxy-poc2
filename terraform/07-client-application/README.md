# Section 7: Client Application

This section deploys a WebSocket client application that tests the connection through the Envoy proxy to the WebSocket server application.

## Overview

The client application:
- Creates 5 WebSocket connections from each client pod to the Envoy proxy
- Attempts 1 new connection every 10 seconds until max connections are reached
- Randomly sends messages over existing connections every 10-20 seconds
- Logs responses including timestamp and server pod IP
- Provides health check endpoint for Kubernetes monitoring

## Architecture

```
[Client Pods (10 replicas)] → [Envoy Proxy (2 replicas)] → [Server Pods (4 replicas)]
     ↓                              ↓                         ↓
- 5 connections per pod      - Rate limiting                - WebSocket server
- Random messaging           - Connection limits            - Responds with metadata
- Health checks              - Load balancing               - Pod IP + timestamp
```

## Prerequisites

Before deploying this section, ensure the following sections are deployed:

1. **Section 2**: Networking (VPC, subnets, security groups)
2. **Section 3**: EKS Cluster 
3. **Section 4**: ECR Repositories
4. **Section 5**: Server Application
5. **Section 6**: Envoy Proxy Setup

## Configuration

Key configuration values in `locals.tf`:

- **Replicas**: 10 client pods (as per requirements)
- **Connections per pod**: 5 WebSocket connections
- **Connection interval**: 10 seconds
- **Message interval**: 10-20 seconds (random)
- **Target endpoint**: `ws://envoy-proxy-service.default.svc.cluster.local:80`

## Files Structure

```
07-client-application/
├── app/
│   ├── client.py           # WebSocket client application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile         # Container image definition
├── k8s/
│   └── deployment.yaml    # Kubernetes deployment manifest
├── scripts/
│   ├── build-and-push.sh  # Build and push Docker image
│   ├── deploy-k8s.sh      # Deploy to Kubernetes
│   └── status-check.sh    # Check deployment status
├── locals.tf              # Configuration variables
├── versions.tf            # Terraform and provider versions
├── data.tf               # Data sources and remote state
├── null-resources.tf     # Build, push, and deploy automation
├── outputs.tf            # Output values
├── deploy.sh             # Main deployment script
└── README.md             # This file
```

## Deployment

Run the automated deployment:

```bash
cd terraform/07-client-application
./deploy.sh
```

Or run Terraform commands manually:

```bash
terraform init
terraform plan
terraform apply
```

## Testing & Monitoring

### Check Client Pod Status
```bash
kubectl get pods -l app=envoy-poc-client-app
```

### Monitor WebSocket Connections
```bash
kubectl logs -l app=envoy-poc-client-app -f | grep "Connection"
```

### Monitor Message Exchanges
```bash
kubectl logs -l app=envoy-poc-client-app -f | grep "Response from server"
```

### Check Resource Usage
```bash
kubectl top pods -l app=envoy-poc-client-app
```

### View All Client Logs
```bash
kubectl logs -l app=envoy-poc-client-app -f --prefix=true
```

### Health Check Status
```bash
kubectl get pods -l app=envoy-poc-client-app -o wide
```

## Expected Behavior

When deployed successfully, you should observe:

1. **Connection Establishment**: Each client pod creates up to 5 WebSocket connections to Envoy
2. **Rate Limiting**: Envoy enforces 1 connection per second rate limit
3. **Message Exchange**: Clients send random messages every 10-20 seconds
4. **Server Responses**: Servers respond with timestamp and pod identification
5. **Load Balancing**: Messages distributed across multiple server pods
6. **Connection Management**: Envoy manages connection limits (max 2 per server pod)

## Troubleshooting

### Client Pods Not Starting
```bash
kubectl describe pods -l app=envoy-poc-client-app
kubectl logs -l app=envoy-poc-client-app
```

### Connection Issues
```bash
# Check if Envoy service is reachable
kubectl exec <client-pod> -- wget -q --spider http://envoy-proxy-service.default.svc.cluster.local:80

# Check Envoy logs for connection rejections
kubectl logs -l app=envoy-proxy
```

### Image Pull Issues
```bash
# Check ECR repository and image
aws ecr describe-repositories --repository-names cfndev-envoy-proxy-poc-client
aws ecr list-images --repository-name cfndev-envoy-proxy-poc-client
```

## Resource Configuration

- **CPU Request**: 50m per pod
- **Memory Request**: 64Mi per pod  
- **CPU Limit**: 100m per pod
- **Memory Limit**: 128Mi per pod
- **Health Check Port**: 8081
- **Total Resource Usage**: ~1 CPU core, ~1.3GB RAM for all 10 pods

## Integration Testing

This client application enables end-to-end testing of:

- WebSocket protocol handling through Envoy
- Rate limiting enforcement (1 connection/second)
- Connection limits per backend pod (max 2)
- Load balancing across server pods
- Connection persistence and message exchange
- Kubernetes service discovery and networking

The logs from both client and server applications provide comprehensive visibility into the system behavior and performance characteristics.
