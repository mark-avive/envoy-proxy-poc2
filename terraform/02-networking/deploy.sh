#!/bin/bash

# Terraform deployment script for Section 2: Networking
# This script helps deploy the networking infrastructure for the Envoy Proxy POC

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Envoy Proxy POC - Section 2: Networking Deployment ==="
echo "Working directory: $(pwd)"
echo ""

# Function to run terraform commands
run_terraform() {
    local command=$1
    echo "Running: terraform $command"
    echo "----------------------------------------"
    terraform $command
    echo ""
}

# Check AWS CLI profile
echo "Checking AWS CLI profile..."
aws sts get-caller-identity --profile avive-cfndev-k8s > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ AWS CLI profile 'avive-cfndev-k8s' is configured and accessible"
else
    echo "✗ AWS CLI profile 'avive-cfndev-k8s' is not configured or accessible"
    echo "Please configure your AWS SSO profile before proceeding"
    exit 1
fi
echo ""

# Parse command line arguments
ACTION="${1:-apply}"

# Check for --destroy flag
if [[ "$1" == "--destroy" ]]; then
    ACTION="destroy"
fi

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
        echo "Deploying networking infrastructure..."
        run_terraform "init -upgrade"
        run_terraform "plan"
        echo ""
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_terraform "apply"
            echo "✓ Networking infrastructure deployed successfully!"
        else
            echo "Deployment cancelled by user"
            exit 0
        fi
        ;;
    "destroy")
        echo "WARNING: This will destroy all networking infrastructure!"
        read -p "Are you sure you want to destroy all resources? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_terraform "destroy"
            echo "✓ Networking infrastructure destroyed!"
        else
            echo "Destruction cancelled by user"
            exit 0
        fi
        ;;
    "output")
        echo "Displaying Terraform outputs..."
        run_terraform "output"
        ;;
    *)
        echo "Usage: $0 [init|plan|apply|destroy|output] or $0 --destroy"
        echo ""
        echo "Commands:"
        echo "  init     - Initialize Terraform"
        echo "  plan     - Plan the deployment"
        echo "  apply    - Deploy the infrastructure (default)"
        echo "  destroy  - Destroy the infrastructure"
        echo "  output   - Show terraform outputs"
        echo ""
        echo "Flags:"
        echo "  --destroy - Same as 'destroy' command"
        exit 1
        ;;
esac

echo "=== Section 2: Networking deployment completed ==="
