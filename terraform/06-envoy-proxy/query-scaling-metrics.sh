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
    
    local connected=$(redis_exec GET "redis:status:connected" 2>/dev/null || echo "false")
    local ready_for_scaling=$(redis_exec GET "redis:status:ready_for_scaling" 2>/dev/null || echo "false")
    
    echo "   Redis Connected: $connected"
    echo "   Ready for Scaling: $ready_for_scaling"
    
    if [[ "$ready_for_scaling" == "true" ]]; then
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
    
    # Get all pod connection keys
    local pod_keys=$(redis_exec KEYS "pod:established_count:*" 2>/dev/null || echo "")
    
    if [[ -z "$pod_keys" ]]; then
        echo "   No pod connection data found"
        return
    fi
    
    echo "$pod_keys" | while read -r key; do
        if [[ -n "$key" ]]; then
            local pod_ip=$(echo "$key" | sed 's/pod:established_count://')
            local count=$(redis_exec GET "$key" 2>/dev/null || echo "0")
            printf "   %-20s: %2d connections\n" "$pod_ip" "$count"
        fi
    done
}

# Function to get rejection statistics
get_rejection_stats() {
    echo ""
    echo "🚫 Connection Rejection Statistics (Last 5 minutes):"
    echo "===================================================="
    
    # Rate limit rejections
    echo ""
    echo "Rate Limit Rejections:"
    local rate_limit_keys=$(redis_exec KEYS "rate_limit_rejections:5m:*" 2>/dev/null || echo "")
    if [[ -n "$rate_limit_keys" ]]; then
        echo "$rate_limit_keys" | while read -r key; do
            if [[ -n "$key" ]]; then
                local pod_ip=$(echo "$key" | sed 's/rate_limit_rejections:5m://')
                local count=$(redis_exec ZCARD "$key" 2>/dev/null || echo "0")
                printf "   %-20s: %2d rejections\n" "$pod_ip" "$count"
            fi
        done
    else
        echo "   No rate limit rejections found"
    fi
    
    # Max limit rejections
    echo ""
    echo "Max Connection Limit Rejections:"
    local max_limit_keys=$(redis_exec KEYS "max_limit_rejections:5m:*" 2>/dev/null || echo "")
    if [[ -n "$max_limit_keys" ]]; then
        echo "$max_limit_keys" | while read -r key; do
            if [[ -n "$key" ]]; then
                local pod_ip=$(echo "$key" | sed 's/max_limit_rejections:5m://')
                local count=$(redis_exec ZCARD "$key" 2>/dev/null || echo "0")
                printf "   %-20s: %2d rejections\n" "$pod_ip" "$count"
            fi
        done
    else
        echo "   No max limit rejections found"
    fi
}

# Function to get scaling recommendations
get_scaling_recommendations() {
    echo ""
    echo "🎯 Scaling Recommendations:"
    echo "==========================="
    
    local candidates=$(redis_exec ZREVRANGE "scaling:candidates:scale_down" 0 -1 WITHSCORES 2>/dev/null || echo "")
    
    if [[ -n "$candidates" ]]; then
        echo ""
        echo "Scale-Down Priority (highest priority first):"
        echo "$candidates" | while read -r pod_ip score; do
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
    
    local scaling_keys=$(redis_exec KEYS "pod:scaling_data:*" 2>/dev/null || echo "")
    
    if [[ -z "$scaling_keys" ]]; then
        echo "   No detailed pod metrics found"
        return
    fi
    
    echo "$scaling_keys" | while read -r key; do
        if [[ -n "$key" ]]; then
            local pod_ip=$(echo "$key" | sed 's/pod:scaling_data://')
            echo ""
            echo "Pod: $pod_ip"
            echo "-------------------"
            
            # Get all fields for this pod
            local metrics=$(redis_exec HGETALL "$key" 2>/dev/null || echo "")
            if [[ -n "$metrics" ]]; then
                echo "$metrics" | while read -r field value; do
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
    *)
        main
        ;;
esac
