#!/bin/bash

# Redis Scaling Metrics Query Tool
# This script queries Redis for connection tracking and scaling metrics

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Redis Connection Tracking and Scaling Metrics ==="

# Function to execute Redis commands
redis_exec() {
    kubectl exec -i deployment/redis-connection-tracker -- redis-cli "$@"
}

# Function to check Redis readiness
check_redis_readiness() {
    echo "🔍 Checking Redis readiness status..."
    
    # Check if Redis is responding and has our connection tracking keys
    local redis_ping=$(redis_exec PING 2>/dev/null || echo "FAILED")
    local has_data=$(redis_exec KEYS "ws:*" 2>/dev/null | wc -l)
    
    echo "   Redis Connected: $([[ "$redis_ping" == "PONG" ]] && echo "true" || echo "false")"
    echo "   Ready for Scaling: $([[ $has_data -gt 0 ]] && echo "true" || echo "false")"
    
    if [[ "$redis_ping" == "PONG" ]] && [[ $has_data -gt 0 ]]; then
        echo "✅ Redis data is ready for scaling decisions"
        return 0
    else
        echo "⚠️  Redis data is not yet ready for scaling (still collecting)"
        return 1
    fi
}

# Function to get pod connection counts
get_pod_connections() {
    echo ""
    echo "📊 Current Pod Connection Counts:"
    echo "=================================="
    
    # Get all pod connection keys (our implementation uses ws:pod_conn:*)
    local pod_keys=$(redis_exec KEYS "ws:pod_conn:*" 2>/dev/null)
    
    if [[ -z "$pod_keys" ]]; then
        echo "   No pod connection data found"
        return
    fi
    
    echo "$pod_keys" | while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            local pod_ip=$(echo "$key" | sed 's/ws:pod_conn://')
            local count=$(redis_exec GET "$key" 2>/dev/null || echo "0")
            printf "   %-40s: %2d connections\n" "$pod_ip" "$count"
        fi
    done
}

# Function to get rejection statistics
get_rejection_stats() {
    echo ""
    echo "🚫 Connection Rejection Statistics:"
    echo "==================================="
    
    # Total rejected connections (our implementation)
    local total_rejected=$(redis_exec GET "ws:rejected" 2>/dev/null || echo "0")
    echo "   Total Rejected Connections: $total_rejected"
    
    # Rate limiting windows (current implementation)
    echo ""
    echo "Rate Limiting Windows (Last 5 minutes):"
    local current_minute=$(date +%s)
    current_minute=$((current_minute / 60))
    
    local total_rate_limited=0
    for i in {0..4}; do
        local minute=$((current_minute - i))
        local key="ws:rate_limit:$minute"
        local count=$(redis_exec GET "$key" 2>/dev/null || echo "0")
        if [[ $count -gt 0 ]]; then
            local minute_time=$(date -d "@$((minute * 60))" +"%H:%M")
            printf "   %-10s: %2d requests\n" "$minute_time" "$count"
            total_rate_limited=$((total_rate_limited + count))
        fi
    done
    
    echo ""
    echo "   Total Rate Limited (5 min): $total_rate_limited"
}

# Function to show all Redis data for debugging
show_all_redis_data() {
    echo ""
    echo "🔍 All Redis Data (Debug Information):"
    echo "====================================="
    
    local all_keys=$(redis_exec KEYS "*" 2>/dev/null)
    if [[ -z "$all_keys" ]]; then
        echo "   No Redis keys found"
        return
    fi
    
    echo "$all_keys" | while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            local value=$(redis_exec GET "$key" 2>/dev/null || echo "N/A")
            printf "   %-40s: %s\n" "$key" "$value"
        fi
    done
}

# Function to get scaling recommendations
get_scaling_recommendations() {
    echo ""
    echo "🎯 Scaling Recommendations:"
    echo "==========================="
    
    # Get scale-down candidates with scores
    local candidates=$(redis_exec ZREVRANGE "scaling:candidates:scale_down" 0 -1 WITHSCORES 2>/dev/null)
    
    if [[ -n "$candidates" ]]; then
        echo ""
        echo "Scale-Down Priority (highest priority first):"
        
        # Parse the output properly
        local items=()
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                items+=("$line")
            fi
        done <<< "$candidates"
        
        # Process pairs (pod_ip, score)
        for ((i=0; i<${#items[@]}; i+=2)); do
            local pod_ip="${items[i]}"
            local score="${items[i+1]}"
            if [[ -n "$pod_ip" && -n "$score" ]]; then
                printf "   %-20s (priority: %s)\n" "$pod_ip" "$score"
            fi
        done
    else
        echo "   No scaling candidates found"
    fi
}

# Function to get detailed pod metrics
get_detailed_pod_metrics() {
    echo ""
    echo "📈 Detailed Pod Scaling Metrics:"
    echo "================================="
    
    local scaling_keys=$(redis_exec KEYS "pod:scaling_data:*" 2>/dev/null)
    
    if [[ -z "$scaling_keys" ]]; then
        echo "   No detailed pod metrics found"
        return
    fi
    
    echo "$scaling_keys" | while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            local pod_ip=$(echo "$key" | sed 's/pod:scaling_data://')
            echo ""
            echo "Pod: $pod_ip"
            echo "-------------------"
            
            # Get all fields for this pod
            local metrics=$(redis_exec HGETALL "$key" 2>/dev/null)
            if [[ -n "$metrics" ]]; then
                # Parse field-value pairs
                local items=()
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        items+=("$line")
                    fi
                done <<< "$metrics"
                
                # Process pairs (field, value)
                for ((i=0; i<${#items[@]}; i+=2)); do
                    local field="${items[i]}"
                    local value="${items[i+1]}"
                    if [[ -n "$field" && -n "$value" ]]; then
                        printf "   %-20s: %s\n" "$field" "$value"
                    fi
                done
            fi
        fi
    done
}

# Function to show Redis memory usage
show_redis_stats() {
    echo ""
    echo "💾 Redis Statistics:"
    echo "==================="
    
    local info=$(redis_exec INFO memory 2>/dev/null || echo "")
    if [[ -n "$info" ]]; then
        echo "$info" | grep -E "(used_memory_human|used_memory_peak_human|mem_fragmentation_ratio)" | while read -r line; do
            echo "   $line"
        done
    fi
    
    local keyspace=$(redis_exec INFO keyspace 2>/dev/null || echo "")
    if [[ -n "$keyspace" ]]; then
        echo ""
        echo "Key Statistics:"
        echo "$keyspace" | grep "db0" | while read -r line; do
            echo "   $line"
        done
    fi
}

# Main execution
main() {
    # Check if Redis is accessible
    if ! kubectl get deployment redis-connection-tracker >/dev/null 2>&1; then
        echo "❌ Redis connection tracker deployment not found"
        echo "Please run './deploy-enhanced.sh' first"
        exit 1
    fi
    
    if ! redis_exec ping >/dev/null 2>&1; then
        echo "❌ Cannot connect to Redis"
        echo "Please ensure Redis is running and accessible"
        exit 1
    fi
    
    echo "✅ Connected to Redis successfully"
    
    # Check readiness status
    check_redis_readiness
    
    # Show debug information first
    show_all_redis_data
    
    # Get all metrics
    get_pod_connections
    get_rejection_stats
    get_scaling_recommendations
    get_detailed_pod_metrics
    show_redis_stats
    
    echo ""
    echo "=== Summary ==="
    echo "📊 Use this data to make scaling decisions:"
    echo "   • Pods with high connection counts may need scaling up"
    echo "   • Pods with high rejections indicate capacity issues"
    echo "   • Use scale-down priority list for choosing pods to terminate"
    echo "   • Monitor trends over time for better scaling decisions"
    echo ""
    echo "🔄 Run this script periodically or integrate with your scaling controller"
}

# Command line options
case "${1:-}" in
    "connections")
        get_pod_connections
        ;;
    "rejections")
        get_rejection_stats
        ;;
    "scaling")
        get_scaling_recommendations
        ;;
    "detailed")
        get_detailed_pod_metrics
        ;;
    "stats")
        show_redis_stats
        ;;
    "readiness")
        check_redis_readiness
        ;;
    "debug")
        show_all_redis_data
        ;;
    *)
        main
        ;;
esac
