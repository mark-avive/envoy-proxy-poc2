#!/bin/bash
set -e

# WebSocket Client Application - Status Check
echo "=== WebSocket Client Application Status Check ==="

# Configuration
REGION=${AWS_REGION:-us-west-2}
PROFILE=${AWS_PROFILE:-avive-cfndev-k8s}
CLUSTER_NAME=${CLUSTER_NAME:-envoy-poc}
NAMESPACE=${NAMESPACE:-default}
APP_NAME=${APP_NAME:-websocket-client}

echo "Region: $REGION"
echo "Profile: $PROFILE"
echo "Cluster: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"

# Configure kubectl
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE >/dev/null 2>&1

# Check if kubectl is working
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Error: Unable to connect to Kubernetes cluster"
    exit 1
fi

echo ""
echo "Deployment Status:"
echo "=================="
kubectl get deployment envoy-poc-client-app -o wide

echo ""
echo "ReplicaSet Status:"
echo "=================="
kubectl get replicaset -l app=envoy-poc-client-app

echo ""
echo "Pod Status:"
echo "==========="
kubectl get pods -l app=envoy-poc-client-app -o wide

echo ""
echo "Service Status:"
echo "==============="
kubectl get service envoy-poc-client-service

echo ""
echo "Recent Events:"
echo "=============="
kubectl get events --field-selector involvedObject.name=envoy-poc-client-app --sort-by='.lastTimestamp' | tail -10

echo ""
echo "Pod Resource Usage (if metrics-server is available):"
echo "===================================================="
if kubectl top pods -l app=envoy-poc-client-app >/dev/null 2>&1; then
    kubectl top pods -l app=envoy-poc-client-app
else
    echo "Metrics server not available"
fi

echo ""
echo "Connection Test to Envoy:"
echo "========================="
# Try to test connection from one of the client pods
POD_NAME=$(kubectl get pods -l app=envoy-poc-client-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    echo "Testing connectivity from pod: $POD_NAME"
    if kubectl exec $POD_NAME -- wget -q --spider --timeout=5 http://envoy-proxy-service.default.svc.cluster.local:80 2>/dev/null; then
        echo "✅ Can reach Envoy service"
    else
        echo "⚠ Cannot reach Envoy service"
    fi
else
    echo "No client pods found"
fi

echo ""
echo "Recent Client Logs (last 20 lines):"
echo "===================================="
kubectl logs -l app=envoy-poc-client-app --tail=20 --prefix=true | head -50

echo ""
echo "Health Check Summary:"
echo "===================="
TOTAL_PODS=$(kubectl get pods -l app=envoy-poc-client-app --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods -l app=envoy-poc-client-app --no-headers | grep Running | wc -l)
READY_PODS=$(kubectl get pods -l app=envoy-poc-client-app --no-headers | awk '{print $2}' | grep -c "1/1" || echo "0")

echo "Total Pods: $TOTAL_PODS"
echo "Running Pods: $RUNNING_PODS"
echo "Ready Pods: $READY_PODS"

if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
    echo "✅ All client pods are running and ready"
    exit 0
elif [ "$RUNNING_PODS" -gt 0 ]; then
    echo "⚠ Some client pods are not ready"
    exit 0
else
    echo "❌ No client pods are running"
    exit 1
fi
