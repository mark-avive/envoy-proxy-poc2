#!/bin/bash
# Envoy WebSocket Monitoring Script
# Assumes: kubectl port-forward svc/envoy-proxy-service 9901:9901 is running

echo "====================================================================="
echo "            ENVOY WEBSOCKET METRICS & CONFIGURATION"
echo "====================================================================="
echo ""

echo "1. === CIRCUIT BREAKER CONFIGURATION (Max Connections per Pod) ==="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/config_dump | jq '.configs[1].static_clusters[0].cluster.circuit_breakers.thresholds[0]' | \
jq '{
  "Max Connections": .max_connections,
  "Max Pending Requests": .max_pending_requests, 
  "Max Requests": .max_requests,
  "Max Retries": .max_retries
}'
echo ""

echo "2. === RATE LIMITING CONFIGURATION ===="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/config_dump | jq -r '
.configs[] | 
select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ListenersConfigDump") |
.static_listeners[0].listener.filter_chains[0].filters[0].typed_config.http_filters[] |
select(.name == "envoy.filters.http.local_ratelimit") |
.typed_config.token_bucket |
{
  "Max Tokens (Rate Limit)": .max_tokens,
  "Tokens per Fill": .tokens_per_fill,
  "Fill Interval": .fill_interval
}'
echo ""

echo "3. === CURRENT CIRCUIT BREAKER STATISTICS ===="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/stats | grep -E "cluster\.websocket_cluster\.circuit_breakers" | \
awk '{
  if ($1 ~ /cx_open/) print "🔴 Connections Circuit Breaker Open: " $2
  else if ($1 ~ /cx_pool_full/) print "🟠 Connection Pool Full: " $2  
  else if ($1 ~ /rq_open/) print "🔴 Requests Circuit Breaker Open: " $2
  else if ($1 ~ /rq_pending_open/) print "🔴 Pending Requests Circuit Breaker Open: " $2
  else if ($1 ~ /rq_retry_open/) print "🔴 Retry Circuit Breaker Open: " $2
  else print $1 ": " $2
}'
echo ""

echo "4. === WEBSOCKET CONNECTION STATISTICS ===="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/stats | grep -E "cluster\.websocket_cluster\." | \
grep -E "(cx_|upstream_cx_)" | \
awk '{
  if ($1 ~ /upstream_cx_total/) print "📊 Total Upstream Connections Created: " $2
  else if ($1 ~ /upstream_cx_active/) print "✅ Active Upstream Connections: " $2
  else if ($1 ~ /upstream_cx_http1_total/) print "📈 HTTP/1.1 Connections: " $2
  else if ($1 ~ /upstream_cx_connect_fail/) print "❌ Connection Failures: " $2
  else if ($1 ~ /upstream_cx_connect_timeout/) print "⏰ Connection Timeouts: " $2
  else if ($1 ~ /upstream_cx_destroy/) print "🗑️ Connections Destroyed: " $2
  else if ($1 ~ /upstream_cx_destroy_local/) print "🏠 Local Connection Destroys: " $2
  else if ($1 ~ /upstream_cx_destroy_remote/) print "🌐 Remote Connection Destroys: " $2
}'
echo ""

echo "5. === REQUEST AND RESPONSE STATISTICS ===="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/stats | grep -E "cluster\.websocket_cluster\." | \
grep -E "(upstream_rq_|retry_)" | \
awk '{
  if ($1 ~ /upstream_rq_total/) print "📋 Total Requests: " $2
  else if ($1 ~ /upstream_rq_active/) print "⚡ Active Requests: " $2
  else if ($1 ~ /upstream_rq_pending_total/) print "⏳ Pending Requests: " $2
  else if ($1 ~ /upstream_rq_pending_active/) print "⏳ Active Pending Requests: " $2
  else if ($1 ~ /upstream_rq_retry/) print "🔄 Request Retries: " $2
  else if ($1 ~ /upstream_rq_timeout/) print "⏰ Request Timeouts: " $2
  else if ($1 ~ /upstream_rq_2xx/) print "✅ HTTP 2xx Responses: " $2
  else if ($1 ~ /upstream_rq_4xx/) print "⚠️ HTTP 4xx Responses: " $2
  else if ($1 ~ /upstream_rq_5xx/) print "❌ HTTP 5xx Responses: " $2
}'
echo ""

echo "6. === RATE LIMITING STATISTICS ===="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/stats | grep -E "http\..*\.local_rate_limit" | \
awk '{
  if ($1 ~ /enabled/) print "✅ Rate Limiting Enabled: " $2
  else if ($1 ~ /enforced/) print "🚫 Rate Limiting Enforced: " $2
  else if ($1 ~ /rate_limited/) print "🛑 Requests Rate Limited: " $2
  else if ($1 ~ /ok/) print "✅ Requests Allowed: " $2
  else print $1 ": " $2
}'
echo ""

echo "7. === WEBSOCKET UPGRADE STATISTICS ===="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/stats | grep -E "(websocket|upgrade)" | \
awk '{
  if ($1 ~ /websocket/) print "🔌 WebSocket: " $1 " = " $2
  else if ($1 ~ /upgrade/) print "⬆️ Upgrade: " $1 " = " $2
}'
echo ""

echo "8. === HEALTH CHECK STATUS ===="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/stats | grep -E "cluster\.websocket_cluster\.health_check" | \
awk '{
  if ($1 ~ /attempt/) print "🏥 Health Check Attempts: " $2
  else if ($1 ~ /success/) print "✅ Health Check Success: " $2
  else if ($1 ~ /failure/) print "❌ Health Check Failures: " $2
  else if ($1 ~ /healthy/) print "💚 Healthy Endpoints: " $2
  else print $1 ": " $2
}'
echo ""

echo "9. === ENDPOINT HEALTH STATUS ===="
echo "---------------------------------------------------------------------"
curl -s http://localhost:9901/clusters | grep -A 20 "websocket_cluster" | \
grep -E "(healthy|unhealthy|no_traffic)" | head -10
echo ""

echo "10. === CURRENT CONFIGURATION SUMMARY ===="
echo "---------------------------------------------------------------------"
echo "Based on locals.tf and live config:"
curl -s http://localhost:9901/config_dump | jq -r '.configs[1].static_clusters[0].cluster.circuit_breakers.thresholds[0]' | \
jq -r '"Max Connections per Server Pod: " + (.max_connections | tostring)'

curl -s http://localhost:9901/config_dump | jq -r '
.configs[] | 
select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ListenersConfigDump") |
.static_listeners[0].listener.filter_chains[0].filters[0].typed_config.http_filters[] |
select(.name == "envoy.filters.http.local_ratelimit") |
.typed_config.token_bucket' | \
jq -r '"Rate Limit: " + (.max_tokens | tostring) + " tokens, " + (.tokens_per_fill | tostring) + " per " + .fill_interval'

echo ""
echo "====================================================================="
echo "                    MONITORING COMMANDS"
echo "====================================================================="
echo "Watch live connection changes:"
echo "  watch -n 2 'curl -s http://localhost:9901/stats | grep cluster.websocket_cluster.upstream_cx_active'"
echo ""
echo "Monitor rate limiting:"
echo "  watch -n 1 'curl -s http://localhost:9901/stats | grep local_rate_limit'"
echo ""
echo "View cluster health:"
echo "  curl -s http://localhost:9901/clusters"
echo ""
echo "Real-time stats:"
echo "  curl -s http://localhost:9901/stats | grep websocket"
echo "====================================================================="
