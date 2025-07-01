#!/bin/bash

# Test script to simulate Lua connection tracking
# This script mimics what the Lua script should be doing

set -e

echo "=== Testing Redis Integration via HTTP Proxy ==="

# Function to execute Redis commands via HTTP proxy
redis_exec() {
    kubectl run redis-test-$(date +%s) --image=curlimages/curl --rm -i --restart=Never -- \
        curl -X POST -H "Content-Type: text/plain" -d "$*" \
        http://redis-http-proxy.default.svc.cluster.local:8080/redis
}

# Simulate connection tracking
CURRENT_TIME=$(date +%s)
POD_IP="172.245.10.137"  # Use one of the backend pod IPs
CONNECTION_ID="envoy-test-${CURRENT_TIME}-12345"
CLIENT_IP="10.0.1.100"

echo "🔗 Simulating connection establishment..."
echo "Pod IP: $POD_IP"
echo "Connection ID: $CONNECTION_ID"
echo "Client IP: $CLIENT_IP"

# 1. Increment connection count
echo ""
echo "1. Incrementing connection count..."
CONN_COUNT=$(redis_exec "INCR \"conn:$POD_IP\"")
echo "New count: $CONN_COUNT"

# 2. Add to active connections set
echo ""
echo "2. Adding to active connections set..."
redis_exec "SADD \"active_connections:$POD_IP\" \"$CONNECTION_ID\""
redis_exec "EXPIRE \"active_connections:$POD_IP\" 3600"

# 3. Store connection details
echo ""
echo "3. Storing connection details..."
redis_exec "HMSET \"connection:$CONNECTION_ID\" \"pod_ip\" \"$POD_IP\" \"client_ip\" \"$CLIENT_IP\" \"established_time\" \"$CURRENT_TIME\" \"last_activity\" \"$CURRENT_TIME\" \"user_agent\" \"test-client\""
redis_exec "EXPIRE \"connection:$CONNECTION_ID\" 3600"

# 4. Update pod connection count
echo ""
echo "4. Updating pod connection count..."
ACTIVE_COUNT=$(redis_exec "SCARD \"active_connections:$POD_IP\"")
redis_exec "SET \"pod:established_count:$POD_IP\" $ACTIVE_COUNT"
redis_exec "EXPIRE \"pod:established_count:$POD_IP\" 3600"

# 5. Update scaling data
echo ""
echo "5. Updating scaling data..."
PRIORITY=$((10 - ACTIVE_COUNT))
redis_exec "HMSET \"pod:scaling_data:$POD_IP\" \"active_connections\" \"$ACTIVE_COUNT\" \"last_updated\" \"$CURRENT_TIME\" \"scaling_priority\" \"$PRIORITY\""
redis_exec "EXPIRE \"pod:scaling_data:$POD_IP\" 3600"

# 6. Add to scaling candidates
echo ""
echo "6. Adding to scaling candidates..."
redis_exec "ZADD \"scaling:candidates:scale_down\" $PRIORITY \"$POD_IP\""
redis_exec "EXPIRE \"scaling:candidates:scale_down\" 300"

# 7. Set readiness flags
echo ""
echo "7. Setting readiness flags..."
redis_exec "SET \"redis:status:connected\" \"true\""
redis_exec "EXPIRE \"redis:status:connected\" 300"
redis_exec "SET \"redis:status:ready_for_scaling\" \"true\""
redis_exec "EXPIRE \"redis:status:ready_for_scaling\" 300"

echo ""
echo "✅ Connection tracking simulation completed!"
echo ""
echo "📊 Now testing query system..."
