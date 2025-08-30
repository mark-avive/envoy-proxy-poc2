-- Enhanced Redis Connection Tracker with Direct Redis and Atomic Operations
-- Based on multi-envoy sample architecture and docs2/ atomic design patterns

-- Import JSON library for metrics formatting
local cjson = require("cjson")

-- Redis configuration for direct connections
local REDIS_CONFIG = {
    HOST = os.getenv("REDIS_HOST") or "redis-connection-tracker.default.svc.cluster.local",
    PORT = tonumber(os.getenv("REDIS_PORT")) or 6379,
    TIMEOUT = 5000,  -- 5 second timeout for stability
    POOL_SIZE = 10
}

-- Redis key patterns for distributed state
local REDIS_KEYS = {
    POD_CONNECTIONS = "ws:pod_conn:%s",           -- ws:pod_conn:pod-ip
    GLOBAL_CONNECTIONS = "ws:global_conn",        -- Total active connections
    RATE_LIMIT_WINDOW = "ws:rate_limit:%d",       -- ws:rate_limit:timestamp
    REJECTED_CONNECTIONS = "ws:rejected",         -- Total rejected
    PROXY_CONNECTIONS = "ws:proxy:%s:connections", -- Per-proxy tracking
    ALL_CONNECTIONS = "ws:all_connections",       -- Set of all connection IDs
    ACTIVE_PODS = "ws:active_pods"                -- Set of active pod IDs
}

-- Configuration constants
local CONFIG = {
    MAX_CONNECTIONS_PER_POD = 2,                  -- Requirements: max 2 per pod
    RATE_LIMIT_REQUESTS = 60,                     -- 1 per second = 60 per minute
    PROXY_ID = os.getenv("HOSTNAME") or "envoy-unknown",
    CONNECTION_TTL = 7200                         -- 2 hours for connection metadata
}

-- ==============================================================================
--                    ATOMIC CONNECTION LIMIT ENFORCEMENT
-- ==============================================================================

-- Redis Lua script for atomic connection checking and incrementing
local REDIS_ATOMIC_SCRIPT = [[
    local pod_key = KEYS[1]              -- ws:pod_conn:pod-ip
    local max_connections = tonumber(ARGV[1])
    local connection_id = ARGV[2]
    local proxy_id = ARGV[3]
    local current_time = ARGV[4]
    
    -- Get current connection count
    local current_count = redis.call('GET', pod_key)
    current_count = tonumber(current_count) or 0
    
    -- Check if limit would be exceeded
    if current_count >= max_connections then
        return {0, current_count, "LIMIT_EXCEEDED"}
    end
    
    -- Atomically increment and set metadata
    local new_count = redis.call('INCR', pod_key)
    redis.call('EXPIRE', pod_key, 86400)  -- 24 hour TTL for pod connections
    
    -- Track connection details
    local conn_detail_key = 'ws:conn:' .. connection_id
    local conn_data = {
        'pod_id', string.match(pod_key, 'ws:pod_conn:(.+)'),
        'proxy_id', proxy_id,
        'created_at', current_time,
        'last_seen', current_time
    }
    redis.call('HMSET', conn_detail_key, unpack(conn_data))
    redis.call('EXPIRE', conn_detail_key, ]] .. CONFIG.CONNECTION_TTL .. [[)
    
    -- Add to global connection registry
    redis.call('SADD', 'ws:all_connections', connection_id)
    redis.call('SADD', 'ws:active_pods', string.match(pod_key, 'ws:pod_conn:(.+)'))
    
    -- Increment proxy-specific counter
    local proxy_key = 'ws:proxy:' .. proxy_id .. ':connections'
    redis.call('INCR', proxy_key)
    redis.call('EXPIRE', proxy_key, 86400)
    
    return {1, new_count, "SUCCESS"}
]]

-- Atomic cleanup script for connection removal
local REDIS_CLEANUP_SCRIPT = [[
    local pod_key = KEYS[1]              -- ws:pod_conn:pod-ip
    local connection_id = ARGV[1]
    local proxy_id = ARGV[2]
    
    -- Get current count
    local current_count = redis.call('GET', pod_key)
    current_count = tonumber(current_count) or 0
    
    if current_count <= 0 then
        return {0, 0, "ALREADY_ZERO"}
    end
    
    -- Atomically decrement
    local new_count = redis.call('DECR', pod_key)
    if new_count < 0 then
        redis.call('SET', pod_key, 0)
        new_count = 0
    end
    
    -- Remove connection details
    local conn_detail_key = 'ws:conn:' .. connection_id
    redis.call('DEL', conn_detail_key)
    redis.call('SREM', 'ws:all_connections', connection_id)
    
    -- Decrement proxy-specific counter
    local proxy_key = 'ws:proxy:' .. proxy_id .. ':connections'
    local proxy_count = redis.call('DECR', proxy_key)
    if proxy_count < 0 then
        redis.call('SET', proxy_key, 0)
    end
    
    return {1, new_count, "SUCCESS"}
]]

-- Rate limiting script
local REDIS_RATE_LIMIT_SCRIPT = [[
    local key = KEYS[1]
    local current = redis.call('INCR', key)
    if current == 1 then
        redis.call('EXPIRE', key, 60)
    end
    return current
]]

-- Get direct Redis connection
function get_redis_connection(handle)
    -- Use Envoy's Redis connection capabilities
    -- This creates a direct TCP connection to Redis
    local redis_client = handle:httpCall(
        "redis_direct",  -- Need to define this cluster in Envoy config
        {
            [":method"] = "GET",
            [":path"] = "/ping",
            [":authority"] = REDIS_CONFIG.HOST .. ":" .. REDIS_CONFIG.PORT
        },
        "",
        REDIS_CONFIG.TIMEOUT
    )
    
    return redis_client
end

-- Execute Redis Lua script atomically
function execute_redis_script(handle, script, keys, args)
    -- For now, fall back to HTTP proxy for script execution
    -- TODO: Implement direct Redis protocol support
    
    local escaped_script = string.gsub(script, "\n", "\\n")
    escaped_script = string.gsub(escaped_script, "\t", "\\t")
    escaped_script = string.gsub(escaped_script, '"', '\\"')
    
    local key_count = #keys
    local cmd_parts = {'EVAL', '"' .. escaped_script .. '"', tostring(key_count)}
    
    -- Add keys
    for _, key in ipairs(keys) do
        table.insert(cmd_parts, '"' .. key .. '"')
    end
    
    -- Add arguments
    for _, arg in ipairs(args) do
        table.insert(cmd_parts, '"' .. tostring(arg) .. '"')
    end
    
    local command = table.concat(cmd_parts, " ")
    
    -- Execute via HTTP proxy
    local headers = {
        [":method"] = "POST",
        [":path"] = "/redis",
        [":authority"] = "redis-http-proxy.default.svc.cluster.local:8080",
        ["content-type"] = "text/plain"
    }
    
    local response_headers, response_body = handle:httpCall(
        "redis_http_proxy_cluster",
        headers,
        command,
        5000  -- 5 second timeout
    )
    
    if response_headers and response_headers[":status"] == "200" then
        -- Parse JSON response
        local ok, response = pcall(cjson.decode, response_body)
        if ok and response.result then
            return response.result
        else
            handle:logErr("[REDIS-TRACKER] Invalid JSON response: " .. tostring(response_body))
            return nil
        end
    else
        handle:logErr("[REDIS-TRACKER] Redis script execution failed: " .. (response_headers and response_headers[":status"] or "no response"))
        return nil
    end
end

-- Enhanced atomic connection limit enforcement
function enforce_pod_connection_limit_atomic(handle, pod_id, connection_id)
    if not pod_id or not connection_id then
        handle:logErr("[REDIS-TRACKER] Missing pod_id or connection_id")
        return false, 0, "INVALID_PARAMETERS"
    end
    
    local pod_key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    local current_time = tostring(os.time())
    
    local result = execute_redis_script(
        handle,
        REDIS_ATOMIC_SCRIPT,
        {pod_key},  -- KEYS
        {CONFIG.MAX_CONNECTIONS_PER_POD, connection_id, CONFIG.PROXY_ID, current_time}  -- ARGV
    )
    
    if not result or #result < 3 then
        handle:logErr("[REDIS-TRACKER] Script execution failed or invalid result")
        return false, 0, "SCRIPT_EXECUTION_FAILED"
    end
    
    local allowed = result[1] == 1
    local current_count = tonumber(result[2]) or 0
    local status = result[3]
    
    if allowed then
        handle:logInfo(string.format(
            "[REDIS-TRACKER] Connection %s allowed to pod %s. Count: %d/%d (%s)",
            connection_id, pod_id, current_count, CONFIG.MAX_CONNECTIONS_PER_POD, status
        ))
    else
        handle:logWarn(string.format(
            "[REDIS-TRACKER] Connection %s denied to pod %s. Limit exceeded: %d/%d (%s)",
            connection_id, pod_id, current_count, CONFIG.MAX_CONNECTIONS_PER_POD, status
        ))
    end
    
    return allowed, current_count, status
end

-- Atomic connection cleanup
function cleanup_connection_atomic(handle, pod_id, connection_id)
    if not pod_id or not connection_id then
        handle:logWarn("[REDIS-TRACKER] Missing pod_id or connection_id for cleanup")
        return false
    end
    
    local pod_key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    
    local result = execute_redis_script(
        handle,
        REDIS_CLEANUP_SCRIPT,
        {pod_key},  -- KEYS
        {connection_id, CONFIG.PROXY_ID}  -- ARGV
    )
    
    if result and #result >= 3 then
        local success = result[1] == 1
        local new_count = tonumber(result[2]) or 0
        local status = result[3]
        
        handle:logInfo(string.format(
            "[REDIS-TRACKER] Connection %s cleanup for pod %s: %s (new count: %d)",
            connection_id, pod_id, status, new_count
        ))
        
        return success
    else
        handle:logErr("[REDIS-TRACKER] Connection cleanup script failed")
        return false
    end
end

-- Distributed atomic rate limiting
function check_rate_limit_atomic(handle, requests_per_minute)
    local current_minute = math.floor(os.time() / 60)
    local key = string.format(REDIS_KEYS.RATE_LIMIT_WINDOW, current_minute)
    
    local result = execute_redis_script(
        handle,
        REDIS_RATE_LIMIT_SCRIPT,
        {key},  -- KEYS
        {}      -- ARGV (none needed)
    )
    
    if not result then
        handle:logWarn("[REDIS-TRACKER] Rate limiting unavailable, allowing request (fail-open)")
        return false  -- Fail open for rate limiting
    end
    
    local current_count = tonumber(result) or 0
    local is_limited = current_count > requests_per_minute
    
    if is_limited then
        handle:logWarn(string.format(
            "[REDIS-TRACKER] Rate limit exceeded: %d requests in current minute (limit: %d)",
            current_count, requests_per_minute
        ))
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

-- Generate unique connection ID
function generate_connection_id(handle)
    local headers = handle:headers()
    local client_ip = headers:get("x-forwarded-for") or headers:get("x-real-ip") or "unknown"
    local request_id = headers:get("x-request-id") or "unknown"
    local timestamp = os.time()
    
    return string.format("%s_%s_%s_%d", CONFIG.PROXY_ID, client_ip, request_id, timestamp)
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

-- Main request handler with atomic coordination
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
    
    -- Global distributed rate limiting check first
    if check_rate_limit_atomic(request_handle, CONFIG.RATE_LIMIT_REQUESTS) then
        request_handle:logWarn("[REDIS-TRACKER] Global rate limit exceeded")
        increment_rejected_counter(request_handle)
        request_handle:respond(
            {[":status"] = "429", ["content-type"] = "text/plain"},
            "Rate limit exceeded globally"
        )
        return
    end
    
    request_handle:logInfo("[REDIS-TRACKER] Request passed rate limiting, proceeding to upstream")
end

-- Enhanced response handler with atomic connection tracking
function envoy_on_response(request_handle)
    local response_headers = request_handle:headers()
    local status = response_headers:get(":status")
    
    -- Only track WebSocket upgrade requests
    if not is_websocket_upgrade(request_handle:headers()) then
        return
    end
    
    request_handle:logInfo(string.format("[REDIS-TRACKER] Response status: %s", status or "unknown"))
    
    -- Get upstream pod information
    local pod_id = get_pod_id_from_upstream(request_handle)
    if not pod_id then
        pod_id = "backend.default.svc.cluster.local"
        request_handle:logWarn("[REDIS-TRACKER] No pod ID available, using service-level tracking")
    end
    
    if status == "101" and pod_id then  -- WebSocket upgrade successful
        -- Generate unique connection ID
        local connection_id = generate_connection_id(request_handle)
        
        -- CRITICAL: Use atomic check-and-increment to prevent race conditions
        local allowed, count, status_msg = enforce_pod_connection_limit_atomic(
            request_handle, pod_id, connection_id
        )
        
        if allowed then
            request_handle:logInfo(string.format(
                "[REDIS-TRACKER] WebSocket established to pod %s: %d/%d connections (%s)",
                pod_id, count, CONFIG.MAX_CONNECTIONS_PER_POD, status_msg
            ))
            
            -- Store connection info for cleanup
            response_headers:add("x-tracked-pod-id", pod_id)
            response_headers:add("x-tracked-connection-id", connection_id)
        else
            request_handle:logWarn(string.format(
                "[REDIS-TRACKER] Pod %s connection rejected: %d/%d (%s)",
                pod_id, count, CONFIG.MAX_CONNECTIONS_PER_POD, status_msg
            ))
            increment_rejected_counter(request_handle)
            -- Note: Connection already established at this point, tracking for monitoring
        end
    elseif status and (status:match("^4%d%d") or status:match("^5%d%d")) then
        -- Track failed connections for monitoring
        request_handle:logInfo(string.format("[REDIS-TRACKER] WebSocket upgrade failed with status %s", status))
        increment_rejected_counter(request_handle)
    end
end

-- Connection termination handler with atomic cleanup
function envoy_on_stream_done(request_handle)
    -- Check if this was a tracked WebSocket connection
    local response_headers = request_handle:headers()
    local tracked_pod_id = response_headers:get("x-tracked-pod-id")
    local tracked_connection_id = response_headers:get("x-tracked-connection-id")
    
    if tracked_pod_id and tracked_connection_id then
        request_handle:logInfo(string.format(
            "[REDIS-TRACKER] WebSocket connection %s closed - cleaning up pod %s",
            tracked_connection_id, tracked_pod_id
        ))
        cleanup_connection_atomic(request_handle, tracked_pod_id, tracked_connection_id)
    else
        request_handle:logWarn("[REDIS-TRACKER] No tracked connection info available for cleanup")
    end
end

-- Helper function to increment rejected counter
function increment_rejected_counter(handle)
    local command = string.format('INCR "%s"', REDIS_KEYS.REJECTED_CONNECTIONS)
    
    local headers = {
        [":method"] = "POST",
        [":path"] = "/redis",
        [":authority"] = "redis-http-proxy.default.svc.cluster.local:8080",
        ["content-type"] = "text/plain"
    }
    
    local response_headers, response_body = handle:httpCall(
        "redis_http_proxy_cluster",
        headers,
        command,
        1000
    )
    
    if not response_headers or response_headers[":status"] ~= "200" then
        handle:logErr("[REDIS-TRACKER] Failed to increment rejected counter")
    end
end

-- Metrics handler for multi-proxy aggregation
function handle_metrics_request(request_handle)
    -- Simple metrics for now - can be enhanced with the pipeline approach from cld-5.txt
    local headers = {
        [":method"] = "POST",
        [":path"] = "/redis",
        [":authority"] = "redis-http-proxy.default.svc.cluster.local:8080",
        ["content-type"] = "text/plain"
    }
    
    -- Get basic metrics
    local rejected_response = request_handle:httpCall(
        "redis_http_proxy_cluster",
        headers,
        string.format('GET "%s"', REDIS_KEYS.REJECTED_CONNECTIONS),
        1000
    )
    
    local rejected_count = 0
    if rejected_response and rejected_response[":status"] == "200" then
        local ok, response = pcall(cjson.decode, rejected_response.body or "{}")
        if ok and response.result then
            rejected_count = tonumber(response.result) or 0
        end
    end
    
    local metrics = string.format([[
# HELP websocket_connections_rejected_total Total rejected WebSocket connections (all proxies)
# TYPE websocket_connections_rejected_total counter
websocket_connections_rejected_total %d

# HELP websocket_proxy_instance Instance identifier
# TYPE websocket_proxy_instance gauge
websocket_proxy_instance{proxy_id="%s"} 1
]], rejected_count, CONFIG.PROXY_ID)
    
    request_handle:respond(
        {[":status"] = "200", ["content-type"] = "text/plain; charset=utf-8"},
        metrics
    )
end
