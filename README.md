# Envoy Proxy POC 2

AWS EKS cluster setup with Envoy proxy as a reverse proxy for WebSocket applications.

## Project Structure

```
├── README.md
├── requirements.txt           # Detailed project requirements
└── terraform/                 # Terraform infrastructure code
    └── 02-networking/         # Section 2: AWS Networking
        ├── README.md          # Networking section documentation
        ├── deploy.sh          # Deployment script
        ├── locals.tf          # Configuration variables
        ├── versions.tf        # Terraform and provider versions
        ├── vpc.tf             # VPC, subnets, routing
        ├── security_groups.tf # Security groups
        └── outputs.tf         # Resource outputs
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

## AWS Configuration

- **AWS Profile**: `avive-cfndev-k8s` (AWS SSO)
- **Region**: `us-west-2`
- **S3 Backend**: `cfndev-envoy-proxy-poc-terraform-state`

## Next Steps

Implement remaining sections:
- Section 1: Project Structure and Tooling
- Section 3: EKS Cluster Details
- Section 4: Container Registries (ECR)
- Section 5: Server Application
- Section 6: Envoy Proxy Setup
- Section 7: Client Application
- Section 8: Post-Deployment Verification