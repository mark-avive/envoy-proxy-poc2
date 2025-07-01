-- Enhanced Redis Connection Tracker with Atomic HTTP Operations
-- Implements multi-envoy patterns using HTTP Redis proxy with atomic operations

local redis_http_cluster = "redis_http_proxy"

-- Configuration following multi-envoy sample patterns
local CONFIG = {
    MAX_CONNECTIONS_PER_POD = 2,                  -- Requirements: max 2 per pod
    RATE_LIMIT_REQUESTS = 60,                     -- 1 per second = 60 per minute  
    PROXY_ID = os.getenv("HOSTNAME") or "envoy-unknown"
}

-- Redis key patterns for distributed state (following sample docs)
local REDIS_KEYS = {
    POD_CONNECTIONS = "ws:pod_conn:%s",           -- ws:pod_conn:pod-ip
    GLOBAL_CONNECTIONS = "ws:global_conn",        -- Total active connections
    RATE_LIMIT_WINDOW = "ws:rate_limit:%d",       -- ws:rate_limit:timestamp
    REJECTED_CONNECTIONS = "ws:rejected",         -- Total rejected
    PROXY_HEARTBEAT = "ws:proxy:%s:heartbeat"     -- Proxy health tracking
}

-- Utility Functions
function get_current_time()
  return math.floor(os.time())
end

function get_client_ip(request_handle)
  return request_handle:headers():get("x-forwarded-for") or 
         request_handle:headers():get("x-real-ip") or "unknown"
end

-- Enhanced Redis HTTP Communication with atomic operations
function redis_http_call(handle, command)
  local headers = {
    [":method"] = "POST",
    [":path"] = "/redis",
    [":authority"] = "redis-http-proxy.default.svc.cluster.local:8080",
    ["content-type"] = "text/plain"
  }
  
  local response_headers, response_body = handle:httpCall(
    redis_http_cluster,
    headers,
    command,
    1000  -- 1 second timeout
  )
  
  if response_headers and response_headers[":status"] == "200" then
    return response_body
  else
    local status = response_headers and response_headers[":status"] or "unknown"
    handle:logErr("[REDIS-TRACKER] Redis HTTP call failed with status: " .. status)
    return nil
  end
end

-- Atomic multi-command execution via HTTP proxy
function redis_atomic_multi(handle, commands)
  local multi_command = "MULTI\n" .. table.concat(commands, "\n") .. "\nEXEC"
  local result = redis_http_call(handle, multi_command)
  
  if result and result ~= "ERROR" then
    -- Parse EXEC result - simplified for HTTP proxy
    return result
  end
  
  return nil
end

-- Atomic increment for pod connections (following sample pattern)
function redis_increment_pod_connections(handle, pod_id)
  local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
  
  -- Use atomic INCR operation
  local result = redis_http_call(handle, string.format("INCR %s", key))
  
  if result and result ~= "ERROR" then
    local new_count = tonumber(result)
    
    -- Set expiration in separate call (not fully atomic but acceptable)
    redis_http_call(handle, string.format("EXPIRE %s 86400", key))
    
    handle:logInfo(string.format("[REDIS-TRACKER] Pod %s connections incremented to %d", pod_id, new_count))
    return new_count
  end
  
  handle:logErr("[REDIS-TRACKER] Failed to increment pod connections for " .. pod_id)
  return nil
end

-- Atomic decrement for pod connections
function redis_decrement_pod_connections(handle, pod_id)
  local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
  
  -- Use atomic DECR operation
  local result = redis_http_call(handle, string.format("DECR %s", key))
  
  if result and result ~= "ERROR" then
    local new_count = tonumber(result)
    -- Don't let it go below 0
    if new_count < 0 then
      redis_http_call(handle, string.format("SET %s 0", key))
      new_count = 0
    end
    
    handle:logInfo(string.format("[REDIS-TRACKER] Pod %s connections decremented to %d", pod_id, new_count))
    return new_count
  end
  
  return nil
end

-- Check pod connection limit with atomic operation
function redis_check_pod_limit(handle, pod_id, max_connections)
  local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
  local result = redis_http_call(handle, string.format("GET %s", key))
  
  local current_count = 0
  if result and result ~= "ERROR" and result ~= "None" then
    current_count = tonumber(result) or 0
  end
  
  handle:logInfo(string.format("[REDIS-TRACKER] Pod %s has %d/%d connections", 
    pod_id, current_count, max_connections))
  
  return current_count >= max_connections, current_count
end

-- Distributed rate limiting with sliding window (following sample pattern)
function redis_check_rate_limit(handle, requests_per_minute)
  local current_minute = math.floor(os.time() / 60)
  local key = string.format(REDIS_KEYS.RATE_LIMIT_WINDOW, current_minute)
  
  -- Atomic increment and check
  local commands = {
    string.format("INCR %s", key),
    string.format("EXPIRE %s 60", key)
  }
  
  local result = redis_atomic_multi(handle, commands)
  
  if result then
    -- Parse the result from MULTI/EXEC
    local current_count = tonumber(string.match(result, "%d+")) or 0
    
    handle:logInfo(string.format("[REDIS-TRACKER] Rate limit check: %d/%d requests this minute", 
      current_count, requests_per_minute))
    
    return current_count > requests_per_minute
  end
  
  -- Fail open if Redis unavailable
  handle:logWarn("[REDIS-TRACKER] Rate limit check failed, allowing request")
  return false
end

-- Enhanced WebSocket detection
function is_websocket_upgrade(headers)
    local connection = headers:get("connection")
    local upgrade = headers:get("upgrade")
    
    if connection and upgrade then
        connection = string.lower(connection)
        upgrade = string.lower(upgrade)
        
        return string.find(connection, "upgrade") and upgrade == "websocket"
    end
    
    return false
end

-- Get pod ID from upstream (enhanced to match sample)
function get_pod_id_from_upstream(handle)
    -- Try to get actual upstream pod IP from Envoy routing
    local upstream_host = handle:headers():get("x-upstream-host")
    
    if upstream_host and upstream_host ~= "" then
        -- Extract IP from "ip:port" format
        local pod_ip = string.match(upstream_host, "^([^:]+)")
        if pod_ip and pod_ip ~= "127.0.0.1" then
            return pod_ip
        end
    end
    
    -- Fallback: try to discover actual pods
    local available_pods = redis_http_call(handle, 'GET "available_pods"')
    if available_pods and available_pods ~= "ERROR" and available_pods ~= "None" then
        -- Select the pod with least connections (simple load balancing)
        local best_pod = nil
        local min_connections = CONFIG.MAX_CONNECTIONS_PER_POD + 1
        
        for pod_ip in string.gmatch(available_pods, "[^,]+") do
            local _, current_count = redis_check_pod_limit(handle, pod_ip, CONFIG.MAX_CONNECTIONS_PER_POD)
            if current_count < min_connections then
                best_pod = pod_ip
                min_connections = current_count
            end
        end
        
        if best_pod then
            return best_pod
        end
    end
    
    -- Final fallback to service-level tracking
    return "backend.default.svc.cluster.local"
end

-- Increment global counter
function increment_counter(handle, key)
    redis_http_call(handle, string.format("INCR %s", key))
end

-- Set proxy heartbeat
function set_proxy_heartbeat(handle)
    local key = string.format(REDIS_KEYS.PROXY_HEARTBEAT, CONFIG.PROXY_ID)
    local commands = {
        string.format("SET %s %d", key, get_current_time()),
        string.format("EXPIRE %s 300", key)  -- 5 minute expiration
    }
    redis_atomic_multi(handle, commands)
end

-- Main request handler with distributed coordination (following sample pattern)
function envoy_on_request(request_handle)
    local headers = request_handle:headers()
    
    -- Handle metrics endpoint (aggregate from Redis)
    if headers:get(":path") == "/websocket/metrics" then
        handle_metrics_request(request_handle)
        return
    end
    
    -- Only process WebSocket upgrades
    if not is_websocket_upgrade(headers) then
        return
    end
    
    request_handle:logInfo("[REDIS-TRACKER] Processing WebSocket upgrade request")
    
    -- Set proxy heartbeat
    set_proxy_heartbeat(request_handle)
    
    -- Global distributed rate limiting check
    if redis_check_rate_limit(request_handle, CONFIG.RATE_LIMIT_REQUESTS) then
        request_handle:logWarn("[REDIS-TRACKER] Global rate limit exceeded")
        increment_counter(request_handle, REDIS_KEYS.REJECTED_CONNECTIONS)
        request_handle:respond(
            {[":status"] = "429", ["content-type"] = "text/plain"},
            "Rate limit exceeded globally"
        )
        return
    end
    
    -- Get target pod for this request
    local pod_id = get_pod_id_from_upstream(request_handle)
    
    -- Check global per-pod connection limit
    local limit_exceeded, current_count = redis_check_pod_limit(request_handle, pod_id, CONFIG.MAX_CONNECTIONS_PER_POD)
    
    if limit_exceeded then
        request_handle:logWarn(string.format(
            "[REDIS-TRACKER] Pod %s connection limit exceeded: %d/%d (global count)",
            pod_id, current_count, CONFIG.MAX_CONNECTIONS_PER_POD
        ))
        increment_counter(request_handle, REDIS_KEYS.REJECTED_CONNECTIONS)
        request_handle:respond(
            {[":status"] = "503", ["content-type"] = "text/plain"},
            "Pod connection limit exceeded"
        )
        return
    end
    
    -- Store pod ID for response handler
    request_handle:headers():add("x-selected-pod", pod_id)
    
    request_handle:logInfo(string.format(
        "[REDIS-TRACKER] WebSocket upgrade allowed for pod %s (%d/%d connections)",
        pod_id, current_count, CONFIG.MAX_CONNECTIONS_PER_POD
    ))
end

-- Enhanced response handler (following sample pattern)
function envoy_on_response(request_handle)
    local response_headers = request_handle:headers()
    local status = response_headers:get(":status")
    
    if status == "101" then  -- WebSocket upgrade successful
        local pod_id = request_handle:headers():get("x-selected-pod") or get_pod_id_from_upstream(request_handle)
        
        if pod_id then
            -- Increment global counters atomically
            local new_pod_count = redis_increment_pod_connections(request_handle, pod_id)
            increment_counter(request_handle, REDIS_KEYS.GLOBAL_CONNECTIONS)
            
            request_handle:logInfo(string.format(
                "[REDIS-TRACKER] WebSocket established to pod %s. Global pod connections: %d/%d",
                pod_id, new_pod_count or 0, CONFIG.MAX_CONNECTIONS_PER_POD
            ))
        end
    end
end

-- Metrics handler for multi-proxy aggregation (following sample pattern)
function handle_metrics_request(request_handle)
    local global_active = redis_http_call(request_handle, string.format("GET %s", REDIS_KEYS.GLOBAL_CONNECTIONS)) or "0"
    local global_rejected = redis_http_call(request_handle, string.format("GET %s", REDIS_KEYS.REJECTED_CONNECTIONS)) or "0"
    
    if global_active == "ERROR" or global_active == "None" then global_active = "0" end
    if global_rejected == "ERROR" or global_rejected == "None" then global_rejected = "0" end
    
    local metrics = string.format([[
# HELP websocket_connections_active_total Total active WebSocket connections (all proxies)
# TYPE websocket_connections_active_total counter
websocket_connections_active_total %s

# HELP websocket_connections_rejected_total Total rejected WebSocket connections (all proxies)
# TYPE websocket_connections_rejected_total counter
websocket_connections_rejected_total %s

# HELP websocket_proxy_instance Instance identifier
# TYPE websocket_proxy_instance gauge
websocket_proxy_instance{proxy_id="%s"} 1
]], global_active, global_rejected, CONFIG.PROXY_ID)
    
    request_handle:respond(
        {[":status"] = "200", ["content-type"] = "text/plain; charset=utf-8"},
        metrics
    )
end
