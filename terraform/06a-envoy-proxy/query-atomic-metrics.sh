#!/bin/bash

# Query scaling metrics for 06a-envoy-proxy atomic implementation
# Provides comprehensive monitoring of connection limits and rate limiting

set -e

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Configuration
NAMESPACE=${NAMESPACE:-default}
REDIS_SERVICE=${REDIS_SERVICE:-redis-atomic-service}

echo "=================================================================="
echo "        ATOMIC CONNECTION TRACKING METRICS DASHBOARD"
echo "=================================================================="
echo "Namespace: $NAMESPACE"
echo "Redis Service: $REDIS_SERVICE"
echo "Timestamp: $(date)"
echo "=================================================================="

# Function to execute Redis command
redis_exec() {
    kubectl exec -n "$NAMESPACE" deployment/redis-atomic -c redis -- redis-cli "$@"
}

# Function to get metrics with error handling
get_metric() {
    local result
    result=$(redis_exec "$@" 2>/dev/null) || echo "0"
    echo "${result:-0}"
}

# Active pod connections (per-pod breakdown)
echo ""
echo "📊 PER-BACKEND-POD CONNECTION COUNTS:"
echo "-----------------------------------------------------------"
backend_pod_keys=$(redis_exec KEYS "ws:backend_pod_conn:*" 2>/dev/null || echo "")
if [[ -n "$backend_pod_keys" ]]; then
    for key in $backend_pod_keys; do
        if [[ "$key" =~ ws:backend_pod_conn:(.+) ]]; then
            pod_ip="${BASH_REMATCH[1]}"
            count=$(get_metric GET "$key")
            echo "  Backend Pod $pod_ip: $count connections"
        fi
    done
else
    echo "  No backend pod connection data found"
fi

# Also show old Envoy pod data for comparison (if any)
echo ""
echo "📊 ENVOY-POD CONNECTION COUNTS (for comparison):"
echo "-----------------------------------------------------------"
pod_keys=$(redis_exec KEYS "ws:pod_conn:*" 2>/dev/null || echo "")
if [[ -n "$pod_keys" ]]; then
    for key in $pod_keys; do
        if [[ "$key" =~ ws:pod_conn:(.+) ]]; then
            pod_id="${BASH_REMATCH[1]}"
            count=$(get_metric GET "$key")
            echo "  Pod $pod_id: $count connections"
        fi
    done
else
    echo "  No active pod connections found"
fi

# Global connection statistics
echo ""
echo "🌐 GLOBAL CONNECTION STATISTICS:"
echo "-----------------------------------------------------------"
total_connections=$(get_metric SCARD "ws:all_connections")
active_pods=$(get_metric SCARD "ws:active_pods")
rejected_connections=$(get_metric GET "ws:rejected")

echo "  Total Active Connections: $total_connections"
echo "  Active Pods: $active_pods"
echo "  Total Rejected Connections: $rejected_connections"

# Proxy-specific metrics
echo ""
echo "🔧 PROXY-SPECIFIC METRICS:"
echo "-----------------------------------------------------------"
proxy_keys=$(redis_exec KEYS "ws:proxy:*:connections" 2>/dev/null || echo "")
if [[ -n "$proxy_keys" ]]; then
    for key in $proxy_keys; do
        if [[ "$key" =~ ws:proxy:(.+):connections ]]; then
            proxy_id="${BASH_REMATCH[1]}"
            count=$(get_metric GET "$key")
            echo "  Proxy $proxy_id: $count connections"
        fi
    done
else
    echo "  No proxy-specific metrics found"
fi

# Rate limiting status
echo ""
echo "⚡ RATE LIMITING STATUS:"
echo "-----------------------------------------------------------"
current_minute=$(date +%s)
current_minute=$((current_minute / 60))
rate_key="ws:rate_limit:$current_minute"
current_rate=$(get_metric GET "$rate_key")
echo "  Current minute requests: $current_rate"

# Check last few minutes for rate limiting trends
echo "  Recent rate limiting (last 5 minutes):"
for i in {0..4}; do
    minute=$((current_minute - i))
    rate=$(get_metric GET "ws:rate_limit:$minute")
    if [[ "$rate" != "0" ]]; then
        echo "    Minute $minute: $rate requests"
    fi
done

# Connection details (sample)
echo ""
echo "🔗 ACTIVE CONNECTION DETAILS (sample):"
echo "-----------------------------------------------------------"
sample_connections=$(redis_exec SRANDMEMBER "ws:all_connections" 5 2>/dev/null || echo "")
if [[ -n "$sample_connections" ]]; then
    for conn_id in $sample_connections; do
        if [[ -n "$conn_id" ]]; then
            echo "  Connection: $conn_id"
            # Get connection metadata
            metadata=$(redis_exec HGETALL "ws:conn:$conn_id" 2>/dev/null || echo "")
            if [[ -n "$metadata" ]]; then
                echo "    Metadata: $metadata" | tr '\n' ' '
                echo ""
            fi
        fi
    done
else
    echo "  No active connections to sample"
fi

# Pod and service status
echo ""
echo "☸️ KUBERNETES STATUS:"
echo "-----------------------------------------------------------"
echo "Redis Pods:"
kubectl get pods -n "$NAMESPACE" -l app=redis-atomic --no-headers 2>/dev/null || echo "  No Redis pods found"

echo ""
echo "Envoy Proxy Pods:"
kubectl get pods -n "$NAMESPACE" -l app=envoy-proxy-atomic --no-headers 2>/dev/null || echo "  No Envoy pods found"

echo ""
echo "Services:"
kubectl get svc -n "$NAMESPACE" redis-atomic-service,envoy-proxy-atomic-service --no-headers 2>/dev/null || echo "  Services not found"

# Configuration summary
echo ""
echo "⚙️ CONFIGURATION SUMMARY:"
echo "-----------------------------------------------------------"
echo "  Max connections per pod: 2 (from requirements)"
echo "  Rate limit: 60 requests/minute (1/second)"
echo "  Connection TTL: 2 hours"
echo "  Redis key patterns:"
echo "    - ws:pod_conn:<pod-id> (per-pod counts)"
echo "    - ws:all_connections (global registry)"
echo "    - ws:conn:<conn-id> (connection metadata)"
echo "    - ws:rate_limit:<minute> (rate limiting)"

# Real-time monitoring suggestion
echo ""
echo "📊 REAL-TIME MONITORING:"
echo "-----------------------------------------------------------"
echo "To monitor in real-time, run:"
echo "  watch -n 2 $0"
echo ""
echo "To monitor Redis commands:"
echo "  kubectl exec -it -n $NAMESPACE deployment/redis-atomic -- redis-cli monitor"
echo ""
echo "To view Envoy logs:"
echo "  kubectl logs -f -n $NAMESPACE -l app=envoy-proxy-atomic"

echo ""
echo "=================================================================="
echo "              END OF METRICS DASHBOARD"
echo "=================================================================="
