# Section 3: EKS Cluster Details

This Terraform configuration creates the Amazon EKS cluster and managed node group for the Envoy Proxy POC as specified in requirement section 3.

## Resources Created

### EKS Cluster
- **Cluster Name**: `envoy-poc`
- **Kubernetes Version**: `1.31` (latest stable available)
- **API Server Endpoints**: Both public and private endpoints enabled
- **Control Plane Logging**: Enabled for `api`, `audit`, `authenticator`, and `scheduler` logs
- **CloudWatch Log Group**: Created with 7-day retention for cluster logs

### Managed Node Group
- **Node Group Name**: `envoy-poc-worker-nodes`
- **Instance Type**: `t3.medium`
- **AMI Type**: `AL2_x86_64` (Amazon Linux 2)
- **Capacity Configuration**:
  - Desired: 2 nodes
  - Minimum: 2 nodes
  - Maximum: 4 nodes
- **Deployment**: Private subnets across multiple AZs
- **Update Strategy**: Max unavailable = 1 (rolling updates)

### IAM Roles and Policies

#### EKS Cluster Service Role
- **Role Name**: `envoy-poc-eks-cluster-role`
- **Attached Policies**: `AmazonEKSClusterPolicy`
- **Purpose**: Allows EKS to manage cluster resources

#### EKS Node Group Service Role
- **Role Name**: `envoy-poc-eks-node-group-role`
- **Attached Policies**:
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEKS_CNI_Policy`
  - `AmazonEC2ContainerRegistryReadOnly`
- **Purpose**: Allows worker nodes to join cluster and pull container images

### Security Configuration

- **Cluster Security Group**: References security group from Section 2 networking
- **Worker Node Placement**: Private subnets for enhanced security
- **Network Access**: Both public and private API endpoints for flexibility

## Dependencies

This section depends on Section 2 (Networking) and uses remote state to reference:
- VPC and subnet IDs
- Security group IDs
- Network configuration

## Usage

1. **Ensure Section 2 is deployed**:
   ```bash
   cd ../02-networking
   terraform apply
   ```

2. **Initialize Terraform**:
   ```bash
   cd terraform/03-eks-cluster
   terraform init
   ```

3. **Plan the deployment**:
   ```bash
   terraform plan
   ```

4. **Apply the configuration**:
   ```bash
   terraform apply
   ```

5. **Configure kubectl access**:
   ```bash
   aws eks update-kubeconfig --name envoy-poc --region us-west-2 --profile avive-cfndev-k8s
   ```

## Configuration

All configurable values are centralized in `locals.tf`:
- EKS cluster version and name
- Node group configuration
- Instance types and capacity
- AWS region and profile
- CloudWatch log types

## Verification Commands

After deployment, verify the cluster:

```bash
# Check cluster status
kubectl cluster-info

# Verify nodes
kubectl get nodes

# Check node group status
aws eks describe-nodegroup --cluster-name envoy-poc --nodegroup-name envoy-poc-worker-nodes --profile avive-cfndev-k8s

# View cluster details
aws eks describe-cluster --name envoy-poc --profile avive-cfndev-k8s
```

## Backend Configuration

State is stored in S3 backend:
- **Bucket**: `cfndev-envoy-proxy-poc-terraform-state`
- **Key**: `03-eks-cluster/terraform.tfstate`
- **Profile**: `avive-cfndev-k8s`

## Outputs

The configuration provides important outputs for other sections:
- Cluster endpoint and certificate data
- Cluster and node group ARNs
- IAM role information
- OIDC issuer URL (for AWS Load Balancer Controller)
- kubectl configuration command

## Cost Considerations

- **EKS Cluster**: ~$0.10/hour for control plane
- **t3.medium instances**: ~$0.0416/hour per instance (2 instances = ~$0.083/hour)
- **NAT Gateway**: ~$0.045/hour (from networking section)
- **Total estimated cost**: ~$0.228/hour (~$164/month)

## Scaling

The node group supports auto-scaling between 2-4 nodes. You can modify scaling parameters in `locals.tf` and reapply.
