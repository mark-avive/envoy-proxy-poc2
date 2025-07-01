-- Enhanced Redis Connection Tracker with Direct Redis Access
-- Following multi-envoy sample architecture for proper distributed state management

-- Redis configuration
local REDIS_CONFIG = {
    HOST = os.getenv("REDIS_HOST") or "redis-service.default.svc.cluster.local",
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

-- Get Redis connection (would require lua-redis library)
function get_redis_connection()
    -- NOTE: This requires adding lua-redis library to Envoy
    -- Alternative: Continue with HTTP proxy but make it atomic
    local redis = require("redis")
    local red = redis:new()
    red:set_timeout(REDIS_CONFIG.TIMEOUT)
    
    local ok, err = red:connect(REDIS_CONFIG.HOST, REDIS_CONFIG.PORT)
    if not ok then
        return nil, "Failed to connect to Redis: " .. tostring(err)
    end
    
    return red, nil
end

-- Atomic increment for pod connections
function redis_increment_pod_connections(handle, pod_id)
    local red, err = get_redis_connection()
    if not red then
        handle:logErr("[REDIS-TRACKER] " .. err)
        return nil, err
    end
    
    local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    local new_count, err = red:incr(key)
    
    if not new_count then
        handle:logErr("[REDIS-TRACKER] Redis incr failed: " .. tostring(err))
        red:close()
        return nil, err
    end
    
    -- Set expiration for cleanup (24 hours)
    red:expire(key, 86400)
    red:close()
    
    return new_count, nil
end

-- Check pod connection limit with atomic Redis operation
function redis_check_pod_limit(handle, pod_id, max_connections)
    local red, err = get_redis_connection()
    if not red then
        handle:logErr("[REDIS-TRACKER] Redis unavailable: " .. err)
        return false, 0  -- Fail open if Redis unavailable
    end
    
    local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    local current_count, err = red:get(key)
    
    red:close()
    
    if not current_count then
        current_count = 0
    else
        current_count = tonumber(current_count) or 0
    end
    
    return current_count >= max_connections, current_count
end

-- Distributed rate limiting with Redis
function redis_check_rate_limit(handle, requests_per_minute)
    local red, err = get_redis_connection()
    if not red then
        handle:logWarn("[REDIS-TRACKER] Redis unavailable for rate limiting, allowing request")
        return false  -- Fail open for rate limiting
    end
    
    local current_minute = math.floor(os.time() / 60)
    local key = string.format(REDIS_KEYS.RATE_LIMIT_WINDOW, current_minute)
    
    -- Use Redis pipeline for atomic operations
    red:init_pipeline()
    red:incr(key)
    red:expire(key, 60)  -- Expire after 60 seconds
    local results, err = red:commit_pipeline()
    
    red:close()
    
    if not results then
        handle:logErr("[REDIS-TRACKER] Redis rate limit check failed: " .. tostring(err))
        return false  -- Fail open
    end
    
    local current_count = results[1]
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
    
    request_handle:logInfo(string.format(
        "[REDIS-TRACKER] WebSocket upgrade allowed for pod %s (%d/%d connections)",
        pod_id, current_count, CONFIG.MAX_CONNECTIONS_PER_POD
    ))
end

-- Enhanced response handler
function envoy_on_response(request_handle)
    local response_headers = request_handle:headers()
    local status = response_headers:get(":status")
    
    if status == "101" then  -- WebSocket upgrade successful
        local pod_id = get_pod_id_from_upstream(request_handle)
        
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

-- Helper function to increment counters
function increment_counter(handle, key)
    local red, err = get_redis_connection()
    if red then
        red:incr(key)
        red:close()
    else
        handle:logErr("[REDIS-TRACKER] Failed to increment counter " .. key .. ": " .. err)
    end
end

-- Metrics handler for multi-proxy aggregation
function handle_metrics_request(request_handle)
    local red, err = get_redis_connection()
    if not red then
        request_handle:respond(
            {[":status"] = "503", ["content-type"] = "text/plain"},
            "Metrics unavailable - Redis connection failed"
        )
        return
    end
    
    local global_active = red:get(REDIS_KEYS.GLOBAL_CONNECTIONS) or 0
    local global_rejected = red:get(REDIS_KEYS.REJECTED_CONNECTIONS) or 0
    red:close()
    
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
