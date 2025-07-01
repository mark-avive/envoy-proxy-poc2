#!/bin/bash

# Redis Scaling Metrics Query Tool (Comprehensive Version)
# This script queries Redis via HTTP proxy for connection tracking and scaling metrics

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Redis Connection Tracking and Scaling Metrics ==="

# Function to execute Redis commands via HTTP proxy
redis_http_exec() {
    local cmd="$*"
    curl -s -X POST -d "$cmd" http://localhost:8080/redis 2>/dev/null || echo "ERROR"
}

# Function to check if HTTP proxy is available
check_http_proxy() {
    if ! curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo "❌ Redis HTTP proxy not accessible on localhost:8080"
        echo "   Please run: kubectl port-forward svc/redis-http-proxy 8080:8080"
        exit 1
    fi
}

# Function to get backend pod IPs dynamically
get_backend_pod_ips() {
    kubectl get endpoints envoy-poc-app-server-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | tr ' ' '\n' | sort
}

# Function to get backend pod names dynamically  
get_backend_pod_names() {
    kubectl get endpoints envoy-poc-app-server-service -o jsonpath='{.subsets[*].addresses[*].targetRef.name}' 2>/dev/null | tr ' ' '\n' | sort
}

# Function to check Redis readiness
check_redis_readiness() {
    echo "🔍 Checking Redis readiness status..."
    
    local connected=$(redis_http_exec GET "redis:status:connected")
    local ready_for_scaling=$(redis_http_exec GET "redis:status:ready_for_scaling")
    
    echo "   Redis Connected: $connected"
    echo "   Ready for Scaling: $ready_for_scaling"
    
    # Check if we have actual connection data even if status keys expired
    local has_connection_data=$(redis_http_exec SCARD "active_connections:backend.default.svc.cluster.local")
    
    if [[ "$ready_for_scaling" == "true" ]]; then
        echo "✅ Redis data is ready for scaling decisions"
        return 0
    elif [[ "$has_connection_data" != "ERROR" && "$has_connection_data" != "None" && -n "$has_connection_data" && "$has_connection_data" -gt 0 ]]; then
        echo "✅ Redis data is available (status keys expired but connection data exists)"
        return 0
    else
        echo "⚠️  Redis data is not yet ready for scaling (still collecting)"
        return 1
    fi
}

# Function to get total established connections across all targets
get_total_connections() {
    echo ""
    echo "📊 Total Connection Summary:"
    echo "============================"
    
    local total_connections=0
    local service_connections=0
    local individual_pod_connections=0
    
    # Check service-level tracking (current implementation)
    service_connections=$(redis_http_exec SCARD "active_connections:backend.default.svc.cluster.local")
    if [[ "$service_connections" != "ERROR" && "$service_connections" != "None" && -n "$service_connections" ]]; then
        total_connections=$service_connections
        echo "   Total WebSocket Connections: $total_connections"
        echo "   (Tracked via service: backend.default.svc.cluster.local)"
    fi
    
    # Check for individual pod tracking
    local pod_ips=($(get_backend_pod_ips))
    local pod_total=0
    
    if [[ ${#pod_ips[@]} -gt 0 ]]; then
        echo ""
        echo "   Individual Pod Analysis:"
        for pod_ip in "${pod_ips[@]}"; do
            if [[ -n "$pod_ip" ]]; then
                local pod_connections=$(redis_http_exec SCARD "active_connections:$pod_ip")
                if [[ "$pod_connections" != "ERROR" && "$pod_connections" != "None" && -n "$pod_connections" && "$pod_connections" -gt 0 ]]; then
                    echo "     $pod_ip: $pod_connections connections"
                    pod_total=$((pod_total + pod_connections))
                else
                    echo "     $pod_ip: 0 connections (not individually tracked)"
                fi
            fi
        done
        
        if [[ $pod_total -gt 0 ]]; then
            individual_pod_connections=$pod_total
            echo "   Individual Pod Total: $individual_pod_connections"
        fi
    fi
    
    # Use the higher of the two totals
    if [[ $individual_pod_connections -gt $total_connections ]]; then
        total_connections=$individual_pod_connections
    fi
    
    echo ""
    echo "   🎯 TOTAL ACTIVE WEBSOCKET CONNECTIONS: $total_connections"
}

# Function to get connection rejection statistics
get_rejection_statistics() {
    echo ""
    echo "🚫 Connection Rejection Statistics (Last 5 minutes):"
    echo "===================================================="
    
    local total_rate_rejections=0
    local total_max_rejections=0
    local found_rejections=false
    
    # Check service-level rejections
    echo ""
    echo "Rate Limit Rejections:"
    
    # Check for rate limit rejections on the service
    local rate_attempts=$(redis_http_exec GET "connection_attempts_rate_limited:5m:backend.default.svc.cluster.local")
    if [[ "$rate_attempts" != "ERROR" && "$rate_attempts" != "None" && -n "$rate_attempts" && "$rate_attempts" -gt 0 ]]; then
        echo "   backend.default.svc.cluster.local: $rate_attempts rejections"
        total_rate_rejections=$rate_attempts
        found_rejections=true
    fi
    
    # Check individual pod IPs for rate limit rejections
    local pod_ips=($(get_backend_pod_ips))
    for pod_ip in "${pod_ips[@]}"; do
        if [[ -n "$pod_ip" ]]; then
            local pod_rate_rejections=$(redis_http_exec GET "connection_attempts_rate_limited:5m:$pod_ip")
            if [[ "$pod_rate_rejections" != "ERROR" && "$pod_rate_rejections" != "None" && -n "$pod_rate_rejections" && "$pod_rate_rejections" -gt 0 ]]; then
                echo "   $pod_ip: $pod_rate_rejections rate limit rejections"
                total_rate_rejections=$((total_rate_rejections + pod_rate_rejections))
                found_rejections=true
            fi
        fi
    done
    
    if [[ $total_rate_rejections -eq 0 ]]; then
        echo "   No rate limit rejections found"
    else
        echo "   TOTAL RATE LIMIT REJECTIONS: $total_rate_rejections"
    fi
    
    echo ""
    echo "Max Connection Limit Rejections:"
    
    # Check for max connection rejections on the service
    local max_attempts=$(redis_http_exec GET "connection_attempts_max_limited:5m:backend.default.svc.cluster.local")
    if [[ "$max_attempts" != "ERROR" && "$max_attempts" != "None" && -n "$max_attempts" && "$max_attempts" -gt 0 ]]; then
        echo "   backend.default.svc.cluster.local: $max_attempts rejections"
        total_max_rejections=$max_attempts
        found_rejections=true
    fi
    
    # Check individual pod IPs for max connection rejections
    for pod_ip in "${pod_ips[@]}"; do
        if [[ -n "$pod_ip" ]]; then
            local pod_max_rejections=$(redis_http_exec GET "connection_attempts_max_limited:5m:$pod_ip")
            if [[ "$pod_max_rejections" != "ERROR" && "$pod_max_rejections" != "None" && -n "$pod_max_rejections" && "$pod_max_rejections" -gt 0 ]]; then
                echo "   $pod_ip: $pod_max_rejections max connection rejections"
                total_max_rejections=$((total_max_rejections + pod_max_rejections))
                found_rejections=true
            fi
        fi
    done
    
    if [[ $total_max_rejections -eq 0 ]]; then
        echo "   No max connection limit rejections found"
    else
        echo "   TOTAL MAX CONNECTION REJECTIONS: $total_max_rejections"
    fi
    
    echo ""
    echo "   🎯 TOTAL REJECTIONS: $((total_rate_rejections + total_max_rejections))"
    
    if [[ $found_rejections == false ]]; then
        echo "   ✅ No rejections detected - system operating within limits"
    fi
}

# Function to get current WebSocket connections per pod
get_websocket_connections_per_pod() {
    echo ""
    echo "� Current WebSocket Connections Per Pod:"
    echo "=========================================="
    
    local pod_ips=($(get_backend_pod_ips))
    local pod_names=($(get_backend_pod_names))
    
    if [[ ${#pod_ips[@]} -eq 0 ]]; then
        echo "   No backend pods found"
        return
    fi
    
    local total_individual=0
    local pods_with_data=0
    
    echo ""
    printf "   %-15s %-35s %s\n" "Pod IP" "Pod Name" "Connections"
    printf "   %-15s %-35s %s\n" "-------" "--------" "-----------"
    
    for i in "${!pod_ips[@]}"; do
        local pod_ip="${pod_ips[$i]}"
        local pod_name="${pod_names[$i]:-unknown}"
        
        if [[ -n "$pod_ip" ]]; then
            # Check for individual pod tracking
            local pod_connections=$(redis_http_exec SCARD "active_connections:$pod_ip")
            
            if [[ "$pod_connections" != "ERROR" && "$pod_connections" != "None" && -n "$pod_connections" ]]; then
                printf "   %-15s %-35s %s\n" "$pod_ip" "$pod_name" "$pod_connections"
                total_individual=$((total_individual + pod_connections))
                if [[ $pod_connections -gt 0 ]]; then
                    pods_with_data=$((pods_with_data + 1))
                fi
            else
                printf "   %-15s %-35s %s\n" "$pod_ip" "$pod_name" "0 (not tracked)"
            fi
        fi
    done
    
    echo ""
    if [[ $pods_with_data -gt 0 ]]; then
        echo "   ✅ Individual pod tracking enabled: $total_individual total connections across $pods_with_data pods"
    else
        # Fall back to service-level tracking
        local service_connections=$(redis_http_exec SCARD "active_connections:backend.default.svc.cluster.local")
        if [[ "$service_connections" != "ERROR" && "$service_connections" != "None" && -n "$service_connections" ]]; then
            echo "   📊 Service-level tracking: $service_connections connections to backend.default.svc.cluster.local"
            echo "   ⚠️  Individual pod tracking not yet implemented"
        else
            echo "   ❌ No connection tracking data found"
        fi
    fi
}

# Function to get scaling recommendations
get_scaling_recommendations() {
    echo ""
    echo "🎯 Scaling Recommendations:"
    echo "==========================="
    
    local pod_ips=($(get_backend_pod_ips))
    local found_scaling_data=false
    
    echo ""
    echo "Scale-Down Priority (highest priority first):"
    
    # Check service-level scaling data
    local service_priority=$(redis_http_exec GET "pod:scaling_data:backend.default.svc.cluster.local")
    if [[ "$service_priority" != "ERROR" && "$service_priority" != "None" && -n "$service_priority" ]]; then
        echo "   backend.default.svc.cluster.local (service-level tracking)"
        found_scaling_data=true
    fi
    
    # Check individual pod scaling data
    for pod_ip in "${pod_ips[@]}"; do
        if [[ -n "$pod_ip" ]]; then
            local pod_priority=$(redis_http_exec GET "pod:scaling_data:$pod_ip")
            if [[ "$pod_priority" != "ERROR" && "$pod_priority" != "None" && -n "$pod_priority" ]]; then
                local connections=$(redis_http_exec SCARD "active_connections:$pod_ip")
                local priority=$((10 - connections))
                echo "   $pod_ip (priority: $priority, connections: $connections)"
                found_scaling_data=true
            fi
        fi
    done
    
    if [[ $found_scaling_data == false ]]; then
        echo "   No scaling priority data available yet"
        echo "   System is still collecting baseline metrics"
    fi
}

# Function to get detailed pod metrics
get_detailed_metrics() {
    echo ""
    echo "📈 Detailed Connection Metrics:"
    echo "==============================="
    
    # Service-level metrics
    echo ""
    echo "Service-Level Tracking (backend.default.svc.cluster.local):"
    echo "-----------------------------------------------------------"
    
    local active_connections=$(redis_http_exec SCARD "active_connections:backend.default.svc.cluster.local")
    local established_count=$(redis_http_exec GET "pod:established_count:backend.default.svc.cluster.local")
    
    if [[ "$active_connections" != "ERROR" && "$active_connections" != "None" ]]; then
        echo "   active_connections  : $active_connections"
    fi
    
    if [[ "$established_count" != "ERROR" && "$established_count" != "None" ]]; then
        echo "   established_count   : $established_count"
    fi
    
    # Calculate priority for service
    if [[ "$active_connections" != "ERROR" && "$active_connections" != "None" && -n "$active_connections" ]]; then
        local priority=$((10 - active_connections))
        echo "   scaling_priority    : $priority"
    fi
    
    # Individual pod metrics
    local pod_ips=($(get_backend_pod_ips))
    local individual_tracking=false
    
    for pod_ip in "${pod_ips[@]}"; do
        if [[ -n "$pod_ip" ]]; then
            local pod_connections=$(redis_http_exec SCARD "active_connections:$pod_ip")
            if [[ "$pod_connections" != "ERROR" && "$pod_connections" != "None" && -n "$pod_connections" && "$pod_connections" -gt 0 ]]; then
                if [[ $individual_tracking == false ]]; then
                    echo ""
                    echo "Individual Pod Tracking:"
                    echo "-----------------------"
                    individual_tracking=true
                fi
                echo "   Pod $pod_ip:"
                echo "     active_connections: $pod_connections"
                local pod_priority=$((10 - pod_connections))
                echo "     scaling_priority  : $pod_priority"
            fi
        fi
    done
    
    if [[ $individual_tracking == false ]]; then
        echo ""
        echo "Individual Pod Tracking: Not yet implemented"
        echo "   All connections currently tracked at service level"
    fi
}

# Function to get connection attempt statistics
get_connection_attempts() {
    echo ""
    echo "📈 Connection Attempt Statistics (Last 5 minutes):"
    echo "=================================================="
    
    # Service-level attempts
    echo ""
    echo "Service-Level Attempts:"
    local service_attempts=$(redis_http_exec GET "connection_attempts:5m:backend.default.svc.cluster.local")
    if [[ "$service_attempts" != "ERROR" && "$service_attempts" != "None" && -n "$service_attempts" ]]; then
        echo "   backend.default.svc.cluster.local: $service_attempts attempts"
    else
        echo "   No service-level attempt data found"
    fi
    
    # Individual pod attempts
    local pod_ips=($(get_backend_pod_ips))
    local found_individual=false
    
    for pod_ip in "${pod_ips[@]}"; do
        if [[ -n "$pod_ip" ]]; then
            local pod_attempts=$(redis_http_exec GET "connection_attempts:5m:$pod_ip")
            if [[ "$pod_attempts" != "ERROR" && "$pod_attempts" != "None" && -n "$pod_attempts" && "$pod_attempts" -gt 0 ]]; then
                if [[ $found_individual == false ]]; then
                    echo ""
                    echo "Individual Pod Attempts:"
                    found_individual=true
                fi
                echo "   $pod_ip: $pod_attempts attempts"
            fi
        fi
    done
    
    if [[ $found_individual == false ]]; then
        echo ""
        echo "Individual Pod Attempts: No data found"
    fi
}

# Function to get Redis statistics
get_redis_stats() {
    echo ""
    echo "💾 Redis Statistics:"
    echo "==================="
    
    # Try to get some basic info
    local redis_status=$(redis_http_exec GET "redis:status:connected")
    echo "   Redis Status: $redis_status"
    
    # Count some key types we know exist
    local backend_connections=$(redis_http_exec SCARD "active_connections:backend.default.svc.cluster.local")
    echo "   Active Connections Tracked: $backend_connections"
    
    local readiness=$(redis_http_exec GET "redis:status:ready_for_scaling")
    echo "   Ready for Scaling: $readiness"
}

# Main execution
main() {
    # Check if HTTP proxy is accessible
    check_http_proxy
    
    # Check if Redis is ready
    if ! check_redis_readiness; then
        echo ""
        echo "⏳ Redis is still initializing. Try again in a few moments."
        exit 0
    fi
    
    # Get comprehensive metrics
    get_total_connections
    get_rejection_statistics  
    get_websocket_connections_per_pod
    get_connection_attempts
    get_scaling_recommendations
    get_detailed_metrics
    get_redis_stats
    
    echo ""
    echo "=== Summary ==="
    echo "📊 Use this data to make scaling decisions:"
    echo "   • Total WebSocket connections across all pods"
    echo "   • Connection rejection counts (rate limits & max connections)"
    echo "   • Per-pod connection distribution"
    echo "   • Scaling priority recommendations"
    echo ""
    echo "🔄 Run this script periodically or integrate with your scaling controller"
    echo ""
    echo "💡 Manual Redis queries:"
    echo "   Total connections: curl -X POST -d 'SCARD \"active_connections:backend.default.svc.cluster.local\"' http://localhost:8080/redis"
    echo "   Connection status: curl -X POST -d 'GET \"redis:status:connected\"' http://localhost:8080/redis"
    echo ""
    echo "⚙️  Current Architecture Notes:"
    echo "   • Connections tracked at service level (not individual pods)"
    echo "   • For true per-pod scaling, Lua script needs pod IP tracking"
    echo "   • Service-level tracking provides total connection count"
}

# Error handling
trap 'echo "❌ Script interrupted"; exit 130' INT
trap 'echo "❌ Script failed on line $LINENO"; exit 1' ERR

# Run main function
main "$@"
