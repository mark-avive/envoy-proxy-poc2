#!/bin/bash
# Envoy Proxy POC - Complete Configuration and Metrics Monitor
# Location: /home/mark/workareas/github/envoy-proxy-poc2/envoy-monitor.sh
# Purpose: Monitor WebSocket connections, rate limiting, circuit breakers, and pod health
# Prerequisites: kubectl port-forward svc/envoy-proxy-service 9901:9901

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}=====================================================================${NC}"
    echo -e "${BLUE}                   ENVOY PROXY POC MONITORING${NC}"
    echo -e "${BLUE}=====================================================================${NC}"
    echo -e "${CYAN}Timestamp: $(date)${NC}"
    echo ""
}

print_section() {
    echo -e "${PURPLE}$1${NC}"
    echo "---------------------------------------------------------------------"
}

check_envoy_connection() {
    if ! curl -s http://localhost:9901/ready > /dev/null 2>&1; then
        echo -e "${RED}❌ ERROR: Cannot connect to Envoy admin interface at localhost:9901${NC}"
        echo -e "${YELLOW}   Make sure to run: kubectl port-forward svc/envoy-proxy-service 9901:9901${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Envoy admin interface is accessible${NC}"
    echo ""
}

get_config_summary() {
    print_section "📋 CONFIGURATION SUMMARY"
    
    # Circuit Breaker Settings
    echo -e "${CYAN}Circuit Breaker Configuration:${NC}"
    curl -s http://localhost:9901/config_dump | jq -r '.configs[1].static_clusters[0].cluster.circuit_breakers.thresholds[0]' | \
    jq -r '"  Max Connections per Pod: " + (.max_connections | tostring) + 
           "\n  Max Pending Requests: " + (.max_pending_requests | tostring) +
           "\n  Max Requests: " + (.max_requests | tostring) +
           "\n  Max Retries: " + (.max_retries | tostring)'
    
    echo ""
    
    # Rate Limiting Configuration
    echo -e "${CYAN}Rate Limiting Configuration:${NC}"
    curl -s http://localhost:9901/config_dump | jq -r '
    .configs[] | 
    select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ListenersConfigDump") |
    .static_listeners[0].listener.filter_chains[0].filters[0].typed_config.http_filters[] |
    select(.name == "envoy.filters.http.local_ratelimit") |
    .typed_config.token_bucket' | \
    jq -r '"  Max Tokens: " + (.max_tokens | tostring) + 
           "\n  Tokens per Fill: " + (.tokens_per_fill | tostring) +
           "\n  Fill Interval: " + .fill_interval'
    
    echo ""
}

get_live_metrics() {
    print_section "📊 LIVE METRICS"
    
    # Current Connections
    local active_connections=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_active:" | awk '{print $2}')
    local total_connections=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_total:" | awk '{print $2}')
    local max_connections=$(curl -s http://localhost:9901/config_dump | jq -r '.configs[1].static_clusters[0].cluster.circuit_breakers.thresholds[0].max_connections')
    
    echo -e "${CYAN}WebSocket Connections:${NC}"
    echo "  Currently Active: ${active_connections}/${max_connections}"
    echo "  Total Created: ${total_connections}"
    
    # Connection Health
    local connection_failures=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_connect_fail:" | awk '{print $2}')
    local connection_timeouts=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_connect_timeout:" | awk '{print $2}')
    
    echo "  Connection Failures: ${connection_failures}"
    echo "  Connection Timeouts: ${connection_timeouts}"
    
    # Circuit Breaker Status
    local cb_open=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.circuit_breakers.default.cx_open:" | awk '{print $2}' 2>/dev/null)
    local pool_open=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.circuit_breakers.default.cx_pool_open:" | awk '{print $2}' 2>/dev/null)
    
    # Handle empty values
    cb_open=${cb_open:-0}
    pool_open=${pool_open:-0}
    
    echo ""
    echo -e "${CYAN}Circuit Breaker Status:${NC}"
    if [[ "$cb_open" =~ ^[0-9]+$ ]] && [ "$cb_open" -gt 0 ]; then
        echo -e "  ${RED}🔴 Circuit Breaker Open Count: ${cb_open}${NC}"
    else
        echo -e "  ${GREEN}✅ Circuit Breaker: Closed (count: ${cb_open})${NC}"
    fi
    
    if [[ "$pool_open" =~ ^[0-9]+$ ]] && [ "$pool_open" -gt 0 ]; then
        echo -e "  ${YELLOW}🟠 Connection Pool Open Count: ${pool_open}${NC}"
    else
        echo -e "  ${GREEN}✅ Connection Pool: Available (count: ${pool_open})${NC}"
    fi
    
    # Rate Limiting Status
    local rate_limited=$(curl -s http://localhost:9901/stats | grep "websocket_rate_limiter.http_local_rate_limit.rate_limited:" | awk '{print $2}' 2>/dev/null)
    local requests_ok=$(curl -s http://localhost:9901/stats | grep "websocket_rate_limiter.http_local_rate_limit.ok:" | awk '{print $2}' 2>/dev/null)
    local enforced=$(curl -s http://localhost:9901/stats | grep "websocket_rate_limiter.http_local_rate_limit.enforced:" | awk '{print $2}' 2>/dev/null)
    local enabled=$(curl -s http://localhost:9901/stats | grep "websocket_rate_limiter.http_local_rate_limit.enabled:" | awk '{print $2}' 2>/dev/null)
    
    # Handle empty values
    rate_limited=${rate_limited:-0}
    requests_ok=${requests_ok:-0}
    enforced=${enforced:-0}
    enabled=${enabled:-0}
    
    echo ""
    echo -e "${CYAN}Rate Limiting Status:${NC}"
    echo "  Rate Limiter Enabled: ${enabled}"
    echo "  Rate Limiter Enforced: ${enforced}"
    echo "  Requests Rate Limited: ${rate_limited}"
    echo "  Requests Allowed: ${requests_ok}"
    
    # Connection Lifecycle
    local destroyed=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_destroy:" | awk '{print $2}' 2>/dev/null)
    local destroyed_local=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_destroy_local:" | awk '{print $2}' 2>/dev/null)
    local destroyed_remote=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_destroy_remote:" | awk '{print $2}' 2>/dev/null)
    
    # Handle empty values
    destroyed=${destroyed:-0}
    destroyed_local=${destroyed_local:-0}
    destroyed_remote=${destroyed_remote:-0}
    
    echo ""
    echo -e "${CYAN}Connection Lifecycle:${NC}"
    echo "  Total Destroyed: ${destroyed}"
    echo "  Destroyed by Client: ${destroyed_local}"
    echo "  Destroyed by Server: ${destroyed_remote}"
    
    echo ""
}

get_cluster_health() {
    print_section "🏥 CLUSTER HEALTH"
    
    # Health Check Stats
    local health_attempts=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.health_check.attempt:" | awk '{print $2}' 2>/dev/null)
    local health_success=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.health_check.success:" | awk '{print $2}' 2>/dev/null)
    local health_failure=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.health_check.failure:" | awk '{print $2}' 2>/dev/null)
    
    # Handle empty values
    health_attempts=${health_attempts:-0}
    health_success=${health_success:-0}
    health_failure=${health_failure:-0}
    
    echo -e "${CYAN}Health Check Statistics:${NC}"
    echo "  Attempts: ${health_attempts}"
    echo "  Successes: ${health_success}"
    echo "  Failures: ${health_failure}"
    
    echo ""
    echo -e "${CYAN}Endpoint Health Status:${NC}"
    curl -s http://localhost:9901/clusters | grep -A 10 "websocket_cluster" | grep -E "(healthy|unhealthy|no_traffic)" | head -5 | \
    sed 's/^/  /'
    
    echo ""
}

get_kubernetes_status() {
    print_section "☸️  KUBERNETES STATUS"
    
    echo -e "${CYAN}Client Pods:${NC}"
    kubectl get pods -l app=envoy-poc-client-app --no-headers 2>/dev/null | awk '{
        if ($3 == "Running") 
            print "  ✅ " $1 " (" $3 ")"
        else 
            print "  ❌ " $1 " (" $3 ")"
    }' || echo "  ⚠️  Unable to get client pod status"
    
    echo ""
    echo -e "${CYAN}Server Pods:${NC}"
    kubectl get pods -l app=envoy-poc-app-server --no-headers 2>/dev/null | awk '{
        if ($3 == "Running") 
            print "  ✅ " $1 " (" $3 ")"
        else 
            print "  ❌ " $1 " (" $3 ")"
    }' || echo "  ⚠️  Unable to get server pod status"
    
    echo ""
    echo -e "${CYAN}Envoy Pods:${NC}"
    kubectl get pods -l app=envoy-proxy --no-headers 2>/dev/null | awk '{
        if ($3 == "Running") 
            print "  ✅ " $1 " (" $3 ")"
        else 
            print "  ❌ " $1 " (" $3 ")"
    }' || echo "  ⚠️  Unable to get envoy pod status"
    
    echo ""
}

get_detailed_stats() {
    print_section "📈 DETAILED STATISTICS"
    
    echo -e "${CYAN}Request Statistics:${NC}"
    curl -s http://localhost:9901/stats | grep -E "cluster\.websocket_cluster\." | \
    grep -E "(upstream_rq_|retry_)" | \
    awk '{
        if ($1 ~ /upstream_rq_total/) print "  Total Requests: " $2
        else if ($1 ~ /upstream_rq_active/) print "  Active Requests: " $2
        else if ($1 ~ /upstream_rq_pending_total/) print "  Pending Requests: " $2
        else if ($1 ~ /upstream_rq_2xx/) print "  HTTP 2xx Responses: " $2
        else if ($1 ~ /upstream_rq_4xx/) print "  HTTP 4xx Responses: " $2
        else if ($1 ~ /upstream_rq_5xx/) print "  HTTP 5xx Responses: " $2
        else if ($1 ~ /upstream_rq_timeout/) print "  Request Timeouts: " $2
        else if ($1 ~ /upstream_rq_retry/) print "  Request Retries: " $2
    }'
    
    echo ""
    echo -e "${CYAN}WebSocket Upgrade Statistics:${NC}"
    curl -s http://localhost:9901/stats | grep -E "(websocket|upgrade)" | \
    sed 's/^/  /' || echo "  No WebSocket upgrade stats found"
    
    echo ""
}

show_monitoring_commands() {
    print_section "🔧 MONITORING COMMANDS"
    
    echo -e "${CYAN}Real-time Monitoring:${NC}"
    echo "  # Watch active connections:"
    echo "  watch -n 2 'curl -s http://localhost:9901/stats | grep cluster.websocket_cluster.upstream_cx_active:'"
    echo ""
    echo "  # Monitor rate limiting:"
    echo "  watch -n 1 'curl -s http://localhost:9901/stats | grep local_rate_limit'"
    echo ""
    echo "  # Watch circuit breaker status:"
    echo "  watch -n 1 'curl -s http://localhost:9901/stats | grep circuit_breakers'"
    echo ""
    echo "  # Monitor client pod logs:"
    echo "  kubectl logs -l app=envoy-poc-client-app -f"
    echo ""
    echo "  # Monitor server pod logs:"
    echo "  kubectl logs -l app=envoy-poc-app-server -f"
    echo ""
    
    echo -e "${CYAN}Configuration Changes:${NC}"
    echo "  # Edit Envoy configuration:"
    echo "  cd terraform/06-envoy-proxy && vim locals.tf"
    echo ""
    echo "  # Edit Client configuration:"
    echo "  cd terraform/07-client-application && vim locals.tf"
    echo ""
    echo "  # Edit Server configuration:"
    echo "  cd terraform/05-server-application && vim locals.tf"
    echo ""
    echo "  # Apply changes:"
    echo "  cd terraform/<section> && terraform apply"
    echo ""
}

# Main execution
main() {
    print_header
    check_envoy_connection
    get_config_summary
    get_live_metrics
    get_cluster_health
    get_kubernetes_status
    get_detailed_stats
    show_monitoring_commands
    
    echo -e "${BLUE}=====================================================================${NC}"
    echo -e "${GREEN}✅ Monitoring complete. Run with -w flag for continuous monitoring.${NC}"
    echo -e "${BLUE}=====================================================================${NC}"
}

# Handle continuous monitoring flag
if [ "$1" = "-w" ] || [ "$1" = "--watch" ]; then
    while true; do
        clear
        main
        echo ""
        echo -e "${YELLOW}Refreshing in 5 seconds... (Ctrl+C to stop)${NC}"
        sleep 5
    done
else
    main
fi
