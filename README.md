# Envoy Proxy POC 2

AWS EKS cluster setup with Envoy proxy as a reverse proxy for WebSocket applications.

## Project Structure

```
├── README.md
├── requirements.txt           # Detailed project requirements
└── terraform/                 # Terraform infrastructure code
    ├── 02-networking/         # Section 2: AWS Networking
    │   ├── README.md          # Networking section documentation
    │   ├── deploy.sh          # Deployment script
    │   ├── locals.tf          # Configuration variables
    │   ├── versions.tf        # Terraform and provider versions
    │   ├── vpc.tf             # VPC, subnets, routing
    │   ├── security_groups.tf # Security groups
    │   └── outputs.tf         # Resource outputs
    ├── 03-eks-cluster/        # Section 3: EKS Cluster Details
    │   ├── README.md          # EKS section documentation
    │   ├── deploy.sh          # Deployment script
    │   ├── locals.tf          # Configuration variables
    │   ├── versions.tf        # Terraform and provider versions
    │   ├── data.tf            # Remote state data sources
    │   ├── iam.tf             # IAM roles and policies
    │   ├── eks.tf             # EKS cluster and node group
    │   └── outputs.tf         # Resource outputs
    ├── 04-ecr-repositories/   # Section 4: Container Registries (ECR)
    │   ├── README.md          # ECR section documentation
    │   ├── deploy.sh          # Deployment script
    │   ├── locals.tf          # Configuration variables
    │   ├── versions.tf        # Terraform and provider versions
    │   ├── ecr.tf             # ECR repositories and policies
    │   ├── null-resources.tf  # Bash script integration
    │   ├── outputs.tf         # Resource outputs
    │   └── scripts/           # Bash scripts for ECR operations
    │       ├── ecr-login.sh   # ECR Docker login
    │       ├── ecr-status.sh  # Repository status check
    │       └── ecr-cleanup.sh # Image cleanup
    └── 05-server-application/ # Section 5: Server Application
        ├── README.md          # Server application documentation
        ├── deploy.sh          # Deployment script
        ├── locals.tf          # Configuration variables
        ├── versions.tf        # Terraform and provider versions
        ├── data.tf            # Remote state data sources
        ├── null-resources.tf  # Build/deploy automation
        ├── outputs.tf         # Resource outputs
        ├── app/               # Python WebSocket server
        │   ├── server.py      # WebSocket server implementation
        │   ├── requirements.txt # Python dependencies
        │   └── Dockerfile     # Container definition
        ├── k8s/               # Kubernetes manifests
        │   └── deployment.yaml # Deployment and service
        └── scripts/           # Deployment automation scripts
            ├── build-and-push.sh # Docker build and ECR push
            ├── deploy-k8s.sh     # Kubernetes deployment
            └── status-check.sh   # Deployment verification
```

## Implemented Sections

### ✅ Section 2: AWS Networking (VPC, Subnets, Security Groups)

Creates the foundational networking infrastructure:
- VPC with CIDR `172.245.0.0/16`
- Public and private subnets across 2 AZs
- Internet Gateway and NAT Gateways
- Security groups for EKS, ALB, and Envoy

**Usage:**
```bash
cd terraform/02-networking
./deploy.sh apply
```

### ✅ Section 3: EKS Cluster Details

Creates the Amazon EKS cluster and managed node group:
- EKS cluster `envoy-poc` with Kubernetes v1.31
- Managed node group with 2 t3.medium instances
- Both public and private API endpoints
- Control plane logging to CloudWatch
- IAM roles and policies for cluster and nodes

**Usage:**
```bash
cd terraform/03-eks-cluster
./deploy.sh apply
```

**Post-deployment:**
```bash
# The kubeconfig is automatically configured during deployment
# The path is determined by the KUBECONFIG environment variable or defaults to:
# /home/mark/.kube/config-cfndev-envoy-poc

# Set up your environment (respects existing KUBECONFIG):
source ./setup-env.sh

# Or set manually:
export KUBECONFIG=/path/to/your/kubeconfig

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

### ✅ Section 4: Container Registries (ECR)

Creates Amazon ECR repositories for application containers:
- Server application repository: `cfndev-envoy-proxy-poc-app`
- Client application repository: `cfndev-envoy-proxy-poc-client`
- Lifecycle policies for automatic image cleanup
- Integrated bash scripts for ECR operations via null resources
- Image scanning and encryption enabled

**Usage:**
```bash
cd terraform/04-ecr-repositories
./deploy.sh apply
```

**ECR Operations:**
```bash
# Check repository status
./deploy.sh status

# Login to ECR
./deploy.sh login

# Get Docker commands
./deploy.sh commands
```

### ✅ Section 5: Server Application

Deploys the Python WebSocket server application to EKS:
- Python WebSocket server with asyncio support
- Containerized with Python 3.10-alpine base image
- Kubernetes deployment with 4 replicas and ClusterIP service
- Automated Docker build and ECR push via null resources
- Resource limits: 100m CPU, 128Mi memory per pod
- Health checks and graceful shutdown support

**Usage:**
```bash
cd terraform/05-server-application
./deploy.sh
```

**Verification:**
```bash
# Check deployment status
kubectl get pods -l app=websocket-server
kubectl get service envoy-poc-app-server-service

# Test WebSocket server (port forwarding)
kubectl port-forward service/envoy-poc-app-server-service 8080:80
```

## AWS Configuration

- **AWS Profile**: `avive-cfndev-k8s` (AWS SSO)
- **Region**: `us-west-2`
- **S3 Backend**: `cfndev-envoy-proxy-poc-terraform-state`
- **Kubeconfig**: Automatically configured using the `KUBECONFIG` environment variable or default path

## Environment Setup

The kubeconfig path is determined dynamically during deployment:
1. If `KUBECONFIG` environment variable is set, it uses that path
2. Otherwise, defaults to `/home/mark/.kube/config-cfndev-envoy-poc`

Use the provided script to configure your environment:
```bash
# Source the environment setup script (respects existing KUBECONFIG)
source ./setup-env.sh

# Or manually set the environment variables
export AWS_PROFILE=avive-cfndev-k8s
export KUBECONFIG=/path/to/your/kubeconfig  # Use your preferred path
```

## Next Steps

Implement remaining sections:
- Section 6: Envoy Proxy Setup
- Section 7: Client Application
- Section 8: Post-Deployment Verification

## Deployment Order

The sections have dependencies and should be deployed in this order:
1. **Section 2**: Networking (foundation)
2. **Section 3**: EKS Cluster (depends on networking)
3. **Section 4**: ECR Repositories (independent, can be deployed anytime)
4. **Section 5**: Server Application (depends on EKS and ECR)
5. **Sections 6-7**: Envoy and Client Applications (depend on Section 5)
6. **Section 8**: Verification