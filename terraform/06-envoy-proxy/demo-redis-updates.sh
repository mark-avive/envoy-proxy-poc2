#!/bin/bash

# Demo: Real-time Redis Connection Tracking Updates
# This demonstrates the Redis update cycle in action

set -e

echo "=== Redis Connection Tracking - Update Cycle Demo ==="
echo ""
echo "This demonstrates how the Redis data gets updated over time"
echo "as connections come and go, showing the real update cycles."
echo ""

# Function to execute Redis commands
redis_exec() {
    kubectl exec -i deployment/redis-connection-tracker -- redis-cli "$@"
}

# Function to show current metrics in compact format
show_metrics() {
    echo "📊 Current Metrics ($(date +%H:%M:%S)):"
    
    # Show connection counts for active pods
    echo "   Connections:"
    kubectl exec -i deployment/redis-connection-tracker -- redis-cli KEYS "pod:established_count:*" | while read key; do
        if [ ! -z "$key" ]; then
            COUNT=$(kubectl exec -i deployment/redis-connection-tracker -- redis-cli GET "$key" 2>/dev/null || echo "0")
            POD_IP=$(echo "$key" | cut -d: -f3)
            echo "     $POD_IP: $COUNT"
        fi
    done
    
    # Show readiness
    READY=$(redis_exec GET "redis:status:ready_for_scaling" 2>/dev/null || echo "false")
    echo "   Ready for Scaling: $READY"
    
    echo ""
}

# Function to simulate connection activity
simulate_activity() {
    local action=$1
    local pod_ip=$2
    local current_time=$(date +%s)
    
    case $action in
        "connect")
            # Simulate new connection
            local connection_id="demo-$current_time-$RANDOM"
            redis_exec SADD "active_connections:$pod_ip" "$connection_id" >/dev/null
            redis_exec EXPIRE "active_connections:$pod_ip" 1800 >/dev/null
            
            # Update connection count
            local count=$(redis_exec SCARD "active_connections:$pod_ip")
            redis_exec SET "pod:established_count:$pod_ip" "$count" >/dev/null
            redis_exec EXPIRE "pod:established_count:$pod_ip" 1800 >/dev/null
            
            # Update scaling metrics
            local priority=$((10 - count))
            redis_exec HMSET "pod:scaling_data:$pod_ip" \
                "active_connections" "$count" \
                "last_updated" "$current_time" \
                "scaling_priority" "$priority" >/dev/null
            redis_exec EXPIRE "pod:scaling_data:$pod_ip" 1800 >/dev/null
            
            echo "   ➕ New connection to $pod_ip (now: $count connections)"
            ;;
        "disconnect")
            # Simulate connection ending
            local connection_id=$(redis_exec SPOP "active_connections:$pod_ip" 2>/dev/null)
            if [ ! -z "$connection_id" ] && [ "$connection_id" != "(nil)" ]; then
                # Update connection count
                local count=$(redis_exec SCARD "active_connections:$pod_ip")
                redis_exec SET "pod:established_count:$pod_ip" "$count" >/dev/null
                
                # Update scaling metrics
                local priority=$((10 - count))
                redis_exec HMSET "pod:scaling_data:$pod_ip" \
                    "active_connections" "$count" \
                    "last_updated" "$current_time" \
                    "scaling_priority" "$priority" >/dev/null
                
                echo "   ➖ Connection ended from $pod_ip (now: $count connections)"
            fi
            ;;
        "rejection")
            # Simulate rejection
            local bucket_5m=$((current_time / 300 * 300))
            redis_exec ZINCRBY "rate_limit_rejections:5m:$pod_ip" 1 "$bucket_5m" >/dev/null
            redis_exec EXPIRE "rate_limit_rejections:5m:$pod_ip" 1800 >/dev/null
            echo "   🚫 Rate limit rejection for $pod_ip"
            ;;
    esac
}

# Start demo
echo "🚀 Starting real-time update demonstration..."
echo "   (Press Ctrl+C to stop)"
echo ""

# Initial state
show_metrics

# Get some active pod IPs
PODS=($(kubectl exec -i deployment/redis-connection-tracker -- redis-cli KEYS "pod:established_count:*" | head -3 | cut -d: -f3))

if [ ${#PODS[@]} -eq 0 ]; then
    echo "No pods found. Running populate-sample-data.sh first..."
    ./populate-sample-data.sh >/dev/null
    PODS=($(kubectl exec -i deployment/redis-connection-tracker -- redis-cli KEYS "pod:established_count:*" | head -3 | cut -d: -f3))
fi

echo "📈 Monitoring pods: ${PODS[*]}"
echo ""

# Update cycle loop
cycle=1
while true; do
    echo "=== Update Cycle #$cycle (Every 15 seconds) ==="
    
    # Simulate random activity
    for pod in "${PODS[@]}"; do
        local rand=$((RANDOM % 10))
        if [ $rand -lt 3 ]; then
            simulate_activity "connect" "$pod"
        elif [ $rand -lt 5 ]; then
            simulate_activity "disconnect" "$pod"
        elif [ $rand -lt 6 ]; then
            simulate_activity "rejection" "$pod"
        fi
    done
    
    # Update readiness status
    redis_exec SET "redis:status:connected" "true" >/dev/null
    redis_exec EXPIRE "redis:status:connected" 300 >/dev/null
    redis_exec SET "redis:status:ready_for_scaling" "true" >/dev/null
    redis_exec EXPIRE "redis:status:ready_for_scaling" 300 >/dev/null
    
    show_metrics
    
    cycle=$((cycle + 1))
    sleep 15
done
