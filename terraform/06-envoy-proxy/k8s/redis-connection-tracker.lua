-- Enhanced Redis Connection Tracker with Direct Redis Access
-- Following multi-envoy sample architecture for proper distributed state management

-- Redis configuration
local REDIS_CONFIG = {
    HOST = os.getenv("REDIS_HOST") or "redis-connection-tracker.default.svc.cluster.local",
    PORT = tonumber(os.getenv("REDIS_PORT")) or 6379,
    TIMEOUT = 1000,
    POOL_SIZE = 10
}

-- Redis key patterns for distributed state
local REDIS_KEYS = {
    POD_CONNECTIONS = "ws:pod_conn:%s",           -- ws:pod_conn:pod-ip
    GLOBAL_CONNECTIONS = "ws:global_conn",        -- Total active connections
    RATE_LIMIT_WINDOW = "ws:rate_limit:%d",       -- ws:rate_limit:timestamp
    REJECTED_CONNECTIONS = "ws:rejected",         -- Total rejected
    PROXY_HEARTBEAT = "ws:proxy:%s:heartbeat"     -- Proxy health tracking
}

-- Configuration constants
local CONFIG = {
    MAX_CONNECTIONS_PER_POD = 2,                  -- Requirements: max 2 per pod
    RATE_LIMIT_REQUESTS = 60,                     -- 1 per second = 60 per minute
    PROXY_ID = os.getenv("HOSTNAME") or "envoy-unknown"
}

-- Get Redis connection via HTTP proxy
function get_redis_connection()
    -- Use HTTP proxy for Redis communication (Option B)
    -- This maintains atomicity while using proven HTTP patterns
    return "http_proxy", nil
end

-- HTTP-based Redis command execution
function redis_http_call(handle, command)
    local headers = {
        [":method"] = "POST",
        [":path"] = "/redis",
        [":authority"] = "redis-http-proxy.default.svc.cluster.local:8080",
        ["content-type"] = "text/plain"
    }
    
    local response_headers, response_body = handle:httpCall(
        "redis_http_proxy",  -- Match the cluster name in envoy config
        headers,
        command,
        1000  -- 1 second timeout
    )
    
    if response_headers and response_headers[":status"] == "200" then
        return response_body
    else
        return nil, string.format("HTTP Redis call failed: %s", response_headers and response_headers[":status"] or "no response")
    end
end

-- Atomic check-and-increment for pod connections (CRITICAL: Prevents race conditions)
function redis_atomic_check_and_increment(handle, pod_id, max_connections)
    local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    
    -- Redis Lua script for atomic check-and-increment
    local lua_script = [[
        local key = KEYS[1]
        local max_connections = tonumber(ARGV[1])
        local current = redis.call('GET', key)
        if current == false then
            current = 0
        else
            current = tonumber(current)
        end
        
        if current >= max_connections then
            return {false, current, "limit_exceeded"}
        else
            local new_count = redis.call('INCR', key)
            redis.call('EXPIRE', key, 86400)
            return {true, new_count, "success"}
        end
    ]]
    
    -- Execute atomic script via HTTP proxy
    local escaped_script = string.gsub(lua_script, "\n", "\\n")
    escaped_script = string.gsub(escaped_script, "\t", "\\t")
    local command = string.format('EVAL "%s" 1 "%s" %d', escaped_script, key, max_connections)
    
    local result_json, err = redis_http_call(handle, command)
    if not result_json then
        handle:logErr("[REDIS-TRACKER] Redis HTTP call failed: " .. (err or "unknown error"))
        return false, 0, "Redis HTTP call failed"
    end
    
    -- Parse JSON response from HTTP proxy
    local json = require("cjson")
    local success, result = pcall(json.decode, result_json)
    if not success or not result or type(result) ~= "table" or #result < 3 then
        handle:logErr("[REDIS-TRACKER] Invalid Redis response: " .. tostring(result_json))
        return false, 0, "Invalid Redis response"
    end
    
    local allowed = result[1]
    local count = result[2] 
    local status = result[3]
    
    return allowed, count, status
end

-- Atomic decrement for connection cleanup
function redis_atomic_decrement(handle, pod_id)
    local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    
    -- Redis Lua script for atomic decrement (don't go below 0)
    local lua_script = [[
        local key = KEYS[1]
        local current = redis.call('GET', key)
        if current == false or tonumber(current) <= 0 then
            return 0
        else
            return redis.call('DECR', key)
        end
    ]]
    
    local escaped_script = string.gsub(lua_script, "\n", "\\n")
    escaped_script = string.gsub(escaped_script, "\t", "\\t")
    local command = string.format('EVAL "%s" 1 "%s"', escaped_script, key)
    
    local result, err = redis_http_call(handle, command)
    if result then
        local count = tonumber(result) or 0
        handle:logInfo(string.format("[REDIS-TRACKER] Decremented connections for pod %s to %d", pod_id, count))
        return true
    else
        handle:logErr("[REDIS-TRACKER] Failed to decrement pod connections: " .. (err or "unknown error"))
        return false
    end
end

-- Distributed rate limiting with Redis
function redis_check_rate_limit(handle, requests_per_minute)
    local current_minute = math.floor(os.time() / 60)
    local key = string.format(REDIS_KEYS.RATE_LIMIT_WINDOW, current_minute)
    
    -- Increment and set expiration via HTTP calls
    local incr_result, err = redis_http_call(handle, string.format('INCR "%s"', key))
    if not incr_result then
        handle:logWarn("[REDIS-TRACKER] Redis unavailable for rate limiting, allowing request")
        return false  -- Fail open for rate limiting
    end
    
    -- Set expiration for the key
    redis_http_call(handle, string.format('EXPIRE "%s" 60', key))
    
    local current_count = tonumber(incr_result) or 0
    return current_count > requests_per_minute
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

-- Get pod ID from upstream (enhanced)
function get_pod_id_from_upstream(handle)
    -- Try to get actual upstream pod IP from Envoy routing
    local upstream_host = handle:headers():get("x-upstream-host")
    
    if upstream_host and upstream_host ~= "" then
        -- Extract IP from "ip:port" format
        local pod_ip = string.match(upstream_host, "^([^:]+)")
        return pod_ip
    end
    
    -- Fallback to service-level tracking
    return "backend.default.svc.cluster.local"
end

-- Main request handler with distributed coordination
function envoy_on_request(request_handle)
    local headers = request_handle:headers()
    
    -- Handle metrics endpoint
    if headers:get(":path") == "/websocket/metrics" then
        handle_metrics_request(request_handle)
        return
    end
    
    -- Only process WebSocket upgrades
    if not is_websocket_upgrade(headers) then
        return
    end
    
    request_handle:logInfo("[REDIS-TRACKER] Processing WebSocket upgrade request")
    
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
    
    -- ATOMIC check-and-increment to prevent race conditions
    local allowed, count, status = redis_atomic_check_and_increment(request_handle, pod_id, CONFIG.MAX_CONNECTIONS_PER_POD)
    
    if not allowed then
        request_handle:logWarn(string.format(
            "[REDIS-TRACKER] Pod %s connection rejected: %d/%d (%s)",
            pod_id, count, CONFIG.MAX_CONNECTIONS_PER_POD, status
        ))
        increment_counter(request_handle, REDIS_KEYS.REJECTED_CONNECTIONS)
        request_handle:respond(
            {[":status"] = "503", ["content-type"] = "text/plain"},
            "Pod connection limit exceeded"
        )
        return
    end
    
    request_handle:logInfo(string.format(
        "[REDIS-TRACKER] WebSocket upgrade ATOMICALLY reserved for pod %s (%d/%d connections)",
        pod_id, count, CONFIG.MAX_CONNECTIONS_PER_POD
    ))
    
    -- Store pod_id for cleanup on connection termination
    request_handle:headers():add("x-reserved-pod-id", pod_id)
end

-- Enhanced response handler with cleanup logic
function envoy_on_response(request_handle)
    local response_headers = request_handle:headers()
    local status = response_headers:get(":status")
    local pod_id = request_handle:headers():get("x-reserved-pod-id")
    
    if not pod_id then
        pod_id = get_pod_id_from_upstream(request_handle)
    end
    
    if status == "101" then  -- WebSocket upgrade successful
        if pod_id then
            -- Update global connection counter (the pod connection was already incremented atomically)
            increment_counter(request_handle, REDIS_KEYS.GLOBAL_CONNECTIONS)
            
            request_handle:logInfo(string.format(
                "[REDIS-TRACKER] WebSocket established to pod %s (connection already counted atomically)",
                pod_id
            ))
        end
    else
        -- WebSocket upgrade failed - need to decrement the reserved connection
        if pod_id and status and status ~= "101" then
            request_handle:logWarn(string.format(
                "[REDIS-TRACKER] WebSocket upgrade failed (status %s) - releasing reserved connection for pod %s",
                status, pod_id
            ))
            redis_atomic_decrement(request_handle, pod_id)
        end
    end
end

-- Connection termination handler (for cleanup when WebSocket closes)
function envoy_on_stream_done(request_handle)
    local pod_id = request_handle:headers():get("x-reserved-pod-id")
    if not pod_id then
        pod_id = get_pod_id_from_upstream(request_handle)
    end
    
    if pod_id then
        request_handle:logInfo(string.format(
            "[REDIS-TRACKER] WebSocket connection closed - decrementing count for pod %s",
            pod_id
        ))
        redis_atomic_decrement(request_handle, pod_id)
        
        -- Decrement global counter
        redis_http_call(request_handle, string.format('DECR "%s"', REDIS_KEYS.GLOBAL_CONNECTIONS))
    end
end

-- Helper function to increment counters
function increment_counter(handle, key)
    local result, err = redis_http_call(handle, string.format('INCR "%s"', key))
    if not result then
        handle:logErr("[REDIS-TRACKER] Failed to increment counter " .. key .. ": " .. (err or "unknown error"))
    end
end

-- Metrics handler for multi-proxy aggregation
function handle_metrics_request(request_handle)
    local global_active, err1 = redis_http_call(request_handle, string.format('GET "%s"', REDIS_KEYS.GLOBAL_CONNECTIONS))
    local global_rejected, err2 = redis_http_call(request_handle, string.format('GET "%s"', REDIS_KEYS.REJECTED_CONNECTIONS))
    
    if not global_active or not global_rejected then
        request_handle:respond(
            {[":status"] = "503", ["content-type"] = "text/plain"},
            "Metrics unavailable - Redis HTTP call failed"
        )
        return
    end
    
    global_active = tonumber(global_active) or 0
    global_rejected = tonumber(global_rejected) or 0
    
    local metrics = string.format([[
# HELP websocket_connections_active_total Total active WebSocket connections (all proxies)
# TYPE websocket_connections_active_total counter
websocket_connections_active_total %d

# HELP websocket_connections_rejected_total Total rejected WebSocket connections (all proxies)
# TYPE websocket_connections_rejected_total counter
websocket_connections_rejected_total %d

# HELP websocket_proxy_instance Instance identifier
# TYPE websocket_proxy_instance gauge
websocket_proxy_instance{proxy_id="%s"} 1
]], global_active, global_rejected, CONFIG.PROXY_ID)
    
    request_handle:respond(
        {[":status"] = "200", ["content-type"] = "text/plain; charset=utf-8"},
        metrics
    )
end
