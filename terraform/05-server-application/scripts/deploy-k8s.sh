#!/bin/bash

# Kubernetes Deployment Script for Server Application
# This script deploys the WebSocket server to EKS cluster

set -e

REGION=${1:-us-west-2}
PROFILE=${2:-avive-cfndev-k8s}
CLUSTER_NAME=${3:-envoy-poc}
ECR_REPO_NAME=${4:-cfndev-envoy-proxy-poc-app}
IMAGE_TAG=${5:-latest}

echo "=== Server Application Kubernetes Deployment ==="
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo "Cluster: $CLUSTER_NAME"
echo "ECR Repository: $ECR_REPO_NAME"
echo "Image Tag: $IMAGE_TAG"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../k8s"

# Get AWS account ID and construct ECR URL
echo "Getting AWS account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get AWS account ID"
    exit 1
fi

ECR_REPO_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO_NAME"
echo "ECR Repository URL: $ECR_REPO_URL"

# Check kubectl configuration
echo "Checking kubectl configuration..."
kubectl cluster-info > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    echo "Run: aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE"
    exit 1
fi
echo "✓ kubectl is configured and cluster is accessible"

# Verify we're connected to the right cluster
CURRENT_CLUSTER=$(kubectl config current-context | grep "$CLUSTER_NAME" || echo "")
if [ -z "$CURRENT_CLUSTER" ]; then
    echo "Warning: Current context does not seem to match expected cluster name"
    echo "Current context: $(kubectl config current-context)"
    echo "Expected cluster: $CLUSTER_NAME"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if ECR image exists
echo "Checking if ECR image exists..."
aws ecr describe-images \
    --repository-name "$ECR_REPO_NAME" \
    --image-ids imageTag="$IMAGE_TAG" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --output text > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "Error: Image $ECR_REPO_URL:$IMAGE_TAG does not exist in ECR"
    echo "Build and push the image first using: ./scripts/build-and-push.sh"
    exit 1
fi
echo "✓ ECR image exists: $ECR_REPO_URL:$IMAGE_TAG"

# Create temporary deployment file with ECR URL
echo "Preparing Kubernetes deployment manifests..."
TEMP_DEPLOYMENT="/tmp/server-deployment-$(date +%s).yaml"

# Replace ECR repository URL in deployment manifest
sed "s|\${ECR_REPOSITORY_URL}|$ECR_REPO_URL|g" "$K8S_DIR/deployment.yaml" > "$TEMP_DEPLOYMENT"

echo "Deployment manifest prepared: $TEMP_DEPLOYMENT"

# Apply the deployment
echo "Deploying to Kubernetes..."
kubectl apply -f "$TEMP_DEPLOYMENT"

if [ $? -ne 0 ]; then
    echo "Error: Failed to apply Kubernetes deployment"
    rm -f "$TEMP_DEPLOYMENT"
    exit 1
fi

echo "✓ Kubernetes deployment applied successfully"

# Clean up temporary file
rm -f "$TEMP_DEPLOYMENT"

# Wait for deployment to be ready
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/envoy-poc-app-server --timeout=300s

if [ $? -ne 0 ]; then
    echo "Error: Deployment rollout failed or timed out"
    echo "Check deployment status with: kubectl get pods -l app=envoy-poc-app-server"
    exit 1
fi

echo "✓ Deployment is ready"
echo ""

# Display deployment status
echo "Deployment Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Show deployment details
kubectl get deployment envoy-poc-app-server -o wide

echo ""
echo "Pods:"
kubectl get pods -l app=envoy-poc-app-server -o wide

echo ""
echo "Service:"
kubectl get service envoy-poc-app-server-service -o wide

echo ""
echo "Recent events:"
kubectl get events --sort-by='.lastTimestamp' | grep envoy-poc-app-server | tail -5

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Useful commands:"
echo "- Check pods: kubectl get pods -l app=envoy-poc-app-server"
echo "- View logs: kubectl logs -l app=envoy-poc-app-server -f"
echo "- Describe deployment: kubectl describe deployment envoy-poc-app-server"
echo "- Port forward for testing: kubectl port-forward service/envoy-poc-app-server-service 8080:80"
echo ""
echo "Service endpoint: envoy-poc-app-server-service.default.svc.cluster.local:80"
