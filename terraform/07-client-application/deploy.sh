#!/bin/bash
set -e

# WebSocket Client Application - Section 7: Client Application

# Parse command line arguments
ACTION="${1:-apply}"

# Check for --destroy flag
if [[ "$1" == "--destroy" ]]; then
    ACTION="destroy"
fi

echo "=== Envoy Proxy POC - Section 7: Client Application ==="
echo "Working directory: $(pwd)"

# Configuration
REGION=${AWS_REGION:-us-west-2}
PROFILE=${AWS_PROFILE:-avive-cfndev-k8s}
CLUSTER_NAME=${CLUSTER_NAME:-envoy-poc}

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
    echo "  apply    - Deploy the client application (default)"
    echo "  destroy  - Destroy the client application"
    echo "  output   - Show terraform outputs"
    echo "  status   - Check deployment status"
    echo ""
    echo "Flags:"
    echo "  --destroy - Same as 'destroy' command"
    exit 1
}

echo ""
echo "Checking AWS CLI profile..."
if aws sts get-caller-identity --profile $PROFILE >/dev/null 2>&1; then
    echo "✓ AWS CLI profile '$PROFILE' is configured and accessible"
else
    echo "❌ AWS CLI profile '$PROFILE' is not configured or accessible"
    echo "Please configure AWS CLI with: aws configure --profile $PROFILE"
    exit 1
fi

echo ""
echo "Checking kubectl configuration..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE >/dev/null 2>&1
if kubectl cluster-info >/dev/null 2>&1; then
    CURRENT_CLUSTER=$(kubectl config current-context | cut -d'/' -f2 2>/dev/null || echo "unknown")
    echo "✓ kubectl is configured and cluster is accessible"
    echo "  Current cluster: $CURRENT_CLUSTER"
else
    echo "❌ kubectl is not properly configured or cluster is not accessible"
    exit 1
fi

echo ""
echo "Checking prerequisite sections..."

# Check networking (Section 2)
if aws s3 ls s3://cfndev-envoy-proxy-poc-terraform-state/02-networking/terraform.tfstate --profile $PROFILE >/dev/null 2>&1; then
    echo "✓ Section 2 (Networking) state found - dependency satisfied"
else
    echo "❌ Section 2 (Networking) state not found - please deploy networking first"
    exit 1
fi

# Check EKS cluster (Section 3)  
if aws s3 ls s3://cfndev-envoy-proxy-poc-terraform-state/03-eks-cluster/terraform.tfstate --profile $PROFILE >/dev/null 2>&1; then
    echo "✓ Section 3 (EKS Cluster) state found - dependency satisfied"
else
    echo "❌ Section 3 (EKS Cluster) state not found - please deploy EKS cluster first"
    exit 1
fi

# Check ECR repositories (Section 4)
if aws s3 ls s3://cfndev-envoy-proxy-poc-terraform-state/04-ecr-repositories/terraform.tfstate --profile $PROFILE >/dev/null 2>&1; then
    echo "✓ Section 4 (ECR Repositories) state found - dependency satisfied"
else
    echo "❌ Section 4 (ECR Repositories) state not found - please deploy ECR repositories first"
    exit 1
fi

# Check server application (Section 5)
if aws s3 ls s3://cfndev-envoy-proxy-poc-terraform-state/05-server-application/terraform.tfstate --profile $PROFILE >/dev/null 2>&1; then
    echo "✓ Section 5 (Server Application) state found - dependency satisfied"
else
    echo "❌ Section 5 (Server Application) state not found - please deploy server application first"
    exit 1
fi

# Check Envoy proxy (Section 6)
if aws s3 ls s3://cfndev-envoy-proxy-poc-terraform-state/06-envoy-proxy/terraform.tfstate --profile $PROFILE >/dev/null 2>&1; then
    echo "✓ Section 6 (Envoy Proxy) state found - dependency satisfied"
else
    echo "❌ Section 6 (Envoy Proxy) state not found - please deploy Envoy proxy first"
    exit 1
fi

echo ""

# Handle command line arguments
case "$ACTION" in
    "init")
        echo "Initializing Terraform..."
        run_terraform "init"
        ;;
    "plan")
        echo "Planning Terraform deployment..."
        run_terraform "init -upgrade"
        run_terraform "plan"
        ;;
    "apply")
        echo "Building, pushing, and deploying WebSocket Client Application..."

        # Run terraform init
        echo "Running: terraform init -upgrade"
        echo "----------------------------------------"
        terraform init -upgrade

        # Run terraform plan  
        echo ""
        echo "Running: terraform plan"
        echo "----------------------------------------"
        terraform plan

        # Ask for confirmation
        echo ""
        read -p "Do you want to apply these changes? (yes/no): " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo "Deployment cancelled by user"
            exit 0
        fi

        # Run terraform apply
        echo ""
        echo "Running: terraform apply"
        echo "----------------------------------------" 
        terraform apply -auto-approve

        echo ""
        echo "✅ Section 7: Client Application deployment completed!"
        echo ""
        echo "Next steps:"
        echo "1. Monitor client logs: kubectl logs -l app=envoy-poc-client-app -f"
        echo "2. Check WebSocket connections in client logs"
        echo "3. Verify message exchanges between clients and servers"
        echo "4. Monitor Envoy proxy for connection management"
        echo "5. Run end-to-end verification tests"
        ;;
    "destroy")
        echo "WARNING: This will destroy the client application deployment!"
        echo "This action will remove all WebSocket client pods and associated resources."
        echo ""
        read -p "Are you sure you want to destroy the client application? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_terraform "destroy"
            echo "✓ Client application destroyed!"
        else
            echo "Destruction cancelled by user"
            exit 0
        fi
        ;;
    "output")
        echo "Displaying Terraform outputs..."
        run_terraform "output"
        ;;
    "status")
        echo "Checking client application status..."
        echo ""
        echo "Client pods:"
        kubectl get pods -l app=envoy-poc-client-app
        echo ""
        echo "Client logs (last 10 lines):"
        kubectl logs -l app=envoy-poc-client-app --tail=10
        ;;
    *)
        show_usage
        ;;
esac
