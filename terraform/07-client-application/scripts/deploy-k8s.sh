#!/bin/bash
set -e

# WebSocket Client Application - Kubernetes Deployment
echo "=== WebSocket Client Kubernetes Deployment ==="

# Configuration
REGION=${AWS_REGION:-us-west-2}
PROFILE=${AWS_PROFILE:-avive-cfndev-k8s}
CLUSTER_NAME=${CLUSTER_NAME:-envoy-poc}
ECR_REPOSITORY=${ECR_REPOSITORY}
IMAGE_TAG=${IMAGE_TAG:-latest}
NAMESPACE=${NAMESPACE:-default}
APP_NAME=${APP_NAME:-websocket-client}
REPLICAS=${REPLICAS:-10}

echo "Region: $REGION"
echo "Profile: $PROFILE" 
echo "Cluster: $CLUSTER_NAME"

# Check if ECR repository is provided
if [ -z "$ECR_REPOSITORY" ]; then
    echo "❌ Error: ECR_REPOSITORY environment variable is required"
    exit 1
fi

# Configure kubectl
echo "Configuring kubectl..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE

# Verify kubectl configuration
echo "Checking kubectl configuration..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Error: Unable to connect to Kubernetes cluster"
    exit 1
fi
echo "✓ kubectl is configured and cluster is accessible"

# Get ECR image URI
IMAGE_URI="$ECR_REPOSITORY:$IMAGE_TAG"
echo "Using image: $IMAGE_URI"

# Check if server application is running (prerequisite)
echo "Checking prerequisite services..."
if ! kubectl get service envoy-poc-app-server-service >/dev/null 2>&1; then
    echo "⚠ Warning: Server application service not found"
    echo "Make sure Section 5 (Server Application) is deployed first"
fi

if ! kubectl get service envoy-proxy-service >/dev/null 2>&1; then
    echo "⚠ Warning: Envoy proxy service not found"
    echo "Make sure Section 6 (Envoy Proxy) is deployed first"
fi

# Prepare deployment manifest
echo "Preparing deployment manifest..."
TEMP_MANIFEST=$(mktemp /tmp/client-deployment-XXXXX.yaml)
sed "s|IMAGE_REGISTRY_PLACEHOLDER|$IMAGE_URI|g" k8s/deployment.yaml > $TEMP_MANIFEST

echo "Deployment manifest prepared: $TEMP_MANIFEST"

# Deploy to Kubernetes
echo "Deploying client application to Kubernetes..."
kubectl apply -f $TEMP_MANIFEST

echo "✓ Kubernetes deployment applied successfully"

# Wait for deployment to be ready
echo "Waiting for client deployment to be ready..."
if kubectl wait --for=condition=available --timeout=300s deployment/envoy-poc-client-app; then
    echo "✓ Client deployment is ready"
else
    echo "⚠ Warning: Deployment readiness check timed out"
    echo "Check deployment status manually with: kubectl get pods -l app=envoy-poc-client-app"
fi

# Show deployment status
echo ""
echo "Deployment Status:"
echo "=================="
kubectl get deployment envoy-poc-client-app
echo ""
echo "Service Status:"
echo "==============="
kubectl get service envoy-poc-client-service
echo ""
echo "Pod Status:"
echo "==========="
kubectl get pods -l app=envoy-poc-client-app

# Clean up temp file
rm -f $TEMP_MANIFEST

echo ""
echo "✅ Client application deployment completed successfully"
echo ""
echo "Monitor logs with:"
echo "kubectl logs -l app=envoy-poc-client-app -f"
