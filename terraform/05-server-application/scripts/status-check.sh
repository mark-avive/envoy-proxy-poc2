#!/bin/bash

# Server Application Status Check Script
# This script checks the status of the WebSocket server application

set -e

REGION=${1:-us-west-2}
PROFILE=${2:-avive-cfndev-k8s}
CLUSTER_NAME=${3:-envoy-poc}

echo "=== Server Application Status Check ==="
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo "Cluster: $CLUSTER_NAME"
echo ""

# Check kubectl configuration
echo "Checking kubectl configuration..."
kubectl cluster-info > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    echo "Run: aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE"
    exit 1
fi
echo "✓ kubectl is configured and cluster is accessible"
echo ""

# Check deployment status
echo "Deployment Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if deployment exists
kubectl get deployment envoy-poc-app-server > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Deployment 'envoy-poc-app-server' not found"
    echo "Deploy the application first using: ./scripts/deploy-k8s.sh"
    exit 1
fi

# Show deployment status
kubectl get deployment envoy-poc-app-server -o wide
echo ""

# Show replica set status
echo "ReplicaSet Status:"
kubectl get replicaset -l app=envoy-poc-app-server -o wide
echo ""

# Show pod status
echo "Pod Status:"
kubectl get pods -l app=envoy-poc-app-server -o wide
echo ""

# Check pod health
echo "Pod Health Details:"
POD_COUNT=$(kubectl get pods -l app=envoy-poc-app-server --no-headers | wc -l)
READY_COUNT=$(kubectl get pods -l app=envoy-poc-app-server --no-headers | grep "1/1" | wc -l)
RUNNING_COUNT=$(kubectl get pods -l app=envoy-poc-app-server --no-headers | grep "Running" | wc -l)

echo "Total Pods: $POD_COUNT"
echo "Ready Pods: $READY_COUNT"
echo "Running Pods: $RUNNING_COUNT"

if [ "$READY_COUNT" -eq 4 ] && [ "$RUNNING_COUNT" -eq 4 ]; then
    echo "✅ All pods are healthy and ready"
else
    echo "⚠️  Some pods may not be ready or running"
fi
echo ""

# Show service status
echo "Service Status:"
kubectl get service envoy-poc-app-server-service -o wide
echo ""

# Check service endpoints
echo "Service Endpoints:"
kubectl get endpoints envoy-poc-app-server-service -o wide
echo ""

# Show recent events
echo "Recent Events (last 10):"
kubectl get events --sort-by='.lastTimestamp' | grep envoy-poc-app-server | tail -10
echo ""

# Resource usage (if metrics-server is available)
echo "Resource Usage:"
kubectl top pods -l app=envoy-poc-app-server 2>/dev/null || echo "Metrics not available (metrics-server may not be installed)"
echo ""

# Show logs from one pod (latest)
echo "Recent Logs (from latest pod):"
LATEST_POD=$(kubectl get pods -l app=envoy-poc-app-server --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
if [ -n "$LATEST_POD" ]; then
    echo "Logs from pod: $LATEST_POD"
    kubectl logs "$LATEST_POD" --tail=20 2>/dev/null || echo "Unable to fetch logs"
else
    echo "No pods found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "=== Status Check Complete ==="
echo ""
echo "Useful commands:"
echo "- Watch pods: kubectl get pods -l app=envoy-poc-app-server -w"
echo "- Stream logs: kubectl logs -l app=envoy-poc-app-server -f"
echo "- Describe deployment: kubectl describe deployment envoy-poc-app-server"
echo "- Describe service: kubectl describe service envoy-poc-app-server-service"
echo "- Test connectivity: kubectl port-forward service/envoy-poc-app-server-service 8080:80"
