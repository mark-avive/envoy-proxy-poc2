#!/bin/bash

# Deploy script for 06a-envoy-proxy with atomic connection tracking
# Uses direct Redis connections and atomic Lua scripts

set -e

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../../config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    echo "Sourcing configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Configuration
NAMESPACE=${NAMESPACE:-default}
AWS_REGION=${AWS_REGION:-us-west-2}
AWS_PROFILE=${AWS_PROFILE:-avive-cfndev-k8s}
CLUSTER_NAME=${CLUSTER_NAME:-envoy-poc}

echo "=================================================================="
echo "             06a-ENVOY-PROXY ATOMIC DEPLOYMENT"
echo "=================================================================="
echo "Namespace: $NAMESPACE"
echo "AWS Region: $AWS_REGION"
echo "AWS Profile: $AWS_PROFILE"
echo "Cluster: $CLUSTER_NAME"
echo "=================================================================="

# Set AWS profile and configure kubectl context
export AWS_PROFILE="$AWS_PROFILE"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# Verify connection to cluster
echo "Verifying cluster connection..."
kubectl cluster-info --context="arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$CLUSTER_NAME" || {
    echo "ERROR: Failed to connect to EKS cluster"
    exit 1
}

# Initialize Terraform
echo "Initializing Terraform..."
cd "$SCRIPT_DIR/.."
terraform init

# Plan the deployment
echo "Planning Terraform deployment..."
terraform plan

# Apply the deployment
echo "Applying Terraform deployment..."
terraform apply -auto-approve

# Wait for deployments to be ready
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/redis-atomic -n "$NAMESPACE"
kubectl wait --for=condition=available --timeout=300s deployment/envoy-proxy-atomic -n "$NAMESPACE"

# Display deployment status
echo "=================================================================="
echo "                    DEPLOYMENT STATUS"
echo "=================================================================="
kubectl get pods -n "$NAMESPACE" -l app=redis-atomic
kubectl get pods -n "$NAMESPACE" -l app=envoy-proxy-atomic
kubectl get svc -n "$NAMESPACE" envoy-proxy-atomic-service
kubectl get svc -n "$NAMESPACE" redis-atomic-service

# Get Envoy admin and proxy URLs
echo "=================================================================="
echo "                    SERVICE ENDPOINTS"
echo "=================================================================="
LOAD_BALANCER_HOSTNAME=$(kubectl get service envoy-proxy-atomic-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

if [[ "$LOAD_BALANCER_HOSTNAME" != "pending" && "$LOAD_BALANCER_HOSTNAME" != "" ]]; then
    echo "Envoy Proxy URL: http://$LOAD_BALANCER_HOSTNAME"
    echo "Envoy Admin URL: http://$LOAD_BALANCER_HOSTNAME:9901"
    echo "WebSocket Metrics: http://$LOAD_BALANCER_HOSTNAME/websocket/metrics"
else
    echo "Load Balancer still provisioning. Check status with:"
    echo "kubectl get service envoy-proxy-atomic-service -n $NAMESPACE -w"
fi

# Test Redis connectivity
echo "=================================================================="
echo "                    REDIS CONNECTIVITY TEST"
echo "=================================================================="
kubectl run redis-test --image=redis:7-alpine --rm -it --restart=Never -n "$NAMESPACE" -- \
    redis-cli -h redis-atomic-service -p 6379 ping || echo "Redis connectivity test failed"

# Display logs for debugging
echo "=================================================================="
echo "                    RECENT LOGS"
echo "=================================================================="
echo "Redis logs (last 10 lines):"
kubectl logs -n "$NAMESPACE" -l app=redis-atomic --tail=10 || echo "No Redis logs available"

echo ""
echo "Envoy logs (last 10 lines):"
kubectl logs -n "$NAMESPACE" -l app=envoy-proxy-atomic --tail=10 || echo "No Envoy logs available"

echo "=================================================================="
echo "                    DEPLOYMENT COMPLETE"
echo "=================================================================="
echo "To test the atomic connection tracking:"
echo "1. Wait for Load Balancer to be ready"
echo "2. Use WebSocket client to connect to: ws://$LOAD_BALANCER_HOSTNAME/"
echo "3. Monitor metrics: curl http://$LOAD_BALANCER_HOSTNAME/websocket/metrics"
echo "4. Check Envoy admin: curl http://$LOAD_BALANCER_HOSTNAME:9901/stats"
echo ""
echo "To monitor the deployment:"
echo "kubectl logs -f -n $NAMESPACE -l app=envoy-proxy-atomic"
echo "kubectl exec -it -n $NAMESPACE deployment/redis-atomic -- redis-cli monitor"
echo "=================================================================="
