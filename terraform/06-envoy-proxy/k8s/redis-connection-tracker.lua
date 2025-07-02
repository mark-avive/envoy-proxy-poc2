-- Enhanced Redis Connection Tracker with Direct Redis Access
-- Following multi-envoy sample architecture for proper distributed state management

-- Import JSON library for parsing HTTP responses
local cjson = require("cjson")

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
        "redis_http_proxy_cluster",  -- Match the cluster name in envoy config
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
    
    local result_str, err = redis_http_call(handle, command)
    if not result_str then
        handle:logErr("[REDIS-TRACKER] Redis HTTP call failed: " .. (err or "unknown error"))
        return false, 0, "Redis HTTP call failed"
    end
    
    -- Parse JSON response: {"result": [true, 1, "success"]} or {"result": [false, 0, "limit_exceeded"]}
    local ok, response = pcall(cjson.decode, result_str)
    if not ok or not response.result then
        handle:logErr("[REDIS-TRACKER] Invalid JSON response: " .. tostring(result_str))
        return false, 0, "Invalid JSON response"
    end
    
    local result = response.result
    if #result < 3 then
        handle:logErr("[REDIS-TRACKER] Invalid Redis result: " .. tostring(result_str))
        return false, 0, "Invalid Redis response"
    end
    
    local allowed = (result[1] == true or result[1] == "true" or result[1] == "True")
    local count = tonumber(result[2]) or 0
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
        -- Parse JSON response for EVAL command
        local ok, response = pcall(cjson.decode, result)
        if ok and response.result then
            local count = tonumber(response.result) or 0
            handle:logInfo(string.format("[REDIS-TRACKER] Decremented connections for pod %s to %d", pod_id, count))
            return true
        else
            handle:logErr("[REDIS-TRACKER] Invalid JSON response from decrement: " .. tostring(result))
            return false
        end
    else
        handle:logErr("[REDIS-TRACKER] Failed to decrement pod connections: " .. (err or "unknown error"))
        return false
    end
end

-- Distributed atomic rate limiting with Redis (based on multi-envoy sample)
function redis_check_rate_limit(handle, requests_per_minute)
    local current_minute = math.floor(os.time() / 60)
    local key = string.format(REDIS_KEYS.RATE_LIMIT_WINDOW, current_minute)
    
    -- Use Redis Lua script for atomic increment + expire in single operation
    local lua_script = [[
        local key = KEYS[1]
        local current = redis.call('INCR', key)
        if current == 1 then
            redis.call('EXPIRE', key, 60)
        end
        return current
    ]]
    
    local escaped_script = string.gsub(lua_script, "\n", "\\n")
    escaped_script = string.gsub(escaped_script, "\t", "\\t")
    local command = string.format('EVAL "%s" 1 "%s"', escaped_script, key)
    
    local result, err = redis_http_call(handle, command)
    if not result then
        handle:logWarn("[REDIS-TRACKER] Redis unavailable for rate limiting, allowing request (fail-open)")
        return false  -- Fail open for rate limiting
    end
    
    -- Parse the atomic increment result
    local current_count = parse_redis_response(result, 0)
    local is_limited = current_count > requests_per_minute
    
    if is_limited then
        handle:logWarn(string.format("[REDIS-TRACKER] Rate limit exceeded: %d requests in current minute (limit: %d)", current_count, requests_per_minute))
    end
    
    return is_limited
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
    
    -- Global distributed rate limiting check only
    if redis_check_rate_limit(request_handle, CONFIG.RATE_LIMIT_REQUESTS) then
        request_handle:logWarn("[REDIS-TRACKER] Global rate limit exceeded")
        increment_counter(request_handle, REDIS_KEYS.REJECTED_CONNECTIONS)
        request_handle:respond(
            {[":status"] = "429", ["content-type"] = "text/plain"},
            "Rate limit exceeded globally"
        )
        return
    end
    
    request_handle:logInfo("[REDIS-TRACKER] Request passed rate limiting, proceeding to upstream")
end

-- Enhanced response handler with proper atomic connection tracking
function envoy_on_response(request_handle)
    local response_headers = request_handle:headers()
    local status = response_headers:get(":status")
    
    -- Only track WebSocket upgrade requests
    if not is_websocket_upgrade(request_handle:headers()) then
        return
    end
    
    request_handle:logInfo(string.format("[REDIS-TRACKER] Response status: %s", status or "unknown"))
    
    -- Get upstream pod information (multiple methods)
    local pod_id = nil
    local upstream_host = nil
    
    -- Method 1: Try to get from response headers (set by Envoy)
    local x_upstream_host = response_headers:get("x-upstream-host")
    if x_upstream_host and x_upstream_host ~= "" then
        upstream_host = x_upstream_host
        pod_id = string.match(upstream_host, "([^:]+)")
        request_handle:logInfo(string.format("[REDIS-TRACKER] Got upstream from headers: %s, Pod ID: %s", upstream_host, pod_id or "unknown"))
    else
        -- Method 2: Try streamInfo (might not be available in all Envoy versions)
        local stream_info = request_handle:streamInfo()
        if stream_info and stream_info.upstreamHost then
            upstream_host = stream_info.upstreamHost
            pod_id = string.match(upstream_host, "([^:]+)")
            request_handle:logInfo(string.format("[REDIS-TRACKER] Got upstream from streamInfo: %s, Pod ID: %s", upstream_host, pod_id or "unknown"))
        else
            request_handle:logWarn("[REDIS-TRACKER] Could not determine upstream host from headers or streamInfo")
        end
    end
    
    if not pod_id then
        request_handle:logWarn("[REDIS-TRACKER] No pod ID available, using service-level tracking")
        pod_id = "backend.default.svc.cluster.local"
    end
    
    if status == "101" and pod_id then  -- WebSocket upgrade successful
        -- CRITICAL: Use atomic check-and-increment to prevent race conditions
        local allowed, count, status_msg = redis_atomic_check_and_increment(request_handle, pod_id, CONFIG.MAX_CONNECTIONS_PER_POD)
        
        if allowed then
            request_handle:logInfo(string.format(
                "[REDIS-TRACKER] WebSocket established to pod %s: %d/%d connections (%s)",
                pod_id, count, CONFIG.MAX_CONNECTIONS_PER_POD, status_msg
            ))
            
            -- Increment global connection counter atomically
            increment_counter(request_handle, REDIS_KEYS.GLOBAL_CONNECTIONS)
            
            -- Store pod_id in response headers for cleanup tracking
            response_headers:add("x-tracked-pod-id", pod_id)
        else
            request_handle:logWarn(string.format(
                "[REDIS-TRACKER] Pod %s connection rejected: %d/%d (%s)",
                pod_id, count, CONFIG.MAX_CONNECTIONS_PER_POD, status_msg
            ))
            increment_counter(request_handle, REDIS_KEYS.REJECTED_CONNECTIONS)
            -- Note: Connection already established at this point, tracking for monitoring
        end
    elseif status and (status:match("^4%d%d") or status:match("^5%d%d")) then
        -- Track failed connections for monitoring
        request_handle:logInfo(string.format("[REDIS-TRACKER] WebSocket upgrade failed with status %s", status))
        increment_counter(request_handle, REDIS_KEYS.REJECTED_CONNECTIONS)
    end
end

-- Connection termination handler (atomic cleanup when WebSocket closes)
function envoy_on_stream_done(request_handle)
    -- Check if this was a tracked WebSocket connection
    local response_headers = request_handle:headers()
    local tracked_pod_id = response_headers:get("x-tracked-pod-id")
    
    if tracked_pod_id then
        -- Use the tracked pod ID for accurate cleanup
        request_handle:logInfo(string.format(
            "[REDIS-TRACKER] WebSocket connection closed - atomically decrementing count for tracked pod %s",
            tracked_pod_id
        ))
        redis_atomic_decrement(request_handle, tracked_pod_id)
        
        -- Atomically decrement global counter
        redis_http_call(request_handle, string.format('DECR "%s"', REDIS_KEYS.GLOBAL_CONNECTIONS))
    else
        -- Fallback: Try to get pod ID from upstream host (may not always work)
        local stream_info = request_handle:streamInfo()
        local upstream_host = stream_info:upstreamHost()
        
        if upstream_host then
            local pod_id = string.match(upstream_host, "([^:]+)")
            if pod_id then
                request_handle:logInfo(string.format(
                    "[REDIS-TRACKER] WebSocket connection closed - decrementing count for pod %s (fallback)",
                    pod_id
                ))
                redis_atomic_decrement(request_handle, pod_id)
                redis_http_call(request_handle, string.format('DECR "%s"', REDIS_KEYS.GLOBAL_CONNECTIONS))
            else
                request_handle:logWarn("[REDIS-TRACKER] Could not determine pod ID for connection cleanup")
            end
        else
            request_handle:logWarn("[REDIS-TRACKER] No upstream host available for connection cleanup")
        end
    end
end

-- Helper function to increment counters
function increment_counter(handle, key)
    local result, err = redis_http_call(handle, string.format('INCR "%s"', key))
    if not result then
        handle:logErr("[REDIS-TRACKER] Failed to increment counter " .. key .. ": " .. (err or "unknown error"))
    end
end

-- Helper function to parse JSON response from Redis HTTP calls
function parse_redis_response(response_str, default_value)
    default_value = default_value or 0
    if not response_str then
        return default_value
    end
    
    local ok, response = pcall(cjson.decode, response_str)
    if ok and response.result then
        return tonumber(response.result) or default_value
    else
        return default_value
    end
end

-- Metrics handler for multi-proxy aggregation
function handle_metrics_request(request_handle)
    local global_active, err1 = redis_http_call(request_handle, string.format('GET "%s"', REDIS_KEYS.GLOBAL_CONNECTIONS))
    local global_rejected, err2 = redis_http_call(request_handle, string.format('GET "%s"', REDIS_KEYS.REJECTED_CONNECTIONS))
    
    -- Parse JSON responses
    local active_count = parse_redis_response(global_active, 0)
    local rejected_count = parse_redis_response(global_rejected, 0)
    
    if not global_active or not global_rejected then
        request_handle:respond(
            {[":status"] = "503", ["content-type"] = "text/plain"},
            "Metrics unavailable - Redis HTTP call failed"
        )
        return
    end
    
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
]], active_count, rejected_count, CONFIG.PROXY_ID)
    
    request_handle:respond(
        {[":status"] = "200", ["content-type"] = "text/plain; charset=utf-8"},
        metrics
    )
end
