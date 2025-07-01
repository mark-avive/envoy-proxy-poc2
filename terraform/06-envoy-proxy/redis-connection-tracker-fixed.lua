-- Redis Connection Tracking for Envoy WebSocket Proxy (FIXED)
-- This Lua script provides connection tracking and scaling metrics without limits
-- Envoy handles rate limiting and connection limits via its own filters

local redis_http_cluster = "redis_http_proxy"

-- Utility Functions
function get_current_time()
  return math.floor(os.time())
end

function generate_connection_id()
  local hostname = os.getenv("HOSTNAME") or "envoy"
  return string.format("%s-%d-%d", hostname, get_current_time(), math.random(10000, 99999))
end

function get_client_ip(request_handle)
  return request_handle:headers():get("x-forwarded-for") or 
         request_handle:headers():get("x-real-ip") or "unknown"
end

-- Redis HTTP Communication (FIXED to use handle)
function redis_http_call(handle, command)
  local headers = {
    [":method"] = "POST",
    [":path"] = "/redis",
    [":authority"] = "redis-http-proxy.default.svc.cluster.local:8080",
    ["content-type"] = "text/plain"
  }
  
  handle:logInfo("[REDIS-TRACKER] Making Redis HTTP call: " .. command)
  
  local response_headers, response_body = handle:httpCall(
    redis_http_cluster,
    headers,
    command,
    1000  -- 1 second timeout
  )
  
  if response_headers and response_headers[":status"] == "200" then
    handle:logInfo("[REDIS-TRACKER] Redis call successful: " .. (response_body or "empty response"))
    return response_body
  else
    local status = response_headers and response_headers[":status"] or "unknown"
    handle:logErr("[REDIS-TRACKER] Redis HTTP call failed with status: " .. status)
    return nil
  end
end

-- Connection Tracking Functions (NO LIMITS)
function get_pod_connection_count(handle, pod_ip)
  local response = redis_http_call(handle, string.format('SCARD "active_connections:%s"', pod_ip))
  return tonumber(response) or 0
end

function track_established_connection(handle, pod_ip, connection_id, client_ip, user_agent)
  local current_time = get_current_time()
  
  handle:logInfo(string.format("[REDIS-TRACKER] Tracking connection: %s to pod %s from %s", 
    connection_id, pod_ip, client_ip))
  
  -- Add to active connections set
  redis_http_call(handle, string.format('SADD "active_connections:%s" "%s"', pod_ip, connection_id))
  redis_http_call(handle, string.format('EXPIRE "active_connections:%s" 3600', pod_ip))
  
  -- Store connection details
  redis_http_call(handle, string.format('HMSET "connection:%s" "pod_ip" "%s" "client_ip" "%s" "established_time" "%d" "last_activity" "%d" "user_agent" "%s"', 
    connection_id, pod_ip, client_ip, current_time, current_time, user_agent or "unknown"))
  redis_http_call(handle, string.format('EXPIRE "connection:%s" 3600', connection_id))
  
  -- Update pod connection count
  local count = get_pod_connection_count(handle, pod_ip)
  redis_http_call(handle, string.format('SET "pod:established_count:%s" %d', pod_ip, count))
  redis_http_call(handle, string.format('EXPIRE "pod:established_count:%s" 3600', pod_ip))
  
  -- Update scaling data
  update_pod_scaling_metrics(handle, pod_ip, count)
  
  handle:logInfo(string.format("[REDIS-TRACKER] Connection established: %s to pod %s (total: %d)", 
    connection_id, pod_ip, count))
end

function track_connection_end(handle, pod_ip, connection_id)
  handle:logInfo(string.format("[REDIS-TRACKER] Ending connection: %s from pod %s", connection_id, pod_ip))
  
  -- Remove from active set
  redis_http_call(handle, string.format('SREM "active_connections:%s" "%s"', pod_ip, connection_id))
  
  -- Clean up connection details
  redis_http_call(handle, string.format('DEL "connection:%s"', connection_id))
  
  -- Update count
  local count = get_pod_connection_count(handle, pod_ip)
  redis_http_call(handle, string.format('SET "pod:established_count:%s" %d', pod_ip, count))
  
  -- Update scaling data
  update_pod_scaling_metrics(handle, pod_ip, count)
  
  handle:logInfo(string.format("[REDIS-TRACKER] Connection ended: %s from pod %s (remaining: %d)", 
    connection_id, pod_ip, count))
end

function update_pod_scaling_metrics(handle, pod_ip, active_connections)
  local current_time = get_current_time()
  
  -- Calculate priority (lower connections = higher priority for scale down)
  local priority_score = 10 - active_connections
  
  handle:logInfo(string.format("[REDIS-TRACKER] Updating scaling metrics for pod %s: %d connections", 
    pod_ip, active_connections))
  
  -- Update scaling data
  redis_http_call(handle, string.format('HMSET "pod:scaling_data:%s" "active_connections" "%d" "last_updated" "%d" "scaling_priority" "%d"', 
    pod_ip, active_connections, current_time, priority_score))
  redis_http_call(handle, string.format('EXPIRE "pod:scaling_data:%s" 3600', pod_ip))
  
  -- Add to scaling candidates
  redis_http_call(handle, string.format('ZADD "scaling:candidates:scale_down" %d "%s"', priority_score, pod_ip))
  redis_http_call(handle, 'EXPIRE "scaling:candidates:scale_down" 300')
  
  -- Set readiness flags
  set_redis_readiness_status(handle)
end

function set_redis_readiness_status(handle)
  handle:logInfo("[REDIS-TRACKER] Setting Redis readiness status")
  
  -- Set basic connectivity
  redis_http_call(handle, 'SET "redis:status:connected" "true"')
  redis_http_call(handle, 'EXPIRE "redis:status:connected" 300')
  
  -- Set scaling readiness (always ready for scaling data)
  redis_http_call(handle, 'SET "redis:status:ready_for_scaling" "true"')
  redis_http_call(handle, 'EXPIRE "redis:status:ready_for_scaling" 300')
end

function record_connection_attempt(handle, pod_ip, client_ip, status)
  local current_time = get_current_time()
  
  handle:logInfo(string.format("[REDIS-TRACKER] Recording connection attempt: pod %s, client %s, status %s", 
    pod_ip, client_ip, status or "unknown"))
  
  -- Track connection attempts for metrics (no limiting)
  local bucket_5m = math.floor(current_time / 300) * 300
  local bucket_15m = math.floor(current_time / 900) * 900
  local bucket_1h = math.floor(current_time / 3600) * 3600
  
  redis_http_call(handle, string.format('ZINCRBY "connection_attempts:5m:%s" 1 %d', pod_ip, bucket_5m))
  redis_http_call(handle, string.format('ZINCRBY "connection_attempts:15m:%s" 1 %d', pod_ip, bucket_15m))
  redis_http_call(handle, string.format('ZINCRBY "connection_attempts:1h:%s" 1 %d', pod_ip, bucket_1h))
  
  -- Set expiration for time buckets
  redis_http_call(handle, string.format('EXPIRE "connection_attempts:5m:%s" 300', pod_ip))
  redis_http_call(handle, string.format('EXPIRE "connection_attempts:15m:%s" 900', pod_ip))
  redis_http_call(handle, string.format('EXPIRE "connection_attempts:1h:%s" 3600', pod_ip))
  
  -- Track by status
  if status then
    redis_http_call(handle, string.format('ZINCRBY "connection_attempts_%s:5m:%s" 1 %d', status, pod_ip, bucket_5m))
    redis_http_call(handle, string.format('EXPIRE "connection_attempts_%s:5m:%s" 300', status, pod_ip))
  end
end

-- Main Envoy Filter Functions - TRACKING ONLY, NO LIMITS
function envoy_on_request(request_handle)
  request_handle:logInfo("[REDIS-TRACKER] Script starting - envoy_on_request called")
  
  -- Get client information
  local client_ip = get_client_ip(request_handle)
  local user_agent = request_handle:headers():get("user-agent") or "unknown"
  
  request_handle:logInfo(string.format("[REDIS-TRACKER] Client info: IP=%s, UA=%s", client_ip, user_agent))
  
  -- Get upstream pod IP - this should be set by Envoy routing
  local pod_ip = request_handle:headers():get("upstream_host")
  if not pod_ip or pod_ip == "" then
    -- Fallback: use backend service discovery
    pod_ip = "backend.default.svc.cluster.local"
    request_handle:logInfo("[REDIS-TRACKER] No upstream host found, using fallback: " .. pod_ip)
  else
    request_handle:logInfo("[REDIS-TRACKER] Using upstream host: " .. pod_ip)
  end
  
  -- Record connection attempt (no blocking)
  record_connection_attempt(request_handle, pod_ip, client_ip, "attempted")
  
  -- Generate connection ID for tracking
  local connection_id = generate_connection_id()
  request_handle:headers():add("x-connection-id", connection_id)
  request_handle:headers():add("x-pod-ip", pod_ip)
  
  request_handle:logInfo(string.format("[REDIS-TRACKER] Generated connection ID: %s", connection_id))
  
  -- Track all connections (no limits applied by Lua)
  track_established_connection(request_handle, pod_ip, connection_id, client_ip, user_agent)
  
  -- Always set Redis readiness
  set_redis_readiness_status(request_handle)
  
  request_handle:logInfo(string.format("[REDIS-TRACKER] Request processing complete for connection %s", connection_id))
end

function envoy_on_response(response_handle)
  response_handle:logInfo("[REDIS-TRACKER] Script starting - envoy_on_response called")
  
  local connection_id = response_handle:headers():get("x-connection-id")
  local pod_ip = response_handle:headers():get("x-pod-ip")
  
  response_handle:logInfo(string.format("[REDIS-TRACKER] Response info: connection_id=%s, pod_ip=%s", 
    connection_id or "none", pod_ip or "none"))
  
  if connection_id and pod_ip then
    -- For WebSocket connections, we track disconnections differently
    -- This is mainly for HTTP requests that complete immediately
    local upgrade_header = response_handle:headers():get("upgrade")
    if not upgrade_header or upgrade_header:lower() ~= "websocket" then
      track_connection_end(response_handle, pod_ip, connection_id)
      record_connection_attempt(response_handle, pod_ip, "unknown", "completed")
      response_handle:logInfo("[REDIS-TRACKER] HTTP connection completed")
    else
      record_connection_attempt(response_handle, pod_ip, "unknown", "websocket_established")
      response_handle:logInfo("[REDIS-TRACKER] WebSocket connection established")
    end
  else
    response_handle:logInfo("[REDIS-TRACKER] Missing connection tracking headers")
  end
end
