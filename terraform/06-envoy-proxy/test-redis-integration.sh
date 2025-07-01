#!/bin/bash

# Test Redis Integration and Connection Tracking
# This script tests the actual Redis integration via the HTTP proxy

set -e

echo "=== Testing Redis Integration with Real Updates ==="

# Function to execute Redis commands via HTTP proxy
redis_http_exec() {
    kubectl exec -i deployment/redis-http-proxy -- curl -s -X POST -H "Content-Type: text/plain" -d "$*" http://localhost:8080/redis
}

# Function to check if Redis HTTP proxy is ready
check_redis_proxy() {
    echo "🔍 Checking Redis HTTP proxy status..."
    if kubectl get pods -l app=redis-http-proxy --no-headers 2>/dev/null | grep -q "Running"; then
        echo "✓ Redis HTTP proxy pod is running"
        
        # Test health endpoint
        if kubectl exec deployment/redis-http-proxy -- curl -s http://localhost:8080/health >/dev/null 2>&1; then
            echo "✓ Redis HTTP proxy health check passed"
            return 0
        else
            echo "❌ Redis HTTP proxy health check failed"
            return 1
        fi
    else
        echo "❌ Redis HTTP proxy pod is not running"
        return 1
    fi
}

# Function to simulate connection tracking updates
simulate_connection_activity() {
    echo ""
    echo "🎯 Simulating real connection activity via Envoy Lua filter..."
    
    # Get current backend pods
    BACKEND_PODS=$(kubectl get pods -l app=envoy-poc-app-server -o jsonpath='{.items[*].status.podIP}' 2>/dev/null | tr ' ' '\n' | head -3)
    
    if [ -z "$BACKEND_PODS" ]; then
        echo "Using fallback pod IPs for simulation..."
        BACKEND_PODS="172.245.10.137
172.245.10.244
172.245.20.177"
    fi
    
    CURRENT_TIME=$(date +%s)
    
    for POD_IP in $BACKEND_PODS; do
        echo "Processing pod: $POD_IP"
        
        # Simulate connection establishment
        CONNECTIONS=$((RANDOM % 3 + 1))
        CONNECTION_ID="envoy-test-$CURRENT_TIME-$RANDOM"
        
        # Track established connection
        echo "  📝 Tracking connection: $CONNECTION_ID"
        redis_http_exec "SADD" "active_connections:$POD_IP" "$CONNECTION_ID"
        redis_http_exec "EXPIRE" "active_connections:$POD_IP" "3600"
        
        # Store connection details
        redis_http_exec "HMSET" "connection:$CONNECTION_ID" "pod_ip" "$POD_IP" "client_ip" "10.0.1.$((RANDOM % 255))" "established_time" "$CURRENT_TIME" "last_activity" "$CURRENT_TIME"
        redis_http_exec "EXPIRE" "connection:$CONNECTION_ID" "3600"
        
        # Update connection count
        COUNT=$(redis_http_exec "SCARD" "active_connections:$POD_IP")
        redis_http_exec "SET" "pod:established_count:$POD_IP" "$COUNT"
        redis_http_exec "EXPIRE" "pod:established_count:$POD_IP" "3600"
        
        # Update scaling metrics
        PRIORITY=$((10 - COUNT))
        redis_http_exec "HMSET" "pod:scaling_data:$POD_IP" "active_connections" "$COUNT" "last_updated" "$CURRENT_TIME" "scaling_priority" "$PRIORITY"
        redis_http_exec "EXPIRE" "pod:scaling_data:$POD_IP" "3600"
        
        # Add to scaling candidates
        redis_http_exec "ZADD" "scaling:candidates:scale_down" "$PRIORITY" "$POD_IP"
        
        echo "    ✓ Pod $POD_IP: $COUNT connections, priority $PRIORITY"
        
        # Simulate some rejections occasionally
        if [ $((RANDOM % 3)) -eq 0 ]; then
            BUCKET_5M=$((CURRENT_TIME / 300 * 300))
            redis_http_exec "ZINCRBY" "rate_limit_rejections:5m:$POD_IP" "1" "$BUCKET_5M"
            echo "    ⚠️  Rate limit rejection recorded"
        fi
    done
    
    # Set expiration for scaling candidates
    redis_http_exec "EXPIRE" "scaling:candidates:scale_down" "300"
    
    # Set readiness flags
    redis_http_exec "SET" "redis:status:connected" "true"
    redis_http_exec "EXPIRE" "redis:status:connected" "300"
    redis_http_exec "SET" "redis:status:ready_for_scaling" "true"
    redis_http_exec "EXPIRE" "redis:status:ready_for_scaling" "300"
    
    echo ""
    echo "✅ Connection activity simulation completed!"
}

# Function to show real-time updates
show_realtime_updates() {
    echo ""
    echo "📊 Real-time Redis Updates (press Ctrl+C to stop)..."
    echo ""
    
    for i in {1..10}; do
        echo "=== Update Cycle #$i ($(date)) ==="
        
        # Simulate new activity
        simulate_connection_activity
        
        # Show current state
        echo ""
        echo "📈 Current State:"
        
        # Check readiness
        READY=$(redis_http_exec "GET" "redis:status:ready_for_scaling")
        echo "  Ready for scaling: $READY"
        
        # Show connection counts
        echo "  Connection counts:"
        for POD_IP in 172.245.10.137 172.245.10.244 172.245.20.177; do
            COUNT=$(redis_http_exec "GET" "pod:established_count:$POD_IP" 2>/dev/null || echo "0")
            echo "    Pod $POD_IP: $COUNT connections"
        done
        
        echo ""
        echo "⏳ Waiting 30 seconds for next update cycle..."
        sleep 30
    done
}

# Main execution
echo "📋 Prerequisites check..."

# Check if Redis is running
if ! kubectl get deployment redis-connection-tracker >/dev/null 2>&1; then
    echo "❌ Redis deployment not found. Please run ./deploy-enhanced.sh first"
    exit 1
fi

# Check if Redis HTTP proxy is ready
if ! check_redis_proxy; then
    echo "❌ Redis HTTP proxy is not ready. Please ensure it's deployed and healthy"
    exit 1
fi

echo ""
echo "🎯 Choose an option:"
echo "1. Run a single update cycle test"
echo "2. Run continuous real-time updates (10 cycles)"
echo "3. Just set readiness flags"
echo ""
read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        simulate_connection_activity
        echo ""
        echo "🎯 Run './query-scaling-metrics.sh' to see the results"
        ;;
    2)
        show_realtime_updates
        ;;
    3)
        echo "Setting readiness flags..."
        redis_http_exec "SET" "redis:status:connected" "true"
        redis_http_exec "EXPIRE" "redis:status:connected" "300"
        redis_http_exec "SET" "redis:status:ready_for_scaling" "true"
        redis_http_exec "EXPIRE" "redis:status:ready_for_scaling" "300"
        echo "✅ Readiness flags set"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "✅ Test completed! Use './query-scaling-metrics.sh' to view current state"
