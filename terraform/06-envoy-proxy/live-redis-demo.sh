#!/bin/bash

# Live Redis Update Cycle Demonstration
# This script shows how Envoy Lua would update Redis in real-time

set -e

echo "=== Live Redis Update Cycle Demo ==="
echo "This demonstrates how the Envoy Lua filter updates Redis every few seconds"
echo ""

# Function to execute Redis commands
redis_exec() {
    kubectl exec -i deployment/redis-connection-tracker -- redis-cli "$@"
}

# Function to simulate a single update cycle (like Envoy would do every 5-10 seconds)
update_cycle() {
    local cycle_num=$1
    local current_time=$(date +%s)
    
    echo "=== Update Cycle #$cycle_num ($(date)) ==="
    
    # Update readiness every cycle (Envoy would do this on every request)
    redis_exec SET "redis:status:connected" "true"
    redis_exec EXPIRE "redis:status:connected" 30  # 30 seconds
    
    redis_exec SET "redis:status:ready_for_scaling" "true"  
    redis_exec EXPIRE "redis:status:ready_for_scaling" 60  # 1 minute
    
    # Simulate connection activity for 3 pods
    local pods=("172.245.10.137" "172.245.10.244" "172.245.20.177")
    
    for pod_ip in "${pods[@]}"; do
        # Simulate random connection changes
        local connections=$((RANDOM % 4))
        local priority=$((10 - connections))
        
        # Update connection count (this happens on every connection/disconnection)
        redis_exec SET "pod:established_count:$pod_ip" "$connections"
        redis_exec EXPIRE "pod:established_count:$pod_ip" 120  # 2 minutes
        
        # Update scaling metrics
        redis_exec HMSET "pod:scaling_data:$pod_ip" \
            "active_connections" "$connections" \
            "scaling_priority" "$priority" \
            "last_updated" "$current_time"
        redis_exec EXPIRE "pod:scaling_data:$pod_ip" 120  # 2 minutes
        
        # Update scaling candidates
        redis_exec ZADD "scaling:candidates:scale_down" "$priority" "$pod_ip"
        
        # Simulate occasional rejections
        if [ $((RANDOM % 3)) -eq 0 ]; then
            local bucket_5m=$((current_time / 300 * 300))
            redis_exec ZINCRBY "rate_limit_rejections:5m:$pod_ip" "1" "$bucket_5m"
            redis_exec EXPIRE "rate_limit_rejections:5m:$pod_ip" 300  # 5 minutes
        fi
        
        echo "  Pod $pod_ip: $connections connections, priority $priority"
    done
    
    # Set expiration for scaling candidates
    redis_exec EXPIRE "scaling:candidates:scale_down" 60  # 1 minute
    
    echo "  ✓ Update cycle completed"
    echo ""
}

# Function to show current state
show_state() {
    echo "📊 Current Redis State:"
    
    # Check readiness
    local ready=$(redis_exec GET "redis:status:ready_for_scaling" 2>/dev/null || echo "false")
    echo "  Ready for scaling: $ready"
    
    # Show connection counts
    echo "  Connection counts:"
    local pods=("172.245.10.137" "172.245.10.244" "172.245.20.177")
    for pod_ip in "${pods[@]}"; do
        local count=$(redis_exec GET "pod:established_count:$pod_ip" 2>/dev/null || echo "0")
        echo "    Pod $pod_ip: $count connections"
    done
    
    # Show total keys
    local total_keys=$(redis_exec KEYS "*" | wc -l)
    echo "  Total Redis keys: $total_keys"
    echo ""
}

# Clear old data first
echo "🧹 Clearing old Redis data..."
redis_exec FLUSHDB >/dev/null

echo "🚀 Starting live update simulation..."
echo "   (In production, Envoy Lua filter would do this automatically)"
echo ""

# Run 10 update cycles with 10-second intervals
for i in {1..10}; do
    update_cycle $i
    
    # Show state every few cycles
    if [ $((i % 2)) -eq 0 ]; then
        show_state
    fi
    
    # Wait between cycles (simulating real-time updates)
    if [ $i -lt 10 ]; then
        echo "⏳ Waiting 10 seconds for next update cycle..."
        sleep 10
    fi
done

echo "✅ Live update simulation completed!"
echo ""
echo "🎯 Final state check:"
show_state

echo "📋 Key points demonstrated:"
echo "  • Redis gets updated every 10 seconds (like Envoy would do)"
echo "  • Connection counts change as traffic flows"
echo "  • Scaling priorities update automatically"
echo "  • Readiness flags are refreshed continuously"
echo "  • TTLs prevent stale data accumulation"
echo ""
echo "Run './query-scaling-metrics.sh' to see the final metrics"
