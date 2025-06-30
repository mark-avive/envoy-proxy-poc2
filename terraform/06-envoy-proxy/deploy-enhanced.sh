#!/bin/bash

# Deploy Redis and Enhanced Envoy with Connection Tracking
# This script deploys the Redis backend and updated Envoy proxy with Lua-based connection tracking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

echo "=== Deploying Redis Connection Tracker and Enhanced Envoy Proxy ==="

# Check if kubectl is available and configured
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ kubectl is not configured or cluster is not accessible"
    echo "Please ensure your kubeconfig is set up correctly"
    exit 1
fi

echo "✓ Kubernetes cluster is accessible"

# Function to wait for deployment to be ready
wait_for_deployment() {
    local deployment_name=$1
    local namespace=${2:-default}
    local timeout=${3:-300}
    
    echo "⏳ Waiting for deployment '$deployment_name' to be ready..."
    if kubectl wait --for=condition=available deployment/$deployment_name -n $namespace --timeout=${timeout}s; then
        echo "✓ Deployment '$deployment_name' is ready"
        return 0
    else
        echo "❌ Deployment '$deployment_name' failed to become ready within ${timeout} seconds"
        return 1
    fi
}

# Function to check pod readiness
check_pod_readiness() {
    local label_selector=$1
    local namespace=${2:-default}
    
    echo "🔍 Checking pod readiness for selector: $label_selector"
    local ready_pods=$(kubectl get pods -l "$label_selector" -n $namespace --no-headers 2>/dev/null | grep "Running" | wc -l)
    local total_pods=$(kubectl get pods -l "$label_selector" -n $namespace --no-headers 2>/dev/null | wc -l)
    
    echo "   Ready pods: $ready_pods/$total_pods"
    return $ready_pods
}

# Deploy Redis first
echo ""
echo "📦 Deploying Redis Connection Tracker..."
kubectl apply -f "$K8S_DIR/redis-deployment.yaml"

# Wait for Redis to be ready
wait_for_deployment "redis-connection-tracker"

# Verify Redis is accessible
echo "🔍 Verifying Redis connectivity..."
if kubectl run redis-test --image=redis:7-alpine --rm -i --restart=Never -- redis-cli -h redis-connection-tracker.default.svc.cluster.local ping >/dev/null 2>&1; then
    echo "✓ Redis is accessible and responding"
else
    echo "⚠️  Redis connectivity test failed, but continuing with deployment"
fi

# Deploy updated Envoy configuration
echo ""
echo "📦 Deploying Enhanced Envoy Proxy with Lua Connection Tracking..."
kubectl apply -f "$K8S_DIR/deployment.yaml"

# Wait for Envoy deployment to be ready
wait_for_deployment "envoy-proxy"

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "=== Deployment Summary ==="
echo "✓ Redis Connection Tracker: deployed and ready"
echo "✓ Enhanced Envoy Proxy: deployed with Lua-based connection tracking"
echo "✓ Per-pod connection limits: 2 connections maximum per backend pod"
echo "✓ Rate limiting: 1 connection per second per Envoy instance"
echo "✓ Scaling metrics: Available via Redis for custom scaling decisions"
echo ""

# Show current status
echo "=== Current Status ==="
echo ""
echo "Redis Pods:"
kubectl get pods -l app=redis-connection-tracker -o wide

echo ""
echo "Envoy Proxy Pods:"
kubectl get pods -l app=envoy-proxy -o wide

echo ""
echo "Services:"
kubectl get services -l 'app in (redis-connection-tracker,envoy-proxy)'

echo ""
echo "=== Next Steps ==="
echo "1. Monitor Envoy logs for connection tracking:"
echo "   kubectl logs -f deployment/envoy-proxy"
echo ""
echo "2. Check Redis data (connection counts, metrics):"
echo "   kubectl exec -it deployment/redis-connection-tracker -- redis-cli"
echo ""
echo "3. Test connection limits by running multiple client connections"
echo ""
echo "4. Access scaling metrics via Redis for custom scaling decisions"
echo ""
echo "5. Monitor with port-forward to Envoy admin interface:"
echo "   kubectl port-forward deployment/envoy-proxy 9901:9901"
echo "   curl http://localhost:9901/stats | grep -E '(lua|redis)'"
echo ""

# Optional: Show recent logs
read -p "📋 Show recent Envoy logs? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "=== Recent Envoy Logs ==="
    kubectl logs deployment/envoy-proxy --tail=20 | grep -E "(REDIS-TRACKER|lua)" || echo "No Lua/Redis logs found yet"
fi

echo ""
echo "🚀 Enhanced Envoy Proxy with Redis Connection Tracking is now active!"
