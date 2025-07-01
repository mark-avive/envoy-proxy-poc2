-- Redis Connection Tracking for Envoy WebSocket Proxy
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

function log_info(message)
  if envoy and envoy.log and envoy.log_levels then
    envoy.log(envoy.log_levels.info, "[REDIS-TRACKER] " .. message)
  end
end

function log_error(message)
  if envoy and envoy.log and envoy.log_levels then
    envoy.log(envoy.log_levels.error, "[REDIS-TRACKER] " .. message)
  end
end

-- Redis HTTP Communication
function redis_http_call(command)
  if not envoy or not envoy.httpCall then
    return nil
  end
  
  local headers = {
    [":method"] = "POST",
    [":path"] = "/redis",
    [":authority"] = "redis-http-proxy.default.svc.cluster.local:8080",
    ["content-type"] = "text/plain"
  }
  
  local response_headers, response_body = envoy.httpCall(
    redis_http_cluster,
    headers,
    command,
    1000  -- 1 second timeout
  )
  
  if response_headers and response_headers[":status"] == "200" then
    return response_body
  else
    log_error("Redis HTTP call failed: " .. (response_headers and response_headers[":status"] or "unknown"))
    return nil
  end
end

-- Connection Tracking Functions (NO LIMITS)
function get_pod_connection_count(pod_ip)
  local response = redis_http_call(string.format('SCARD "active_connections:%s"', pod_ip))
  return tonumber(response) or 0
end

function track_established_connection(pod_ip, connection_id, client_ip, user_agent)
  local current_time = get_current_time()
  
  -- Add to active connections set
  redis_http_call(string.format('SADD "active_connections:%s" "%s"', pod_ip, connection_id))
  redis_http_call(string.format('EXPIRE "active_connections:%s" 3600', pod_ip))
  
  -- Store connection details
  redis_http_call(string.format('HMSET "connection:%s" "pod_ip" "%s" "client_ip" "%s" "established_time" "%d" "last_activity" "%d" "user_agent" "%s"', 
    connection_id, pod_ip, client_ip, current_time, current_time, user_agent or "unknown"))
  redis_http_call(string.format('EXPIRE "connection:%s" 3600', connection_id))
  
  -- Update pod connection count
  local count = get_pod_connection_count(pod_ip)
  redis_http_call(string.format('SET "pod:established_count:%s" %d', pod_ip, count))
  redis_http_call(string.format('EXPIRE "pod:established_count:%s" 3600', pod_ip))
  
  -- Update scaling data
  update_pod_scaling_metrics(pod_ip, count)
  
  log_info(string.format("Connection established: %s to pod %s (total: %d)", connection_id, pod_ip, count))
end

function track_connection_end(pod_ip, connection_id)
  -- Remove from active set
  redis_http_call(string.format('SREM "active_connections:%s" "%s"', pod_ip, connection_id))
  
  -- Clean up connection details
  redis_http_call(string.format('DEL "connection:%s"', connection_id))
  
  -- Update count
  local count = get_pod_connection_count(pod_ip)
  redis_http_call(string.format('SET "pod:established_count:%s" %d', pod_ip, count))
  
  -- Update scaling data
  update_pod_scaling_metrics(pod_ip, count)
  
  log_info(string.format("Connection ended: %s from pod %s (remaining: %d)", connection_id, pod_ip, count))
end

function update_pod_scaling_metrics(pod_ip, active_connections)
  local current_time = get_current_time()
  
  -- Calculate priority (lower connections = higher priority for scale down)
  local priority_score = 10 - active_connections
  
  -- Update scaling data
  redis_http_call(string.format('HMSET "pod:scaling_data:%s" "active_connections" "%d" "last_updated" "%d" "scaling_priority" "%d"', 
    pod_ip, active_connections, current_time, priority_score))
  redis_http_call(string.format('EXPIRE "pod:scaling_data:%s" 3600', pod_ip))
  
  -- Add to scaling candidates
  redis_http_call(string.format('ZADD "scaling:candidates:scale_down" %d "%s"', priority_score, pod_ip))
  redis_http_call('EXPIRE "scaling:candidates:scale_down" 300')
  
  -- Set readiness flags
  set_redis_readiness_status()
end

function set_redis_readiness_status()
  -- Set basic connectivity
  redis_http_call('SET "redis:status:connected" "true"')
  redis_http_call('EXPIRE "redis:status:connected" 300')
  
  -- Set scaling readiness (always ready for scaling data)
  redis_http_call('SET "redis:status:ready_for_scaling" "true"')
  redis_http_call('EXPIRE "redis:status:ready_for_scaling" 300')
end

function record_connection_attempt(pod_ip, client_ip, status)
  local current_time = get_current_time()
  
  -- Track connection attempts for metrics (no limiting)
  local bucket_5m = math.floor(current_time / 300) * 300
  local bucket_15m = math.floor(current_time / 900) * 900
  local bucket_1h = math.floor(current_time / 3600) * 3600
  
  redis_http_call(string.format('ZINCRBY "connection_attempts:5m:%s" 1 %d', pod_ip, bucket_5m))
  redis_http_call(string.format('ZINCRBY "connection_attempts:15m:%s" 1 %d', pod_ip, bucket_15m))
  redis_http_call(string.format('ZINCRBY "connection_attempts:1h:%s" 1 %d', pod_ip, bucket_1h))
  
  -- Set expiration for time buckets
  redis_http_call(string.format('EXPIRE "connection_attempts:5m:%s" 300', pod_ip))
  redis_http_call(string.format('EXPIRE "connection_attempts:15m:%s" 900', pod_ip))
  redis_http_call(string.format('EXPIRE "connection_attempts:1h:%s" 3600', pod_ip))
  
  -- Track by status
  if status then
    redis_http_call(string.format('ZINCRBY "connection_attempts_%s:5m:%s" 1 %d', status, pod_ip, bucket_5m))
    redis_http_call(string.format('EXPIRE "connection_attempts_%s:5m:%s" 300', status, pod_ip))
  end
  
  log_info(string.format("Connection attempt recorded for pod %s from client %s (status: %s)", pod_ip, client_ip, status or "unknown"))
end

-- Main Envoy Filter Functions - TRACKING ONLY, NO LIMITS
function envoy_on_request(request_handle)
  -- Get client information
  local client_ip = get_client_ip(request_handle)
  local user_agent = request_handle:headers():get("user-agent") or "unknown"
  
  -- Get upstream pod IP - this should be set by Envoy routing
  local pod_ip = request_handle:headers():get("upstream_host")
  if not pod_ip or pod_ip == "" then
    -- Fallback: use backend service discovery
    pod_ip = "backend.default.svc.cluster.local"
    log_info("No upstream host found, using fallback: " .. pod_ip)
  end
  
  -- Record connection attempt (no blocking)
  record_connection_attempt(pod_ip, client_ip, "attempted")
  
  -- Generate connection ID for tracking
  local connection_id = generate_connection_id()
  request_handle:headers():add("x-connection-id", connection_id)
  request_handle:headers():add("x-pod-ip", pod_ip)
  
  -- Track all connections (no limits applied by Lua)
  track_established_connection(pod_ip, connection_id, client_ip, user_agent)
  
  -- Always set Redis readiness
  set_redis_readiness_status()
  
  log_info(string.format("Request tracked for pod %s with connection ID %s (tracking only - no limits)", 
    pod_ip, connection_id))
end

function envoy_on_response(response_handle)
  local connection_id = response_handle:headers():get("x-connection-id")
  local pod_ip = response_handle:headers():get("x-pod-ip")
  
  if connection_id and pod_ip then
    -- For WebSocket connections, we track disconnections differently
    -- This is mainly for HTTP requests that complete immediately
    local upgrade_header = response_handle:headers():get("upgrade")
    if not upgrade_header or upgrade_header:lower() ~= "websocket" then
      track_connection_end(pod_ip, connection_id)
      record_connection_attempt(pod_ip, "unknown", "completed")
    else
      record_connection_attempt(pod_ip, "unknown", "websocket_established")
    end
  end
end

-- Always ensure Redis readiness on script load
set_redis_readiness_status()
log_info("Redis connection tracker initialized - TRACKING ONLY MODE (no limits)")
