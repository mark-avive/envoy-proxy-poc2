#!/bin/bash

# Terraform deployment script for Section 6: Enhanced Envoy Proxy Setup
# This script deploys Envoy proxy with direct Redis support and custom image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_CONFIG_FILE="$SCRIPT_DIR/deploy-config.env"

# Load deployment configuration from file
if [[ -f "$DEPLOY_CONFIG_FILE" ]]; then
    echo "📋 Loading deployment configuration from: $DEPLOY_CONFIG_FILE"
    source "$DEPLOY_CONFIG_FILE"
else
    echo "❌ Deployment configuration file not found: $DEPLOY_CONFIG_FILE"
    echo "Please create the configuration file with required variables."
    exit 1
fi

cd "$SCRIPT_DIR"

echo "=== Enhanced Envoy Proxy POC - Section 6: Envoy Proxy Setup ==="
echo "Working directory: $(pwd)"
echo "Project: $PROJECT_NAME ($ENVIRONMENT)"
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
aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ AWS CLI profile '$AWS_PROFILE' is configured and accessible"
else
    echo "✗ AWS CLI profile '$AWS_PROFILE' is not configured or accessible"
    echo "Please configure your AWS SSO profile before proceeding"
    exit 1
fi
echo ""

# Check kubectl configuration
echo "Checking kubectl configuration..."
kubectl cluster-info > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ kubectl is configured and cluster is accessible"
    CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2 2>/dev/null || echo "unknown")
    echo "  Current cluster: $CLUSTER_NAME"
else
    echo "✗ kubectl is not configured or cluster is not accessible"
    echo "Please ensure KUBECONFIG is set and EKS cluster is accessible"
    exit 1
fi
echo ""

# Check prerequisite sections
echo "Checking prerequisite sections..."

# Check networking
aws s3api head-object --bucket cfndev-envoy-proxy-poc-terraform-state --key 02-networking/terraform.tfstate --profile avive-cfndev-k8s > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Section 2 (Networking) state found - dependency satisfied"
else
    echo "✗ Section 2 (Networking) state not found"
    echo "Please deploy Section 2 first: cd ../02-networking && ./deploy.sh apply"
    exit 1
fi

# Check EKS cluster  
aws s3api head-object --bucket cfndev-envoy-proxy-poc-terraform-state --key 03-eks-cluster/terraform.tfstate --profile avive-cfndev-k8s > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Section 3 (EKS Cluster) state found - dependency satisfied"
else
    echo "✗ Section 3 (EKS Cluster) state not found"
    echo "Please deploy Section 3 first: cd ../03-eks-cluster && ./deploy.sh apply"
    exit 1
fi

# Check server application
aws s3api head-object --bucket cfndev-envoy-proxy-poc-terraform-state --key 05-server-application/terraform.tfstate --profile avive-cfndev-k8s > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Section 5 (Server Application) state found - dependency satisfied"
else
    echo "✗ Section 5 (Server Application) state not found"
    echo "Please deploy Section 5 first: cd ../05-server-application && ./deploy.sh apply"
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
        echo "Deploying Envoy Proxy and AWS Load Balancer Controller..."
        run_terraform "init -upgrade"
        run_terraform "plan"
        echo ""
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_terraform "apply"
            echo ""
            echo "✓ Envoy Proxy infrastructure deployed successfully!"
            
            # Ensure Envoy ConfigMap is up-to-date with correct configuration
            echo "Updating Envoy ConfigMap with latest configuration..."
            if kubectl get configmap envoy-config >/dev/null 2>&1; then
                echo "Deleting existing Envoy ConfigMap..."
                kubectl delete configmap envoy-config
            fi
            echo "Creating Envoy ConfigMap from generated configuration..."
            kubectl create configmap envoy-config --from-file=envoy.yaml=k8s/envoy-config.yaml
            echo "✓ Envoy ConfigMap updated successfully!"
            
            # Deploy Redis connection tracker
            echo ""
            echo "Deploying Redis connection tracker for enhanced connection management..."
            kubectl apply -f k8s/redis-deployment.yaml
            
            # Deploy Redis HTTP proxy for Lua script integration
            echo "Deploying Redis HTTP proxy..."
            kubectl apply -f k8s/redis-http-proxy.yaml
            
            # Update Lua ConfigMap with connection tracking script
            echo "Updating Lua ConfigMap with unlimited connection tracking script..."
            ./update-lua-configmap.sh
            
            echo "Waiting for Redis to be ready..."
            if kubectl wait --for=condition=available deployment/redis-connection-tracker --timeout=120s; then
                echo "✓ Redis connection tracker deployed successfully!"
            else
                echo "⚠ Redis deployment may still be in progress"
            fi
            
            echo "Waiting for Redis HTTP proxy to be ready..."
            if kubectl wait --for=condition=available deployment/redis-http-proxy --timeout=120s; then
                echo "✓ Redis HTTP proxy deployed successfully!"
            else
                echo "⚠ Redis HTTP proxy deployment may still be in progress"
            fi
            
            # Restart Envoy pods to pick up new configuration and Lua script
            echo "Restarting Envoy pods to load updated configuration and Lua script..."
            kubectl rollout restart deployment/envoy-proxy
            kubectl rollout status deployment/envoy-proxy --timeout=120s
            echo "✓ Envoy pods restarted with updated configuration!"
            
            echo ""
            echo "Deployment includes:"
            echo "  - AWS Load Balancer Controller installed via Helm"
            echo "  - Envoy proxy deployed with 2 replicas and Redis-based connection tracking"
            echo "  - Redis connection tracker for global per-pod connection limits"
            echo "  - ALB Ingress configured for external access"
            echo "  - Enhanced WebSocket connection limiting and rate limiting"
            echo "  - Scaling metrics and connection tracking via Redis"
            echo ""
            echo "Getting ALB endpoint..."
            sleep 30  # Wait a moment for ALB to be ready
            ALB_ENDPOINT=$(kubectl get ingress envoy-proxy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
            if [ -n "$ALB_ENDPOINT" ] && [ "$ALB_ENDPOINT" != "null" ]; then
                echo "✓ ALB Endpoint: http://$ALB_ENDPOINT"
                echo "✓ WebSocket Endpoint: ws://$ALB_ENDPOINT"
            else
                echo "⚠ ALB is still provisioning. Check status with:"
                echo "  kubectl get ingress envoy-proxy-ingress"
            fi
            echo ""
            echo "Next steps:"
            echo "1. Wait for ALB to be fully provisioned (2-3 minutes)"
            echo "2. Test WebSocket connectivity via ALB endpoint"
            echo "3. Monitor Envoy admin interface: kubectl port-forward deployment/envoy-proxy 9901:9901"
            echo "4. Deploy client application: cd ../07-client-application && ./deploy.sh apply"
            echo ""
        else
            echo "Deployment cancelled by user"
            exit 0
        fi
        ;;
    "destroy")
        echo "WARNING: This will destroy Envoy Proxy, Redis, ALB Controller, and associated resources!"
        echo "This will also delete the Application Load Balancer and all connection tracking data."
        echo ""
        read -p "Are you sure you want to destroy the Envoy Proxy setup? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Clean up Redis components first
            echo "Cleaning up Redis connection tracker and HTTP proxy..."
            kubectl delete -f k8s/redis-deployment.yaml --ignore-not-found=true
            kubectl delete -f k8s/redis-http-proxy.yaml --ignore-not-found=true
            
            run_terraform "destroy"
            echo "✓ Envoy Proxy infrastructure and Redis destroyed!"
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
        echo "Checking Envoy Proxy deployment status..."
        echo ""
        ./scripts/status-check.sh
        ;;
    *)
        echo "Usage: $0 [init|plan|apply|destroy|output|status] or $0 --destroy"
        echo ""
        echo "Commands:"
        echo "  init     - Initialize Terraform"
        echo "  plan     - Plan the deployment"
        echo "  apply    - Deploy Envoy Proxy and ALB Controller (default)"
        echo "  destroy  - Destroy Envoy Proxy and ALB Controller"
        echo "  output   - Show terraform outputs"
        echo "  status   - Check deployment status and connectivity"
        echo ""
        echo "Flags:"
        echo "  --destroy - Same as 'destroy' command"
        exit 1
        ;;
esac

echo "=== Section 6: Envoy Proxy deployment completed ==="
