#!/bin/bash

# Terraform deployment script for Section 3: EKS Cluster
# This script helps deploy the EKS cluster infrastructure for the Envoy Proxy POC

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Envoy Proxy POC - Section 3: EKS Cluster Deployment ==="
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

# Check if networking section is deployed
echo "Checking if Section 2 (Networking) is deployed..."
aws s3api head-object --bucket cfndev-envoy-proxy-poc-terraform-state --key 02-networking/terraform.tfstate --profile avive-cfndev-k8s > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Section 2 (Networking) state found - dependency satisfied"
else
    echo "✗ Section 2 (Networking) state not found"
    echo "Please deploy Section 2 first:"
    echo "  cd ../02-networking && ./deploy.sh apply"
    exit 1
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
        echo "Deploying EKS cluster infrastructure..."
        run_terraform "init -upgrade"
        run_terraform "plan"
        echo ""
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_terraform "apply"
            echo ""
            echo "✓ EKS cluster infrastructure deployed successfully!"
            echo ""
            echo "Kubeconfig has been automatically configured."
            echo "The kubeconfig path used was determined by:"
            echo "  1. KUBECONFIG environment variable (if set)"
            echo "  2. Default: /home/mark/.kube/config-cfndev-envoy-poc"
            echo ""
            echo "To use this cluster:"
            if [ -n "$KUBECONFIG" ]; then
                echo "  Your KUBECONFIG is already set to: $KUBECONFIG"
            else
                echo "  export KUBECONFIG=/home/mark/.kube/config-cfndev-envoy-poc"
            fi
            echo ""
            echo "Verify cluster status:"
            echo "  kubectl cluster-info"
            echo "  kubectl get nodes"
            echo ""
        else
            echo "Deployment cancelled by user"
            exit 0
        fi
        ;;
    "destroy")
        echo "WARNING: This will destroy the EKS cluster and all associated resources!"
        echo "This action cannot be undone and will affect any workloads running on the cluster."
        echo ""
        read -p "Are you sure you want to destroy the EKS cluster? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_terraform "destroy"
            echo "✓ EKS cluster infrastructure destroyed!"
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
        echo "Checking EKS cluster status..."
        echo ""
        echo "Terraform outputs:"
        terraform output -json | jq -r '.cluster_name.value' > /tmp/cluster_name 2>/dev/null || echo "envoy-poc" > /tmp/cluster_name
        CLUSTER_NAME=$(cat /tmp/cluster_name)
        echo "Cluster Name: $CLUSTER_NAME"
        echo ""
        echo "AWS EKS cluster status:"
        aws eks describe-cluster --name "$CLUSTER_NAME" --profile avive-cfndev-k8s --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' --output table 2>/dev/null || echo "Cluster not found or not accessible"
        echo ""
        echo "Kubeconfig configuration:"
        KUBECONFIG_PATH="${KUBECONFIG:-/home/mark/.kube/config-cfndev-envoy-poc}"
        if [ -f "$KUBECONFIG_PATH" ]; then
            echo "✓ Kubeconfig exists at: $KUBECONFIG_PATH"
            echo "To use: export KUBECONFIG=$KUBECONFIG_PATH"
            echo ""
            echo "Testing kubectl connection..."
            KUBECONFIG="$KUBECONFIG_PATH" kubectl cluster-info 2>/dev/null && echo "✓ kubectl connection successful" || echo "✗ kubectl connection failed"
        else
            echo "✗ Kubeconfig not found at: $KUBECONFIG_PATH"
            echo "Run deployment first or manually configure:"
            echo "  aws eks update-kubeconfig --name $CLUSTER_NAME --region us-west-2 --profile avive-cfndev-k8s --kubeconfig $KUBECONFIG_PATH"
        fi
        rm -f /tmp/cluster_name
        ;;
    *)
        echo "Usage: $0 [init|plan|apply|destroy|output|status]"
        echo ""
        echo "Commands:"
        echo "  init     - Initialize Terraform"
        echo "  plan     - Plan the deployment"
        echo "  apply    - Deploy the EKS cluster (default)"
        echo "  destroy  - Destroy the EKS cluster"
        echo "  output   - Show terraform outputs"
        echo "  status   - Check EKS cluster status"
        exit 1
        ;;
esac

echo "=== Section 3: EKS Cluster deployment completed ==="
