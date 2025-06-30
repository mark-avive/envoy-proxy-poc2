#!/bin/bash

# Deploy script for Section 5: Server Application
# This script deploys the WebSocket server application to EKS

set -e

SECTION_NAME="05-server-application"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
ACTION="${1:-apply}"

# Check for --destroy flag
if [[ "$1" == "--destroy" ]]; then
    ACTION="destroy"
fi

echo "======================================="
echo "Deploying Section 5: Server Application"
echo "======================================="
echo ""

# Function to run terraform commands
run_terraform() {
    local command=$1
    echo "Running: terraform $command"
    echo "----------------------------------------"
    terraform $command
    echo ""
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [init|plan|apply|destroy|output|status] or $0 --destroy"
    echo ""
    echo "Commands:"
    echo "  init     - Initialize Terraform"
    echo "  plan     - Plan the deployment"
    echo "  apply    - Deploy the server application (default)"
    echo "  destroy  - Destroy the server application"
    echo "  output   - Show terraform outputs"
    echo "  status   - Check deployment status"
    echo ""
    echo "Flags:"
    echo "  --destroy - Same as 'destroy' command"
    exit 1
}

# Check prerequisites
echo "Checking prerequisites..."

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is not installed or not in PATH"
    exit 1
fi

# Check if docker is installed and running
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

docker info > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Docker is not running or not accessible"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed or not in PATH"
    exit 1
fi

echo "✓ All prerequisites are available"
echo ""

# Check AWS credentials
echo "Checking AWS credentials..."
aws sts get-caller-identity --profile avive-cfndev-k8s > /dev/null
if [ $? -ne 0 ]; then
    echo "Error: AWS credentials not configured for profile 'avive-cfndev-k8s'"
    echo "Please run: aws configure sso --profile avive-cfndev-k8s"
    exit 1
fi
echo "✓ AWS credentials are configured"
echo ""

# Check if kubectl is configured for EKS
echo "Checking EKS cluster connectivity..."
kubectl cluster-info > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Warning: kubectl not configured for EKS cluster"
    echo "Configuring kubectl for EKS cluster..."
    aws eks update-kubeconfig --region us-west-2 --name envoy-poc --profile avive-cfndev-k8s
    if [ $? -ne 0 ]; then
        echo "Error: Failed to configure kubectl for EKS cluster"
        echo "Please ensure the EKS cluster is deployed (Section 3)"
        exit 1
    fi
fi
echo "✓ EKS cluster connectivity confirmed"
echo ""

# Check if previous sections are deployed
echo "Checking previous section dependencies..."

# Check if ECR repositories exist (Section 4)
aws ecr describe-repositories --repository-names "cfndev-envoy-proxy-poc-app" --region us-west-2 --profile avive-cfndev-k8s > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: ECR repository 'cfndev-envoy-proxy-poc-app' not found"
    echo "Please deploy Section 4: ECR Repositories first"
    exit 1
fi
echo "✓ ECR repository is available"

# Check if EKS cluster exists (Section 3)  
aws eks describe-cluster --name envoy-poc --region us-west-2 --profile avive-cfndev-k8s > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: EKS cluster 'envoy-poc' not found"
    echo "Please deploy Section 3: EKS Cluster first"
    exit 1
fi
echo "✓ EKS cluster is available"
echo ""

# Handle command line arguments
case "$ACTION" in
    "init")
        echo "Initializing Terraform..."
        cd "$SCRIPT_DIR"
        run_terraform "init"
        ;;
    "plan")
        echo "Planning Terraform deployment..."
        cd "$SCRIPT_DIR"
        run_terraform "init -upgrade"
        run_terraform "plan"
        ;;
    "apply")
        # Original deployment logic
        cd "$SCRIPT_DIR"

        # Initialize Terraform
        echo "Initializing Terraform..."
        terraform init

        if [ $? -ne 0 ]; then
            echo "Error: Terraform initialization failed"
            exit 1
        fi
        echo "✓ Terraform initialized successfully"
        echo ""

        # Validate Terraform configuration
        echo "Validating Terraform configuration..."
        terraform validate

        if [ $? -ne 0 ]; then
            echo "Error: Terraform configuration is invalid"
            exit 1
        fi
        echo "✓ Terraform configuration is valid"
        echo ""

        # Plan Terraform deployment
        echo "Planning Terraform deployment..."
        terraform plan -out=tfplan

        if [ $? -ne 0 ]; then
            echo "Error: Terraform planning failed"
            exit 1
        fi
        echo "✓ Terraform plan completed successfully"
        echo ""

        # Apply Terraform configuration
        echo "Applying Terraform configuration..."
        echo "This will:"
        echo "  - Build and push Docker image to ECR"
        echo "  - Deploy WebSocket server to EKS cluster"
        echo "  - Configure Kubernetes service"
        echo ""

        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled by user"
            rm -f tfplan
            exit 0
        fi

        terraform apply tfplan

        if [ $? -ne 0 ]; then
            echo "Error: Terraform apply failed"
            rm -f tfplan
            exit 1
        fi

        rm -f tfplan
        echo "✓ Terraform deployment completed successfully"
        echo ""

        # Verify deployment
        echo "Verifying deployment..."
        echo ""

        # Wait a moment for resources to be ready
        echo "Waiting for resources to be ready..."
        sleep 10

        # Check deployment status using the status script
        if [ -x "$SCRIPT_DIR/scripts/status-check.sh" ]; then
            echo "Running deployment status check..."
            "$SCRIPT_DIR/scripts/status-check.sh" us-west-2 avive-cfndev-k8s envoy-poc
        else
            echo "Status check script not found or not executable"
            echo "Performing basic verification..."
            
            # Basic kubectl checks
            echo "Checking pods..."
            kubectl get pods -l app=websocket-server
            
            echo ""
            echo "Checking service..."
            kubectl get service envoy-poc-app-server-service
            
            echo ""
            echo "Checking deployment..."
            kubectl get deployment envoy-poc-websocket-server-deployment
        fi

        echo ""
        echo "======================================="
        echo "Section 5 deployment completed!"
        echo "======================================="
        echo ""
        echo "WebSocket server application has been deployed to EKS cluster."
        echo ""
        echo "Next steps:"
        echo "  1. Review the deployment outputs above"
        echo "  2. Test WebSocket connectivity (optional):"
        echo "     kubectl port-forward service/envoy-poc-app-server-service 8080:80"
        echo "  3. Deploy Section 6: Envoy Proxy Setup"
        echo ""
        echo "For troubleshooting, check:"
        echo "  - Pod logs: kubectl logs -l app=websocket-server"
        echo "  - Pod status: kubectl describe pods -l app=websocket-server"
        echo "  - Service status: kubectl describe service envoy-poc-app-server-service"
        echo ""
        ;;
    "destroy")
        echo "WARNING: This will destroy the server application deployment!"
        echo "This action will remove all WebSocket server pods and services."
        echo ""
        read -p "Are you sure you want to destroy the server application? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd "$SCRIPT_DIR"
            run_terraform "destroy"
            echo "✓ Server application destroyed!"
        else
            echo "Destruction cancelled by user"
            exit 0
        fi
        ;;
    "output")
        echo "Displaying Terraform outputs..."
        cd "$SCRIPT_DIR"
        run_terraform "output"
        ;;
    "status")
        echo "Checking server application status..."
        cd "$SCRIPT_DIR"
        if [ -x "$SCRIPT_DIR/scripts/status-check.sh" ]; then
            "$SCRIPT_DIR/scripts/status-check.sh" us-west-2 avive-cfndev-k8s envoy-poc
        else
            echo "Basic status check..."
            kubectl get pods -l app=websocket-server
            kubectl get service envoy-poc-app-server-service
            kubectl get deployment envoy-poc-websocket-server-deployment
        fi
        ;;
    *)
        show_usage
        ;;
esac
