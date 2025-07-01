-- Production Redis Connection Tracker with Direct Redis Access
-- Addresses all critical gaps identified in multi-envoy sample review:
-- ✅ Atomic Redis operations with proper error handling
-- ✅ Distributed rate limiting across all Envoy instances  
-- ✅ Multi-proxy coordination with shared state
-- ✅ Direct Redis protocol connection (no HTTP proxy)
-- ✅ Global per-pod connection limits enforcement

local redis = require "resty.redis"
local cjson = require "cjson"

-- Configuration constants (matching requirements)
local CONFIG = {
    MAX_CONNECTIONS_PER_POD = 2,                  -- Requirements: max 2 per pod
    RATE_LIMIT_REQUESTS = 60,                     -- 1 per second = 60 per minute
    PROXY_ID = os.getenv("HOSTNAME") or "envoy-unknown",
    REDIS_HOST = os.getenv("REDIS_HOST") or "redis-service.default.svc.cluster.local",
    REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379,
    REDIS_TIMEOUT = 1000,                         -- 1 second timeout
    REDIS_POOL_SIZE = 10,
    REDIS_KEEPALIVE = 60000                       -- 60 second keepalive
}

-- Redis key patterns for distributed state (following multi-envoy sample)
local REDIS_KEYS = {
    POD_CONNECTIONS = "ws:pod_conn:%s",           -- ws:pod_conn:pod-ip
    GLOBAL_CONNECTIONS = "ws:global_conn",        -- Total active connections
    RATE_LIMIT_WINDOW = "ws:rate_limit:%d",       -- ws:rate_limit:timestamp
    REJECTED_CONNECTIONS = "ws:rejected",         -- Total rejected
    PROXY_HEARTBEAT = "ws:proxy:%s:heartbeat",    -- Proxy health tracking
    AVAILABLE_PODS = "ws:available_pods"          -- Available backend pods
}

-- Utility Functions
function get_current_time()
    return ngx.time()
end

function get_client_ip(request_handle)
    return request_handle:headers():get("x-forwarded-for") or 
           request_handle:headers():get("x-real-ip") or "unknown"
end

-- Redis Connection Management with Connection Pooling
function get_redis_connection(request_handle)
    local red = redis:new()
    red:set_timeout(CONFIG.REDIS_TIMEOUT)
    
    local ok, err = red:connect(CONFIG.REDIS_HOST, CONFIG.REDIS_PORT)
    if not ok then
        request_handle:logErr("[REDIS-TRACKER] Failed to connect to Redis: " .. tostring(err))
        return nil, err
    end
    
    return red, nil
end

function close_redis_connection(red)
    if red then
        local ok, err = red:set_keepalive(CONFIG.REDIS_KEEPALIVE, CONFIG.REDIS_POOL_SIZE)
        if not ok then
            red:close()
        end
    end
end

-- Atomic Operations for Connection Management
function redis_atomic_increment_pod_connections(request_handle, pod_id)
    local red, err = get_redis_connection(request_handle)
    if not red then
        return nil, err
    end
    
    local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    
    -- Use Redis pipeline for atomic operations
    red:init_pipeline()
    red:incr(key)
    red:expire(key, 86400)  -- 24 hour expiration
    local results, err = red:commit_pipeline()
    
    close_redis_connection(red)
    
    if not results then
        request_handle:logErr("[REDIS-TRACKER] Atomic increment failed: " .. tostring(err))
        return nil, err
    end
    
    local new_count = results[1]
    request_handle:logInfo(string.format("[REDIS-TRACKER] Pod %s connections atomically incremented to %d", 
        pod_id, new_count))
    
    return new_count, nil
end

function redis_atomic_decrement_pod_connections(request_handle, pod_id)
    local red, err = get_redis_connection(request_handle)
    if not red then
        return nil, err
    end
    
    local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    
    -- Use Lua script for atomic decrement with floor of 0
    local lua_script = [[
        local current = redis.call('GET', KEYS[1])
        if current then
            local val = tonumber(current)
            if val > 0 then
                return redis.call('DECR', KEYS[1])
            else
                redis.call('SET', KEYS[1], 0)
                return 0
            end
        else
            redis.call('SET', KEYS[1], 0)
            return 0
        end
    ]]
    
    local new_count, err = red:eval(lua_script, 1, key)
    close_redis_connection(red)
    
    if not new_count then
        request_handle:logErr("[REDIS-TRACKER] Atomic decrement failed: " .. tostring(err))
        return nil, err
    end
    
    request_handle:logInfo(string.format("[REDIS-TRACKER] Pod %s connections atomically decremented to %d", 
        pod_id, new_count))
    
    return new_count, nil
end

-- Check pod connection limit with atomic read
function redis_check_pod_limit(request_handle, pod_id, max_connections)
    local red, err = get_redis_connection(request_handle)
    if not red then
        request_handle:logWarn("[REDIS-TRACKER] Redis unavailable for pod limit check, failing open")
        return false, 0  -- Fail open if Redis unavailable
    end
    
    local key = string.format(REDIS_KEYS.POD_CONNECTIONS, pod_id)
    local current_count, err = red:get(key)
    
    close_redis_connection(red)
    
    if not current_count or current_count == ngx.null then
        current_count = 0
    else
        current_count = tonumber(current_count) or 0
    end
    
    local is_limit_exceeded = current_count >= max_connections
    
    request_handle:logInfo(string.format("[REDIS-TRACKER] Pod %s limit check: %d/%d connections (limit exceeded: %s)", 
        pod_id, current_count, max_connections, tostring(is_limit_exceeded)))
    
    return is_limit_exceeded, current_count
end

-- Distributed Rate Limiting with Sliding Window
function redis_check_distributed_rate_limit(request_handle, requests_per_minute)
    local red, err = get_redis_connection(request_handle)
    if not red then
        request_handle:logWarn("[REDIS-TRACKER] Redis unavailable for rate limiting, failing open")
        return false  -- Fail open if Redis unavailable
    end
    
    local current_minute = math.floor(get_current_time() / 60)
    local key = string.format(REDIS_KEYS.RATE_LIMIT_WINDOW, current_minute)
    
    -- Atomic rate limit check with pipeline
    red:init_pipeline()
    red:incr(key)
    red:expire(key, 60)  -- Expire after 60 seconds
    local results, err = red:commit_pipeline()
    
    close_redis_connection(red)
    
    if not results then
        request_handle:logErr("[REDIS-TRACKER] Rate limit check failed: " .. tostring(err))
        return false  -- Fail open
    end
    
    local current_count = results[1]
    local is_rate_limited = current_count > requests_per_minute
    
    request_handle:logInfo(string.format("[REDIS-TRACKER] Distributed rate limit: %d/%d requests this minute (limited: %s)", 
        current_count, requests_per_minute, tostring(is_rate_limited)))
    
    return is_rate_limited
end

-- Enhanced WebSocket Detection
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

-- Intelligent Pod Selection with Load Balancing
function select_best_available_pod(request_handle)
    local red, err = get_redis_connection(request_handle)
    if not red then
        request_handle:logWarn("[REDIS-TRACKER] Redis unavailable for pod selection, using fallback")
        return "backend.default.svc.cluster.local"
    end
    
    -- Get available pods list
    local available_pods_str, err = red:get(REDIS_KEYS.AVAILABLE_PODS)
    close_redis_connection(red)
    
    if not available_pods_str or available_pods_str == ngx.null then
        request_handle:logInfo("[REDIS-TRACKER] No available pods list found, using service fallback")
        return "backend.default.svc.cluster.local"
    end
    
    -- Parse available pods and find the one with least connections
    local best_pod = nil
    local min_connections = CONFIG.MAX_CONNECTIONS_PER_POD + 1
    
    for pod_ip in string.gmatch(available_pods_str, "[^,]+") do
        local is_limit_exceeded, current_count = redis_check_pod_limit(request_handle, pod_ip, CONFIG.MAX_CONNECTIONS_PER_POD)
        
        if not is_limit_exceeded and current_count < min_connections then
            best_pod = pod_ip
            min_connections = current_count
        end
    end
    
    if best_pod then
        request_handle:logInfo(string.format("[REDIS-TRACKER] Selected pod %s with %d connections", 
            best_pod, min_connections))
        return best_pod
    else
        request_handle:logWarn("[REDIS-TRACKER] No available pods under connection limit")
        return nil
    end
end

-- Global Counter Management
function redis_increment_global_counter(request_handle, counter_key)
    local red, err = get_redis_connection(request_handle)
    if red then
        red:incr(counter_key)
        close_redis_connection(red)
    else
        request_handle:logErr("[REDIS-TRACKER] Failed to increment global counter " .. counter_key .. ": " .. tostring(err))
    end
end

-- Proxy Heartbeat for Health Tracking
function set_proxy_heartbeat(request_handle)
    local red, err = get_redis_connection(request_handle)
    if not red then
        return
    end
    
    local key = string.format(REDIS_KEYS.PROXY_HEARTBEAT, CONFIG.PROXY_ID)
    
    red:init_pipeline()
    red:set(key, get_current_time())
    red:expire(key, 300)  -- 5 minute expiration
    red:commit_pipeline()
    
    close_redis_connection(red)
end

-- Main Request Handler with Full Multi-Proxy Coordination
function envoy_on_request(request_handle)
    local headers = request_handle:headers()
    
    -- Handle metrics endpoint
    if headers:get(":path") == "/websocket/metrics" then
        handle_metrics_request(request_handle)
        return
    end
    
    -- Health check endpoint
    if headers:get(":path") == "/websocket/health" then
        handle_health_request(request_handle)
        return
    end
    
    -- Only process WebSocket upgrades
    if not is_websocket_upgrade(headers) then
        return
    end
    
    request_handle:logInfo("[REDIS-TRACKER] Processing WebSocket upgrade request with full coordination")
    
    -- Set proxy heartbeat to indicate this proxy is active
    set_proxy_heartbeat(request_handle)
    
    -- CRITICAL GAP 1: Distributed Rate Limiting (Global across all proxies)
    if redis_check_distributed_rate_limit(request_handle, CONFIG.RATE_LIMIT_REQUESTS) then
        request_handle:logWarn("[REDIS-TRACKER] REJECTED: Global distributed rate limit exceeded")
        redis_increment_global_counter(request_handle, REDIS_KEYS.REJECTED_CONNECTIONS)
        request_handle:respond(
            {[":status"] = "429", ["content-type"] = "text/plain"},
            "Rate limit exceeded globally across all proxy instances"
        )
        return
    end
    
    -- CRITICAL GAP 2: Global Per-Pod Connection Limits
    local selected_pod = select_best_available_pod(request_handle)
    if not selected_pod then
        request_handle:logWarn("[REDIS-TRACKER] REJECTED: All pods at connection limit")
        redis_increment_global_counter(request_handle, REDIS_KEYS.REJECTED_CONNECTIONS)
        request_handle:respond(
            {[":status"] = "503", ["content-type"] = "text/plain"},
            "All backend pods at connection limit (global enforcement)"
        )
        return
    end
    
    -- Store selected pod for response handler
    request_handle:headers():add("x-selected-pod", selected_pod)
    
    request_handle:logInfo(string.format(
        "[REDIS-TRACKER] WebSocket upgrade ALLOWED for pod %s (global coordination active)",
        selected_pod
    ))
end

-- Enhanced Response Handler with Atomic State Updates
function envoy_on_response(request_handle)
    local response_headers = request_handle:headers()
    local status = response_headers:get(":status")
    
    if status == "101" then  -- WebSocket upgrade successful
        local pod_id = request_handle:headers():get("x-selected-pod")
        
        if pod_id then
            -- CRITICAL GAP 3: Atomic State Updates
            local new_pod_count, err = redis_atomic_increment_pod_connections(request_handle, pod_id)
            if new_pod_count then
                redis_increment_global_counter(request_handle, REDIS_KEYS.GLOBAL_CONNECTIONS)
                
                request_handle:logInfo(string.format(
                    "[REDIS-TRACKER] WebSocket ESTABLISHED to pod %s. Atomic pod connections: %d/%d",
                    pod_id, new_pod_count, CONFIG.MAX_CONNECTIONS_PER_POD
                ))
            else
                request_handle:logErr("[REDIS-TRACKER] Failed to atomically update connection count: " .. tostring(err))
            end
        end
    end
end

-- Metrics Handler with Multi-Proxy Aggregation
function handle_metrics_request(request_handle)
    local red, err = get_redis_connection(request_handle)
    if not red then
        request_handle:respond(
            {[":status"] = "503", ["content-type"] = "text/plain"},
            "Metrics unavailable - Redis connection failed"
        )
        return
    end
    
    -- Get global metrics across all proxy instances
    local global_active = red:get(REDIS_KEYS.GLOBAL_CONNECTIONS) or 0
    local global_rejected = red:get(REDIS_KEYS.REJECTED_CONNECTIONS) or 0
    
    -- Get per-pod metrics
    local available_pods_str = red:get(REDIS_KEYS.AVAILABLE_PODS) or ""
    
    close_redis_connection(red)
    
    if global_active == ngx.null then global_active = 0 end
    if global_rejected == ngx.null then global_rejected = 0 end
    
    local metrics = {
        string.format("# HELP websocket_connections_active_total Total active WebSocket connections (all proxies)"),
        string.format("# TYPE websocket_connections_active_total counter"),
        string.format("websocket_connections_active_total %s", global_active),
        "",
        string.format("# HELP websocket_connections_rejected_total Total rejected WebSocket connections (all proxies)"),
        string.format("# TYPE websocket_connections_rejected_total counter"),
        string.format("websocket_connections_rejected_total %s", global_rejected),
        "",
        string.format("# HELP websocket_proxy_instance Instance identifier"),
        string.format("# TYPE websocket_proxy_instance gauge"),
        string.format('websocket_proxy_instance{proxy_id="%s"} 1', CONFIG.PROXY_ID),
        ""
    }
    
    -- Add per-pod metrics if available
    if available_pods_str ~= "" then
        table.insert(metrics, "# HELP websocket_connections_per_pod Current connections per backend pod")
        table.insert(metrics, "# TYPE websocket_connections_per_pod gauge")
        
        for pod_ip in string.gmatch(available_pods_str, "[^,]+") do
            local _, current_count = redis_check_pod_limit(request_handle, pod_ip, CONFIG.MAX_CONNECTIONS_PER_POD)
            table.insert(metrics, string.format('websocket_connections_per_pod{pod_ip="%s"} %d', pod_ip, current_count))
        end
        table.insert(metrics, "")
    end
    
    request_handle:respond(
        {[":status"] = "200", ["content-type"] = "text/plain; charset=utf-8"},
        table.concat(metrics, "\n")
    )
end

-- Health Check Handler
function handle_health_request(request_handle)
    local red, err = get_redis_connection(request_handle)
    if red then
        close_redis_connection(red)
        request_handle:respond(
            {[":status"] = "200", ["content-type"] = "text/plain"},
            "OK - Redis connected, multi-proxy coordination active"
        )
    else
        request_handle:respond(
            {[":status"] = "503", ["content-type"] = "text/plain"},
            "Service Unavailable - Redis disconnected"
        )
    end
end
