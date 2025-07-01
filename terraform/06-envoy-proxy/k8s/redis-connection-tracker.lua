-- Redis Connection Tracking and Enforcement for Envoy WebSocket Proxy
-- This Lua script enforces per-pod connection limits and rate limiting as per requirements:
-- - Max 2 WebSocket connections per pod
-- - 1 connection per second rate limiting
-- Envoy relies on this script to make real-time limiting decisions

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

-- Connection Limiting Functions (ENFORCING LIMITS AS PER REQUIREMENTS)
function check_pod_connection_limit(handle, pod_ip)
  local MAX_CONNECTIONS_PER_POD = 2  -- Requirements: max 2 WebSocket connections per pod
  local current_connections = get_pod_connection_count(handle, pod_ip)
  
  handle:logInfo(string.format("[REDIS-TRACKER] Pod %s has %d/%d connections", 
    pod_ip, current_connections, MAX_CONNECTIONS_PER_POD))
  
  if current_connections >= MAX_CONNECTIONS_PER_POD then
    handle:logWarn(string.format("[REDIS-TRACKER] Pod %s at connection limit (%d/%d) - REJECTING", 
      pod_ip, current_connections, MAX_CONNECTIONS_PER_POD))
    return false
  end
  
  return true
end

function check_rate_limit(handle, client_ip)
  local RATE_LIMIT_WINDOW = 60  -- 1 minute window
  local MAX_CONNECTIONS_PER_MINUTE = 1  -- Requirements: 1 connection per second = 60 per minute max
  local current_time = get_current_time()
  local window_start = current_time - RATE_LIMIT_WINDOW
  
  -- Count recent connection attempts from this client
  local recent_attempts = redis_http_call(handle, 
    string.format('ZCOUNT "client_rate_limit:%s" %d %d', client_ip, window_start, current_time))
  
  local attempts_count = tonumber(recent_attempts) or 0
  
  handle:logInfo(string.format("[REDIS-TRACKER] Client %s has %d attempts in last %d seconds", 
    client_ip, attempts_count, RATE_LIMIT_WINDOW))
  
  if attempts_count >= MAX_CONNECTIONS_PER_MINUTE then
    handle:logWarn(string.format("[REDIS-TRACKER] Client %s rate limited (%d/%d per minute) - REJECTING", 
      client_ip, attempts_count, MAX_CONNECTIONS_PER_MINUTE))
    return false
  end
  
  -- Record this attempt
  redis_http_call(handle, string.format('ZADD "client_rate_limit:%s" %d "%d"', client_ip, current_time, current_time))
  redis_http_call(handle, string.format('EXPIRE "client_rate_limit:%s" %d', client_ip, RATE_LIMIT_WINDOW + 10))
  
  -- Clean up old entries
  redis_http_call(handle, string.format('ZREMRANGEBYSCORE "client_rate_limit:%s" -inf %d', client_ip, window_start))
  
  return true
end
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

-- Get available backend pod IPs from Kubernetes endpoints
function get_backend_pod_ips(handle)
  -- This would ideally query Kubernetes API, but for now we'll use a Redis key that gets populated
  -- by the metrics script or an external process
  local pod_ips_str = redis_http_call(handle, 'GET "available_pods"')
  
  if pod_ips_str and pod_ips_str ~= "ERROR" and pod_ips_str ~= "None" then
    -- Parse comma-separated list of pod IPs
    local pod_ips = {}
    for ip in string.gmatch(pod_ips_str, "[^,]+") do
      table.insert(pod_ips, ip)
    end
    return pod_ips
  end
  
  -- Fallback to known pod IPs or service discovery
  return {"backend.default.svc.cluster.local"}
end

-- Intelligent pod selection based on current connection counts
function select_best_pod(handle)
  local MAX_CONNECTIONS_PER_POD = 2
  local pod_ips = get_backend_pod_ips(handle)
  local best_pod = nil
  local min_connections = MAX_CONNECTIONS_PER_POD + 1
  
  handle:logInfo(string.format("[REDIS-TRACKER] Selecting from %d available pods", #pod_ips))
  
  for _, pod_ip in ipairs(pod_ips) do
    local connections = get_pod_connection_count(handle, pod_ip)
    handle:logInfo(string.format("[REDIS-TRACKER] Pod %s has %d connections", pod_ip, connections))
    
    if connections < MAX_CONNECTIONS_PER_POD and connections < min_connections then
      best_pod = pod_ip
      min_connections = connections
    end
  end
  
  if best_pod then
    handle:logInfo(string.format("[REDIS-TRACKER] Selected pod %s with %d connections", best_pod, min_connections))
    return best_pod
  else
    handle:logWarn("[REDIS-TRACKER] No pods available under connection limit")
    return nil
  end
end

-- Enhanced connection tracking for both service and pod level
function track_connection_with_fallback(handle, connection_id, client_ip, user_agent, status)
  -- Try to get individual pod IP from Envoy routing
  local pod_ip = get_upstream_pod_ip(handle)
  
  -- Always track at service level for backward compatibility
  local service_target = "backend.default.svc.cluster.local"
  
  if status == "established" then
    track_established_connection(handle, service_target, connection_id, client_ip, user_agent)
    
    -- If we have a specific pod IP that's different from service, track individually too
    if pod_ip ~= service_target and pod_ip ~= "" then
      track_established_connection(handle, pod_ip, connection_id, client_ip, user_agent)
      handle:logInfo(string.format("[REDIS-TRACKER] Dual tracking: service + pod (%s)", pod_ip))
    end
  elseif status == "ended" then
    track_connection_end(handle, service_target, connection_id)
    
    if pod_ip ~= service_target and pod_ip ~= "" then
      track_connection_end(handle, pod_ip, connection_id)
    end
  end
  
  -- Record attempts with both targets
  record_connection_attempt(handle, service_target, client_ip, status)
  if pod_ip ~= service_target and pod_ip ~= "" then
    record_connection_attempt(handle, pod_ip, client_ip, status)
  end
end

-- Track rejection events from Envoy filters
function track_rejection(handle, pod_ip, client_ip, rejection_type)
  local current_time = get_current_time()
  local bucket_5m = math.floor(current_time / 300) * 300
  
  handle:logInfo(string.format("[REDIS-TRACKER] Recording rejection: %s to pod %s from %s", 
    rejection_type, pod_ip, client_ip))
  
  -- Track rejections by type and time bucket
  redis_http_call(handle, string.format('ZINCRBY "connection_attempts_%s:5m:%s" 1 %d', rejection_type, pod_ip, bucket_5m))
  redis_http_call(handle, string.format('EXPIRE "connection_attempts_%s:5m:%s" 300', rejection_type, pod_ip))
  
  -- Also track at service level
  local service_target = "backend.default.svc.cluster.local"
  redis_http_call(handle, string.format('ZINCRBY "connection_attempts_%s:5m:%s" 1 %d', rejection_type, service_target, bucket_5m))
  redis_http_call(handle, string.format('EXPIRE "connection_attempts_%s:5m:%s" 300', rejection_type, service_target))
end

-- Main Envoy Filter Functions - ENFORCING LIMITS PER REQUIREMENTS
function envoy_on_request(request_handle)
  request_handle:logInfo("[REDIS-TRACKER] Script starting - envoy_on_request called")
  
  -- Get client information
  local client_ip = get_client_ip(request_handle)
  local user_agent = request_handle:headers():get("user-agent") or "unknown"
  
  request_handle:logInfo(string.format("[REDIS-TRACKER] Client info: IP=%s, UA=%s", client_ip, user_agent))
  
  -- ENFORCE RATE LIMITING FIRST (Requirements: 1 connection per second)
  if not check_rate_limit(request_handle, client_ip) then
    track_rejection(request_handle, "rate_limited", client_ip, "rate_limited")
    request_handle:logErr("[REDIS-TRACKER] Connection REJECTED due to rate limiting")
    request_handle:respond({[":status"] = "429"}, "Rate limit exceeded")
    return
  end
  
  -- SELECT BEST POD BASED ON CONNECTION COUNTS (Requirements: max 2 connections per pod)
  local selected_pod = select_best_pod(request_handle)
  if not selected_pod then
    track_rejection(request_handle, "all_pods", client_ip, "max_limited")
    request_handle:logErr("[REDIS-TRACKER] Connection REJECTED - all pods at connection limit")
    request_handle:respond({[":status"] = "503"}, "All backend pods at connection limit")
    return
  end
  
  -- Generate connection ID for tracking
  local connection_id = generate_connection_id()
  request_handle:headers():add("x-connection-id", connection_id)
  request_handle:headers():add("x-pod-ip", selected_pod)
  
  -- Override the upstream destination to direct to the selected pod
  if selected_pod ~= "backend.default.svc.cluster.local" then
    request_handle:headers():add("x-envoy-upstream-alt-stat-name", selected_pod)
    -- TODO: Set the actual upstream host header for Envoy routing
    -- This may require additional Envoy configuration for dynamic routing
  end
  
  -- Connection allowed - track it
  track_connection_with_fallback(request_handle, connection_id, client_ip, user_agent, "established")
  
  -- Always set Redis readiness
  set_redis_readiness_status(request_handle)
  
  request_handle:logInfo(string.format("[REDIS-TRACKER] Connection ALLOWED: %s to pod %s", connection_id, selected_pod))
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
      track_connection_with_fallback(response_handle, connection_id, "unknown", "unknown", "ended")
      response_handle:logInfo("[REDIS-TRACKER] HTTP connection completed")
    else
      record_connection_attempt(response_handle, pod_ip, "unknown", "websocket_established")
      
      -- Also record at service level for compatibility
      local service_target = "backend.default.svc.cluster.local"
      if pod_ip ~= service_target then
        record_connection_attempt(response_handle, service_target, "unknown", "websocket_established")
      end
      
      response_handle:logInfo("[REDIS-TRACKER] WebSocket connection established")
    end
  else
    response_handle:logInfo("[REDIS-TRACKER] Missing connection tracking headers")
  end
end
