#!/bin/bash
# WebSocket Connections Per Pod - Quick View
# Assumes: kubectl port-forward svc/envoy-proxy-service 9901:9901 is running

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}  WEBSOCKET CONNECTIONS PER POD${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# Total from Envoy
echo -e "${CYAN}📊 Total Active Connections (from Envoy):${NC}"
active_total=$(curl -s http://localhost:9901/stats | grep "cluster.websocket_cluster.upstream_cx_active:" | awk '{print $2}')
max_connections=$(curl -s http://localhost:9901/config_dump | jq -r '.configs[1].static_clusters[0].cluster.circuit_breakers.thresholds[0].max_connections')
echo "  ${active_total}/${max_connections} connections"
echo ""

# Envoy endpoint details
echo -e "${CYAN}🎯 Envoy Load Balancer Target:${NC}"
service_name=""
endpoint_ip=""
active_cx=""
active_rq=""

while IFS= read -r line; do
    if [[ $line == *"hostname"* ]]; then
        service_name=$(echo "$line" | sed 's/.*hostname:://')
    elif [[ $line == *"cx_active"* ]]; then
        endpoint_ip=$(echo "$line" | cut -d':' -f3)
        active_cx=$(echo "$line" | sed 's/.*cx_active:://')
    elif [[ $line == *"rq_active"* ]]; then
        active_rq=$(echo "$line" | sed 's/.*rq_active:://')
    fi
done < <(curl -s http://localhost:9901/clusters | grep "websocket_cluster::" | grep -E "(hostname|cx_active|rq_active)")

echo "  Service: ${service_name}"
echo "  Endpoint IP: ${endpoint_ip}"
echo "  Active Connections: ${active_cx}"
echo "  Active Requests: ${active_rq}"
echo ""

# Individual server pods
echo -e "${CYAN}📦 Individual Server Pods:${NC}"
if command -v kubectl >/dev/null 2>&1; then
    pod_count=0
    total_pod_connections=0
    
    kubectl get pods -l app=envoy-poc-app-server -o wide --no-headers 2>/dev/null | while read pod_line; do
        pod_name=$(echo $pod_line | awk '{print $1}')
        pod_ip=$(echo $pod_line | awk '{print $6}')
        pod_status=$(echo $pod_line | awk '{print $3}')
        
        if [ "$pod_status" = "Running" ]; then
            # Get recent WebSocket activity from logs
            recent_activity=$(kubectl logs $pod_name --tail=20 --since=60s 2>/dev/null | grep -c "WebSocket" 2>/dev/null || echo "0")
            echo "  ${pod_name}"
            echo "    ├─ IP: ${pod_ip}"
            echo "    ├─ Status: ${pod_status}"
            echo "    └─ Recent WebSocket activity (last 60s): ${recent_activity} log entries"
        else
            echo "  ${pod_name} (${pod_status})"
        fi
        echo ""
    done
    
    echo -e "${CYAN}💡 Note:${NC}"
    echo "  • Envoy load balances to the Kubernetes service (${service_name})"
    echo "  • The service distributes connections among the ${pod_count} server pods"
    echo "  • Total active connections (${active_total}) are distributed across all pods"
    echo "  • Circuit breaker limit is ${max_connections} total connections"
else
    echo "  ⚠️  kubectl not available"
fi

echo ""
echo -e "${CYAN}🔍 For real-time monitoring:${NC}"
echo "  watch -n 2 './websocket-connections-per-pod.sh'"
