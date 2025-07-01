#!/bin/bash

# Test Redis Data Population Script
# This script populates Redis with realistic sample data to demonstrate the scaling system

set -e

echo "=== Populating Redis with Sample Connection Tracking Data ==="

# Get actual pod IPs from the running backend pods
BACKEND_PODS=$(kubectl get pods -l app=envoy-poc-app-server -o jsonpath='{.items[*].status.podIP}' 2>/dev/null || echo "172.245.10.137 172.245.10.244 172.245.20.177 172.245.10.144 172.245.20.117")

echo "Backend pods found: $BACKEND_PODS"

# Function to execute Redis commands
redis_exec() {
    kubectl exec -i deployment/redis-connection-tracker -- redis-cli "$@"
}

# Set readiness flags
echo "Setting readiness flags..."
redis_exec SET "redis:status:connected" "true"
redis_exec EXPIRE "redis:status:connected" 1800  # 30 minutes

redis_exec SET "redis:status:ready_for_scaling" "true"
redis_exec EXPIRE "redis:status:ready_for_scaling" 1800  # 30 minutes

redis_exec HMSET "redis:readiness:quality" \
    "confidence_level" "high" \
    "data_completeness_pct" "98" \
    "last_full_refresh" "$(date +%s)" \
    "pods_reporting" "5"
redis_exec EXPIRE "redis:readiness:quality" 1800  # 30 minutes

# Populate connection data for each pod
echo "Setting up pod connection data..."

CURRENT_TIME=$(date +%s)
PRIORITY_SCORE=10

for POD_IP in $BACKEND_PODS; do
    # Random connection count (0-3)
    CONNECTIONS=$((RANDOM % 4))
    
    # Set established connection count
    redis_exec SET "pod:established_count:$POD_IP" "$CONNECTIONS"
    redis_exec EXPIRE "pod:established_count:$POD_IP" 1800  # 30 minutes
    
    # Create active connections set
    for ((i=1; i<=CONNECTIONS; i++)); do
        CONNECTION_ID="envoy-$(hostname)-$CURRENT_TIME-$i"
        redis_exec SADD "active_connections:$POD_IP" "$CONNECTION_ID"
        
        # Store connection details
        redis_exec HMSET "connection:$CONNECTION_ID" \
            "pod_ip" "$POD_IP" \
            "client_ip" "10.0.$((RANDOM % 255)).$((RANDOM % 255))" \
            "established_time" "$((CURRENT_TIME - RANDOM % 3600))" \
            "last_activity" "$CURRENT_TIME" \
            "user_agent" "WebSocket-Client-1.0"
        redis_exec EXPIRE "connection:$CONNECTION_ID" 1800  # 30 minutes
    done
    redis_exec EXPIRE "active_connections:$POD_IP" 1800  # 30 minutes
    
    # Calculate priority (lower connections = higher priority for scale down)
    PRIORITY_SCORE=$((10 - CONNECTIONS))
    
    # Set detailed scaling metrics
    redis_exec HMSET "pod:scaling_data:$POD_IP" \
        "active_connections" "$CONNECTIONS" \
        "scaling_priority" "$PRIORITY_SCORE" \
        "last_updated" "$CURRENT_TIME" \
        "idle_connections" "$((CONNECTIONS > 0 ? RANDOM % CONNECTIONS : 0))" \
        "avg_connection_duration" "$((RANDOM % 3600))"
    redis_exec EXPIRE "pod:scaling_data:$POD_IP" 1800  # 30 minutes
    
    # Add to scaling candidates
    redis_exec ZADD "scaling:candidates:scale_down" "$PRIORITY_SCORE" "$POD_IP"
    
    # Add some rejection data (randomly)
    if [ $((RANDOM % 2)) -eq 1 ]; then
        BUCKET_5M=$((CURRENT_TIME / 300 * 300))
        REJECTIONS=$((RANDOM % 5 + 1))
        redis_exec ZINCRBY "rate_limit_rejections:5m:$POD_IP" "$REJECTIONS" "$BUCKET_5M"
        redis_exec EXPIRE "rate_limit_rejections:5m:$POD_IP" 1800  # 30 minutes
    fi
    
    if [ $((RANDOM % 3)) -eq 1 ]; then
        BUCKET_5M=$((CURRENT_TIME / 300 * 300))
        REJECTIONS=$((RANDOM % 3 + 1))
        redis_exec ZINCRBY "max_limit_rejections:5m:$POD_IP" "$REJECTIONS" "$BUCKET_5M"
        redis_exec EXPIRE "max_limit_rejections:5m:$POD_IP" 1800  # 30 minutes
    fi
    
    echo "  Pod $POD_IP: $CONNECTIONS connections, priority $PRIORITY_SCORE"
done

# Set expiration for scaling candidates
redis_exec EXPIRE "scaling:candidates:scale_down" 300

echo ""
echo "✅ Sample data populated successfully!"
echo ""
echo "Data summary:"
redis_exec KEYS "*" | wc -l | xargs echo "  Total Redis keys:"
echo "  Connection tracking keys: $(redis_exec KEYS "pod:established_count:*" | wc -l)"
echo "  Scaling data keys: $(redis_exec KEYS "pod:scaling_data:*" | wc -l)"
echo "  Active connection sets: $(redis_exec KEYS "active_connections:*" | wc -l)"

echo ""
echo "🎯 Now run: ./query-scaling-metrics.sh"
