#!/bin/bash

# Terraform deployment script for Section 4: ECR Repositories
# This script helps deploy the ECR repositories for the Envoy Proxy POC

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Envoy Proxy POC - Section 4: ECR Repositories Deployment ==="
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

# Check Docker installation
echo "Checking Docker installation..."
docker --version > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Docker is installed and accessible"
    docker --version
else
    echo "⚠ Docker is not installed or not accessible"
    echo "Docker is required for ECR operations but not for Terraform deployment"
fi
echo ""

# Handle command line arguments
case "${1:-apply}" in
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
        echo "Deploying ECR repositories..."
        run_terraform "init -upgrade"
        run_terraform "plan"
        echo ""
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_terraform "apply"
            echo ""
            echo "✓ ECR repositories deployed successfully!"
            echo ""
            echo "Repository Information:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            terraform output -json repositories_config | jq -r '
            "App Repository:    " + .app_repository.name + "\n" +
            "App Repository URL: " + .app_repository.url + "\n" +
            "Client Repository:  " + .client_repository.name + "\n" +
            "Client Repository URL: " + .client_repository.url + "\n" +
            "Registry URL:       " + .registry.url
            ' 2>/dev/null || echo "Use 'terraform output' to see repository details"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Next steps:"
            echo "1. Check repository status:"
            echo "   ./scripts/ecr-status.sh"
            echo ""
            echo "2. Login to ECR (if Docker is available):"
            echo "   ./scripts/ecr-login.sh"
            echo ""
            echo "3. Get Docker commands:"
            echo "   terraform output docker_login_command"
            echo "   terraform output app_docker_build_command"
            echo "   terraform output client_docker_build_command"
            echo ""
        else
            echo "Deployment cancelled by user"
            exit 0
        fi
        ;;
    "destroy")
        echo "WARNING: This will destroy the ECR repositories and all container images!"
        echo "This action cannot be undone and will delete all stored container images."
        echo ""
        read -p "Are you sure you want to destroy the ECR repositories? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Note: The cleanup script will automatically remove all images before destroying repositories"
            run_terraform "destroy"
            echo "✓ ECR repositories destroyed!"
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
        echo "Checking ECR repository status..."
        echo ""
        if [ -f "scripts/ecr-status.sh" ]; then
            ./scripts/ecr-status.sh
        else
            echo "Status script not found. Using terraform output instead:"
            terraform output repositories_config 2>/dev/null || echo "No terraform state found"
        fi
        ;;
    "login")
        echo "Logging into ECR..."
        if [ -f "scripts/ecr-login.sh" ]; then
            ./scripts/ecr-login.sh
        else
            echo "Login script not found. Use terraform output to get login command:"
            terraform output docker_login_command
        fi
        ;;
    "commands")
        echo "Docker Commands:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Login to ECR:"
        terraform output -raw docker_login_command 2>/dev/null || echo "terraform output docker_login_command"
        echo ""
        echo "Build App Image:"
        terraform output -raw app_docker_build_command 2>/dev/null || echo "terraform output app_docker_build_command"
        echo ""
        echo "Build Client Image:"
        terraform output -raw client_docker_build_command 2>/dev/null || echo "terraform output client_docker_build_command"
        echo ""
        echo "Push App Image:"
        terraform output -raw app_docker_push_command 2>/dev/null || echo "terraform output app_docker_push_command"
        echo ""
        echo "Push Client Image:"
        terraform output -raw client_docker_push_command 2>/dev/null || echo "terraform output client_docker_push_command"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
    *)
        echo "Usage: $0 [init|plan|apply|destroy|output|status|login|commands]"
        echo ""
        echo "Commands:"
        echo "  init     - Initialize Terraform"
        echo "  plan     - Plan the deployment"
        echo "  apply    - Deploy the ECR repositories (default)"
        echo "  destroy  - Destroy the ECR repositories"
        echo "  output   - Show terraform outputs"
        echo "  status   - Check ECR repository status"
        echo "  login    - Login to ECR registry"
        echo "  commands - Show Docker commands for building and pushing images"
        exit 1
        ;;
esac

echo "=== Section 4: ECR Repositories deployment completed ==="
