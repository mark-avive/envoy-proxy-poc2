# Section 2: AWS Networking (VPC, Subnets, Security Groups)

This Terraform configuration creates the networking infrastructure for the Envoy Proxy POC as specified in requirement section 2.

## Resources Created

### VPC
- **VPC Name**: `envoy-vpc`
- **CIDR Block**: `172.245.0.0/16`
- **DNS Support**: Enabled
- **DNS Hostnames**: Enabled

### Subnets
- **Public Subnets**: 2 subnets in different AZs (`us-west-2a`, `us-west-2b`)
  - `172.245.1.0/24` (AZ: us-west-2a)
  - `172.245.2.0/24` (AZ: us-west-2b)
  - Tagged for AWS Load Balancer Controller (`kubernetes.io/role/elb = 1`)
  
- **Private Subnets**: 2 subnets in different AZs for EKS worker nodes
  - `172.245.10.0/24` (AZ: us-west-2a)
  - `172.245.20.0/24` (AZ: us-west-2b)
  - Tagged for internal ELB (`kubernetes.io/role/internal-elb = 1`)

### Internet Gateway
- Provides internet access for public subnets

### NAT Gateways
- **Count**: 2 (one per public subnet)
- **Purpose**: Provide internet egress for private subnets
- **Elastic IPs**: Allocated for each NAT Gateway

### Route Tables
- **Public Route Table**: Routes internet traffic (0.0.0.0/0) to Internet Gateway
- **Private Route Tables**: 2 tables, each routing internet traffic to respective NAT Gateway

### Security Groups

#### 1. EKS Cluster Security Group
- **Purpose**: Communication between EKS control plane and worker nodes
- **Ingress**: HTTPS (443) from worker nodes
- **Egress**: All traffic

#### 2. Worker Node Security Group
- **Purpose**: EKS worker nodes communication
- **Ingress**: 
  - Node-to-node communication (self-referencing)
  - Communication from EKS control plane (1025-65535)
  - HTTPS to EKS control plane (443)
  - Communication from ALB (NodePort range: 30000-32767)
- **Egress**: All traffic

#### 3. ALB Security Group
- **Purpose**: Application Load Balancer
- **Ingress**: 
  - HTTP (80) from internet
  - HTTPS (443) from internet
- **Egress**: 
  - To worker nodes (NodePort range: 30000-32767)
  - To Envoy service (80)

#### 4. Envoy Service Security Group
- **Purpose**: Envoy proxy service
- **Ingress**: 
  - HTTP (80) from ALB
  - Internal communication from worker nodes (80)
  - Envoy admin interface (9901) from worker nodes
- **Egress**: 
  - To server application (8080)
  - All outbound traffic for AWS services

## Usage

1. **Initialize Terraform**:
   ```bash
   cd terraform/02-networking
   terraform init
   ```

2. **Plan the deployment**:
   ```bash
   terraform plan
   ```

3. **Apply the configuration**:
   ```bash
   terraform apply
   ```

## Configuration

All configurable values are centralized in `locals.tf`:
- VPC CIDR and name
- Subnet CIDRs
- Availability zones
- AWS region and profile
- Common tags

## Outputs

The configuration outputs important resource IDs and information that will be used by other Terraform sections:
- VPC ID and CIDR
- Subnet IDs (public and private)
- Security Group IDs
- NAT Gateway information
- Route Table IDs

## Backend Configuration

State is stored in S3 backend:
- **Bucket**: `cfndev-envoy-proxy-poc-terraform-state`
- **Key**: `02-networking/terraform.tfstate`
- **Profile**: `avive-cfndev-k8s`

## Dependencies

This configuration has no dependencies on other Terraform sections and can be deployed independently.
