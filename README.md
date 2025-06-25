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
    └── 04-ecr-repositories/   # Section 4: Container Registries (ECR)
        ├── README.md          # ECR section documentation
        ├── deploy.sh          # Deployment script
        ├── locals.tf          # Configuration variables
        ├── versions.tf        # Terraform and provider versions
        ├── ecr.tf             # ECR repositories and policies
        ├── null-resources.tf  # Bash script integration
        ├── outputs.tf         # Resource outputs
        └── scripts/           # Bash scripts for ECR operations
            ├── ecr-login.sh   # ECR Docker login
            ├── ecr-status.sh  # Repository status check
            └── ecr-cleanup.sh # Image cleanup
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
# Configure kubectl
aws eks update-kubeconfig --name envoy-poc --region us-west-2 --profile avive-cfndev-k8s

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

## AWS Configuration

- **AWS Profile**: `avive-cfndev-k8s` (AWS SSO)
- **Region**: `us-west-2`
- **S3 Backend**: `cfndev-envoy-proxy-poc-terraform-state`

## Next Steps

Implement remaining sections:
- Section 1: Project Structure and Tooling
- Section 4: Container Registries (ECR)
- Section 5: Server Application
- Section 6: Envoy Proxy Setup
- Section 7: Client Application
- Section 8: Post-Deployment Verification

## Deployment Order

The sections have dependencies and should be deployed in this order:
1. **Section 2**: Networking (foundation)
2. **Section 3**: EKS Cluster (depends on networking)
3. **Section 4**: ECR Repositories (independent, can be deployed anytime)
4. **Sections 5-7**: Applications (depend on EKS and ECR)
5. **Section 8**: Verification