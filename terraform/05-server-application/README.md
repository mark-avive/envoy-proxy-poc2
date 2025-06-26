# Section 5: Server Application

This section deploys the WebSocket server application to the EKS cluster created in previous sections.

## Architecture Overview

The server application consists of:
- **Python WebSocket Server**: A simple WebSocket server built with Python and asyncio
- **Docker Container**: Containerized using Python 3.10-alpine base image
- **Kubernetes Deployment**: Deployed as a Kubernetes service with 4 replicas
- **ECR Integration**: Docker image stored in AWS ECR repository
- **Resource Management**: Configured with appropriate CPU/memory limits and requests

## Components

### Application (`app/`)
- `server.py`: WebSocket server implementation
- `requirements.txt`: Python dependencies (websockets, asyncio)
- `Dockerfile`: Multi-stage Docker build configuration

### Kubernetes Manifests (`k8s/`)
- `deployment.yaml`: Kubernetes deployment and service definitions

### Automation Scripts (`scripts/`)
- `build-and-push.sh`: Builds Docker image and pushes to ECR
- `deploy-k8s.sh`: Deploys application to Kubernetes cluster  
- `status-check.sh`: Checks deployment status and health

### Terraform Configuration
- `locals.tf`: Local variables and configuration
- `versions.tf`: Provider version constraints
- `data.tf`: Remote state references and data sources
- `null-resources.tf`: Automation via null resources
- `outputs.tf`: Output values for reference

## Prerequisites

Before deploying this section, ensure:

1. **Previous sections are deployed**:
   - Section 2: Networking (VPC, subnets, security groups)
   - Section 3: EKS Cluster (EKS cluster and node groups)
   - Section 4: ECR Repositories (Container registry)

2. **Required tools are installed**:
   - AWS CLI v2
   - Docker
   - kubectl
   - Terraform >= 1.0

3. **AWS credentials are configured**:
   ```bash
   aws configure sso --profile avive-cfndev-k8s
   ```

4. **kubectl is configured for EKS**:
   ```bash
   aws eks update-kubeconfig --region us-west-2 --name envoy-poc --profile avive-cfndev-k8s
   ```

## Configuration

Key configuration values in `locals.tf`:

- **Application**: `websocket-server` with version `1.0.0`
- **Replicas**: 4 pods for high availability
- **Container Port**: 8080
- **Service Port**: 80
- **Resource Limits**: 100m CPU, 128Mi memory
- **Resource Requests**: 50m CPU, 64Mi memory

## Deployment

### Automatic Deployment (Recommended)

Use the deployment script for automated execution:

```bash
./deploy.sh
```

This will:
1. Initialize Terraform
2. Plan the deployment
3. Apply the configuration
4. Build and push Docker image to ECR
5. Deploy application to Kubernetes
6. Verify deployment status

### Manual Deployment

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Plan deployment**:
   ```bash
   terraform plan
   ```

3. **Apply configuration**:
   ```bash
   terraform apply
   ```

The Terraform configuration will automatically:
- Build the Docker image from the application source
- Push the image to the ECR repository
- Deploy the application to the EKS cluster
- Configure the Kubernetes service

## Verification

### Check Deployment Status

1. **Using the status script**:
   ```bash
   ./scripts/status-check.sh
   ```

2. **Using kubectl directly**:
   ```bash
   # Check pods
   kubectl get pods -l app=websocket-server
   
   # Check service
   kubectl get service envoy-poc-app-server-service
   
   # Check deployment
   kubectl describe deployment envoy-poc-websocket-server-deployment
   
   # View logs
   kubectl logs -l app=websocket-server
   ```

3. **Port forwarding for testing**:
   ```bash
   kubectl port-forward service/envoy-poc-app-server-service 8080:80
   ```

### Expected Output

- **4 pods** running with `Running` status
- **Service** with ClusterIP assigned
- **Deployment** showing 4/4 replicas ready
- **Container logs** showing WebSocket server startup messages

## Application Details

### WebSocket Server Features

- **Protocol**: WebSocket over HTTP
- **Port**: 8080 (container), 80 (service)
- **Health Check**: HTTP endpoint on `/health`
- **Graceful Shutdown**: Handles SIGTERM signals
- **Connection Handling**: Supports multiple concurrent connections

### Resource Configuration

Per pod resource allocation:
- **CPU Request**: 50m (guaranteed)
- **CPU Limit**: 100m (maximum)
- **Memory Request**: 64Mi (guaranteed)  
- **Memory Limit**: 128Mi (maximum)

Total cluster resources (4 replicas):
- **CPU**: 200m request, 400m limit
- **Memory**: 256Mi request, 512Mi limit

## Troubleshooting

### Common Issues

1. **Image pull errors**:
   ```bash
   # Check ECR repository and login
   aws ecr describe-repositories --profile avive-cfndev-k8s
   aws ecr get-login-password --region us-west-2 --profile avive-cfndev-k8s | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com
   ```

2. **Pod startup failures**:
   ```bash
   # Check pod events and logs
   kubectl describe pod <pod-name>
   kubectl logs <pod-name>
   ```

3. **Service connectivity issues**:
   ```bash
   # Check service endpoints
   kubectl get endpoints envoy-poc-app-server-service
   kubectl describe service envoy-poc-app-server-service
   ```

### Log Locations

- **Terraform logs**: Current directory
- **Docker build logs**: Docker daemon logs
- **Kubernetes logs**: `kubectl logs` command
- **Application logs**: Container stdout/stderr

## Integration Points

This section integrates with:

- **Section 2 (Networking)**: Uses VPC and security groups (indirectly via EKS)
- **Section 3 (EKS Cluster)**: Deploys to the EKS cluster and node groups
- **Section 4 (ECR Repositories)**: Stores Docker images in ECR

## Next Steps

After successful deployment:

1. **Section 6**: Deploy Envoy Proxy configuration
2. **Section 7**: Deploy client application
3. **Section 8**: Perform end-to-end verification

## Cleanup

To remove all resources:

```bash
terraform destroy
```

This will:
- Remove Kubernetes deployments and services
- Clean up null resources (build artifacts remain in ECR)
- Preserve ECR images (cleaned up in Section 4)

**Note**: ECR images are preserved for potential reuse. Use Section 4's cleanup scripts to remove images if needed.
