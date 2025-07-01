#!/bin/bash

# Update Available Backend Pods in Redis
# This script discovers backend pod IPs and updates Redis for Lua script consumption

set -e

NAMESPACE="default"
SERVICE_NAME="envoy-poc-app-server-service"
REDIS_HTTP_PROXY="http://localhost:8080/redis"

echo "=== Updating Available Backend Pods in Redis ==="

# Function to execute Redis commands via HTTP proxy
redis_http_exec() {
    local cmd="$*"
    curl -s -X POST -d "$cmd" "$REDIS_HTTP_PROXY" 2>/dev/null || echo "ERROR"
}

# Check if HTTP proxy is available
if ! curl -s http://localhost:8080/health >/dev/null 2>&1; then
    echo "❌ Redis HTTP proxy not accessible on localhost:8080"
    echo "   Please run: kubectl port-forward svc/redis-http-proxy 8080:8080"
    exit 1
fi

# Get backend pod IPs dynamically
echo "🔍 Discovering backend pod IPs..."
POD_IPS=$(kubectl get endpoints "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | tr ' ' ',')

if [[ -z "$POD_IPS" ]]; then
    echo "❌ No backend pod IPs found for service $SERVICE_NAME"
    exit 1
fi

echo "✅ Found backend pod IPs: $POD_IPS"

# Update Redis with available pod IPs
echo "📝 Updating Redis with available pod IPs..."
RESULT=$(redis_http_exec SET "available_pods" "$POD_IPS")
if [[ "$RESULT" == "OK" ]]; then
    echo "✅ Successfully updated Redis with pod IPs"
else
    echo "❌ Failed to update Redis: $RESULT"
    exit 1
fi

# Set expiration (refresh every 5 minutes)
redis_http_exec EXPIRE "available_pods" 300

# Verify the update
STORED_IPS=$(redis_http_exec GET "available_pods")
echo "🔍 Verified stored pod IPs: $STORED_IPS"

echo "✅ Available pod IPs updated successfully in Redis"
echo "   Pod IPs: $POD_IPS"
echo "   Run this script periodically to keep pod list current"
