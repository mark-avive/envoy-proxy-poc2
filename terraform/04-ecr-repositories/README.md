# Section 4: Container Registries (ECR)

This Terraform configuration creates the Amazon ECR repositories for the Envoy Proxy POC as specified in requirement section 4. It includes bash scripts integrated via null resources for ECR operations.

## Resources Created

### ECR Repositories

#### Server Application Repository
- **Name**: `cfndev-envoy-proxy-poc-app`
- **Purpose**: WebSocket server application container images
- **Image Tag Mutability**: MUTABLE (allows tag overwriting)
- **Scan on Push**: Enabled for vulnerability scanning
- **Encryption**: AES256 encryption at rest

#### Client Application Repository
- **Name**: `cfndev-envoy-proxy-poc-client`
- **Purpose**: WebSocket client application container images
- **Image Tag Mutability**: MUTABLE (allows tag overwriting)
- **Scan on Push**: Enabled for vulnerability scanning
- **Encryption**: AES256 encryption at rest

### Lifecycle Policies
- **Retention**: 30 days for all images
- **Cleanup**: Automatic removal of images older than 30 days
- **Rule Priority**: 1 (highest priority)

### Bash Script Integration

#### ECR Login Script (`scripts/ecr-login.sh`)
- Authenticates Docker with ECR registry
- Uses AWS CLI to get login token
- Automatically configures Docker credentials
- **Usage**: `./scripts/ecr-login.sh [region] [profile]`

#### ECR Status Script (`scripts/ecr-status.sh`)
- Checks repository existence and status
- Lists recent images with details
- Shows repository URIs and creation dates
- **Usage**: `./scripts/ecr-status.sh [region] [profile] [app-repo] [client-repo]`

#### ECR Cleanup Script (`scripts/ecr-cleanup.sh`)
- Cleans up repository images during destroy
- Batch deletes all images before repository deletion
- Prevents terraform destroy failures due to non-empty repositories
- **Usage**: `CLEANUP_MODE=true ./scripts/ecr-cleanup.sh [region] [profile] [app-repo] [client-repo]`

### Null Resources

#### ECR Login Resource
- **Trigger**: Runs after repositories are created
- **Purpose**: Automatically logs Docker into ECR
- **Dependencies**: Both ECR repositories must exist

#### ECR Status Check Resource
- **Trigger**: Always runs (uses timestamp)
- **Purpose**: Verifies repositories and shows status
- **Dependencies**: Repositories and login must complete

#### ECR Cleanup Resource
- **Trigger**: Runs on terraform destroy
- **Purpose**: Cleans up images before repository deletion
- **Environment**: Uses destroy-time values

## Usage

### 1. Deploy ECR Infrastructure

```bash
cd terraform/04-ecr-repositories
terraform init
terraform plan
terraform apply
```

### 2. Manual ECR Operations

```bash
# Login to ECR
./scripts/ecr-login.sh us-west-2 avive-cfndev-k8s

# Check repository status
./scripts/ecr-status.sh us-west-2 avive-cfndev-k8s

# Build and push example (after creating application)
docker build -t <repository-url>:latest .
docker push <repository-url>:latest
```

### 3. Using Output Commands

```bash
# Get Docker login command
terraform output docker_login_command

# Get build commands
terraform output app_docker_build_command
terraform output client_docker_build_command

# Get push commands
terraform output app_docker_push_command
terraform output client_docker_push_command
```

## Configuration

All configurable values are centralized in `locals.tf`:
- Repository names
- Image tag mutability settings
- Scan on push configuration
- Lifecycle policy retention days
- AWS region and profile

## Dependencies

This section has no dependencies on other sections and can be deployed independently. However, it's typically deployed after networking and EKS for the complete infrastructure setup.

## Backend Configuration

State is stored in S3 backend:
- **Bucket**: `cfndev-envoy-proxy-poc-terraform-state`
- **Key**: `04-ecr-repositories/terraform.tfstate`
- **Profile**: `avive-cfndev-k8s`

## Outputs

The configuration provides comprehensive outputs:
- Repository names, URLs, and ARNs
- Registry information
- Docker command examples
- Complete configuration summary

## Security Features

- **Encryption**: AES256 encryption at rest
- **Image Scanning**: Vulnerability scanning on push
- **Lifecycle Management**: Automatic cleanup of old images
- **Access Control**: Uses IAM roles and policies

## Cost Considerations

- **Storage**: $0.10 per GB per month for stored images
- **Data Transfer**: Standard AWS data transfer rates apply
- **Image Scanning**: $0.09 per image scan (if enabled)
- **Lifecycle Policies**: Help reduce storage costs by cleaning up old images

## Troubleshooting

### Docker Login Issues
```bash
# Manual login
aws ecr get-login-password --region us-west-2 --profile avive-cfndev-k8s | \
    docker login --username AWS --password-stdin <registry-url>
```

### Permission Issues
- Ensure AWS profile has ECR permissions
- Check IAM policies for ECR access
- Verify region configuration

### Script Execution Issues
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Check script logs
./scripts/ecr-status.sh 2>&1 | tee ecr-status.log
```

## Integration with Applications

The repositories created here will be used by:
- **Section 5**: Server Application (uses app repository)
- **Section 6**: Client Application (uses client repository)
- **Section 7**: Kubernetes deployments (pulls from both repositories)

## Next Steps

After deploying ECR repositories:
1. Build application Docker images
2. Push images to respective repositories
3. Deploy applications to EKS cluster
4. Configure image pull secrets in Kubernetes (if needed)
