-- ==============================================================================
--                    SIMPLIFIED ATOMIC CONNECTION TRACKER
-- ==============================================================================
-- Streamlined implementation for direct Redis connectivity via HTTP calls
-- Focus on atomic operations and reliability

local cjson = require("cjson.safe")

-- Configuration
local CONFIG = {
  max_connections_per_pod = 2,
  rate_limit_per_minute = 60,
  proxy_id = os.getenv("HOSTNAME") or "envoy-unknown",
  redis_host = "redis-atomic-service",
  redis_port = 6379,
  redis_timeout = 5000
}

-- Redis Lua script for atomic connection enforcement (from docs2/cld-2.txt)
local ATOMIC_CONNECTION_SCRIPT = [[
    local pod_key = KEYS[1]
    local max_connections = tonumber(ARGV[1])
    local connection_id = ARGV[2]
    local proxy_id = ARGV[3]
    local current_time = ARGV[4]
    
    local current_count = redis.call('GET', pod_key)
    current_count = tonumber(current_count) or 0
    
    if current_count >= max_connections then
        return {0, current_count, "LIMIT_EXCEEDED"}
    end
    
    local new_count = redis.call('INCR', pod_key)
    
    local conn_detail_key = 'ws:conn:' .. connection_id
    local conn_data = {
        'pod_id', string.match(pod_key, 'ws:pod_conn:(.+)'),
        'proxy_id', proxy_id,
        'created_at', current_time,
        'last_seen', current_time
    }
    redis.call('HMSET', conn_detail_key, unpack(conn_data))
    redis.call('EXPIRE', conn_detail_key, 7200)
    
    redis.call('SADD', 'ws:all_connections', connection_id)
    
    return {1, new_count, "SUCCESS"}
]]

-- Redis Lua script for atomic cleanup
local ATOMIC_CLEANUP_SCRIPT = [[
    local pod_key = KEYS[1]
    local connection_id = ARGV[1]
    local proxy_id = ARGV[2]
    
    local current_count = redis.call('GET', pod_key)
    current_count = tonumber(current_count) or 0
    
    if current_count > 0 then
        redis.call('DECR', pod_key)
        current_count = current_count - 1
    end
    
    local conn_detail_key = 'ws:conn:' .. connection_id
    redis.call('DEL', conn_detail_key)
    redis.call('SREM', 'ws:all_connections', connection_id)
    
    return {1, current_count, "CLEANED_UP"}
]]

-- Simple rate limiting script
local RATE_LIMIT_SCRIPT = [[
    local key = KEYS[1]
    local current = redis.call('INCR', key)
    if current == 1 then
        redis.call('EXPIRE', key, 60)
    end
    return current
]]

-- Execute Redis command via HTTP call
local function redis_call(handle, command_args)
  -- Simple Redis protocol over HTTP
  local command_str = table.concat(command_args, " ")
  
  local headers = {
    [":method"] = "POST",
    [":path"] = "/",
    [":authority"] = CONFIG.redis_host,
    ["content-type"] = "text/plain"
  }
  
  local response_headers, response_body = handle:httpCall(
    "redis_cluster",
    headers,
    command_str,
    CONFIG.redis_timeout
  )
  
  if response_headers and response_headers[":status"] == "200" then
    return response_body
  end
  
  return nil
end

-- Execute Redis Lua script
local function redis_eval(handle, script, keys, args)
  local eval_args = {"EVAL", script, tostring(#keys)}
  
  for _, key in ipairs(keys) do
    table.insert(eval_args, key)
  end
  
  for _, arg in ipairs(args) do
    table.insert(eval_args, tostring(arg))
  end
  
  local result = redis_call(handle, eval_args)
  
  if result then
    -- Parse basic Redis response (simplified)
    local ok, parsed = pcall(cjson.decode, result)
    if ok and type(parsed) == "table" then
      return parsed
    end
  end
  
  return nil
end

-- Generate unique connection ID
local function generate_connection_id(handle)
  local headers = handle:headers()
  local remote_addr = headers:get("x-forwarded-for") or headers:get("x-real-ip") or "unknown"
  local timestamp = os.time()
  local random = math.random(1000, 9999)
  
  remote_addr = string.gsub(remote_addr, "[^%w%-]", "_")
  return string.format("%s_%s_%d_%d", CONFIG.proxy_id, remote_addr, timestamp, random)
end

-- Extract pod ID from upstream
local function get_pod_id(handle)
  -- Try to get from response headers or stream info
  local headers = handle:headers()
  local pod_name = headers:get("x-pod-name")
  if pod_name then
    return pod_name
  end
  
  -- Fallback to service-level tracking
  return "backend-service"
end

-- Check if request is WebSocket upgrade
local function is_websocket_upgrade(handle)
  local headers = handle:headers()
  local connection = headers:get("connection")
  local upgrade = headers:get("upgrade")
  
  if connection and upgrade then
    return string.find(string.lower(connection), "upgrade") and 
           string.lower(upgrade) == "websocket"
  end
  
  return false
end

-- Atomic connection enforcement
local function enforce_connection_limit(handle, pod_id, connection_id)
  local pod_key = string.format("ws:pod_conn:%s", pod_id)
  local current_time = tostring(os.time())
  
  local result = redis_eval(
    handle,
    ATOMIC_CONNECTION_SCRIPT,
    {pod_key},
    {CONFIG.max_connections_per_pod, connection_id, CONFIG.proxy_id, current_time}
  )
  
  if result and type(result) == "table" and #result >= 3 then
    local allowed = result[1] == 1
    local count = tonumber(result[2]) or 0
    local status = result[3]
    
    return allowed, count, status
  end
  
  return false, 0, "SCRIPT_FAILED"
end

-- Atomic connection cleanup
local function cleanup_connection(handle, pod_id, connection_id)
  local pod_key = string.format("ws:pod_conn:%s", pod_id)
  
  local result = redis_eval(
    handle,
    ATOMIC_CLEANUP_SCRIPT,
    {pod_key},
    {connection_id, CONFIG.proxy_id}
  )
  
  if result and type(result) == "table" and #result >= 2 then
    local success = result[1] == 1
    local count = tonumber(result[2]) or 0
    
    handle:logInfo(string.format(
      "[ATOMIC-TRACKER] Cleaned up connection %s from pod %s, remaining: %d",
      connection_id, pod_id, count
    ))
    
    return success
  end
  
  return false
end

-- Rate limiting check
local function check_rate_limit(handle)
  local current_minute = math.floor(os.time() / 60)
  local rate_key = string.format("ws:rate_limit:%d", current_minute)
  
  local result = redis_eval(handle, RATE_LIMIT_SCRIPT, {rate_key}, {})
  
  if result then
    local count = tonumber(result) or 0
    return count > CONFIG.rate_limit_per_minute
  end
  
  -- Fail open for rate limiting
  return false
end

-- Request handler
function envoy_on_request(request_handle)
  local headers = request_handle:headers()
  
  -- Handle metrics endpoint
  if headers:get(":path") == "/websocket/metrics" then
    request_handle:respond(
      {[":status"] = "200", ["content-type"] = "text/plain"},
      "# Simplified metrics endpoint\nwebsocket_connections_total 0\n"
    )
    return
  end
  
  -- Only process WebSocket upgrades
  if not is_websocket_upgrade(request_handle) then
    return
  end
  
  request_handle:logInfo("[ATOMIC-TRACKER] Processing WebSocket request")
  
  -- Check rate limit
  if check_rate_limit(request_handle) then
    request_handle:logWarn("[ATOMIC-TRACKER] Rate limit exceeded")
    request_handle:respond(
      {[":status"] = "429", ["content-type"] = "text/plain"},
      "Rate limit exceeded"
    )
    return
  end
  
  -- Generate connection ID for tracking
  local connection_id = generate_connection_id(request_handle)
  headers:add("x-connection-id", connection_id)
  
  request_handle:logInfo(string.format(
    "[ATOMIC-TRACKER] WebSocket request %s proceeding", connection_id
  ))
end

-- Response handler
function envoy_on_response(response_handle)
  local headers = response_handle:headers()
  local status = headers:get(":status")
  
  -- Only track successful WebSocket upgrades
  if not is_websocket_upgrade(response_handle) or status ~= "101" then
    return
  end
  
  local connection_id = headers:get("x-connection-id")
  if not connection_id then
    response_handle:logErr("[ATOMIC-TRACKER] Missing connection ID")
    return
  end
  
  local pod_id = get_pod_id(response_handle)
  
  -- Enforce connection limit atomically
  local allowed, count, status_msg = enforce_connection_limit(
    response_handle, pod_id, connection_id
  )
  
  if allowed then
    response_handle:logInfo(string.format(
      "[ATOMIC-TRACKER] WebSocket %s allowed to pod %s (%d/%d) - %s",
      connection_id, pod_id, count, CONFIG.max_connections_per_pod, status_msg
    ))
    
    -- Store for cleanup
    headers:add("x-tracked-pod-id", pod_id)
    headers:add("x-tracked-connection-id", connection_id)
  else
    response_handle:logWarn(string.format(
      "[ATOMIC-TRACKER] WebSocket %s denied to pod %s (%d/%d) - %s",
      connection_id, pod_id, count, CONFIG.max_connections_per_pod, status_msg
    ))
    
    -- Note: At this point the connection is already established,
    -- but we're tracking the violation for monitoring
  end
end

-- Connection termination handler
function envoy_on_stream_done(request_handle)
  local headers = request_handle:headers()
  local pod_id = headers:get("x-tracked-pod-id")
  local connection_id = headers:get("x-tracked-connection-id")
  
  if pod_id and connection_id then
    cleanup_connection(request_handle, pod_id, connection_id)
  end
end
