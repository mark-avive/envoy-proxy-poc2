-- Redis Connection Tracking for Envoy WebSocket Proxy
-- Uses Envoy's native Redis proxy for optimal performance

local max_connections_per_pod = 2
local rate_limit_per_second = 1
local redis_cluster = "redis_cluster"  -- Use Envoy's Redis proxy cluster

-- Rate limiting state (per Envoy instance)
local rate_limit_tokens = nil
local last_refill_time = 0

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
  -- Note: This will only work within request/response context when request_handle is available
  -- For global logging, this function would need to be called with a handle
end

function log_error(message)
  -- Note: This will only work within request/response context when request_handle is available
  -- For global logging, this function would need to be called with a handle
end

-- Redis Communication through HTTP proxy
function redis_call(request_handle, command, ...)
  if not request_handle then
    return nil
  end
  
  local args = {...}
  local redis_command = command
  for _, arg in ipairs(args) do
    redis_command = redis_command .. " " .. tostring(arg)
  end
  
  -- Use request_handle:httpCall to communicate with Redis via HTTP
  local headers, body = request_handle:httpCall(
    "redis_http_bridge_cluster",
    {
      [":method"] = "POST",
      [":path"] = "/redis-cmd",
      [":authority"] = "redis-http-bridge-service",
      ["content-type"] = "application/x-redis-command"
    },
    redis_command,
    5000  -- 5 second timeout
  )
  
  if headers and headers[":status"] == "200" then
    return body
  else
    request_handle:logError("REDIS-TRACKER: Redis command failed: " .. command .. " - " .. (headers and headers[":status"] or "no response"))
    return nil
  end
end

-- Rate Limiting Functions
function check_rate_limit()
  local current_time = get_current_time()
  
  -- Initialize if needed
  if rate_limit_tokens == nil then
    rate_limit_tokens = rate_limit_per_second
    last_refill_time = current_time
  end
  
  local time_passed = current_time - last_refill_time
  
  -- Refill tokens
  if time_passed > 0 then
    rate_limit_tokens = math.min(rate_limit_per_second, rate_limit_tokens + time_passed * rate_limit_per_second)
    last_refill_time = current_time
  end
  
  if rate_limit_tokens >= 1 then
    rate_limit_tokens = rate_limit_tokens - 1
    return true
  end
  
  return false
end

-- Connection Tracking Functions
function get_pod_connection_count(request_handle, pod_ip)
  local response = redis_call(request_handle, "SCARD", "active_connections:" .. pod_ip)
  return tonumber(response) or 0
end

function increment_pod_connection_count(request_handle, pod_ip)
  local response = redis_call(request_handle, "INCR", "conn:" .. pod_ip)
  local count = tonumber(response) or 0
  
  -- Set expiration
  redis_call(request_handle, "EXPIRE", "conn:" .. pod_ip, 3600)
  
  return count
end

function decrement_pod_connection_count(request_handle, pod_ip)
  redis_call(request_handle, "DECR", "conn:" .. pod_ip)
end

function track_established_connection(request_handle, pod_ip, connection_id, client_ip, user_agent)
  local current_time = get_current_time()
  
  -- Add to active connections set
  redis_call(request_handle, "SADD", "active_connections:" .. pod_ip, connection_id)
  redis_call(request_handle, "EXPIRE", "active_connections:" .. pod_ip, 3600)
  
  -- Store connection details using HMSET
  redis_call(request_handle, "HMSET", "connection:" .. connection_id,
    "pod_ip", pod_ip,
    "client_ip", client_ip,
    "established_time", current_time,
    "last_activity", current_time,
    "user_agent", user_agent or "unknown")
  redis_call(request_handle, "EXPIRE", "connection:" .. connection_id, 3600)
  
  -- Update pod connection count
  local count = get_pod_connection_count(request_handle, pod_ip)
  redis_call(request_handle, "SET", "pod:established_count:" .. pod_ip, count)
  redis_call(request_handle, "EXPIRE", "pod:established_count:" .. pod_ip, 3600)
  
  -- Update scaling data
  update_pod_scaling_metrics(request_handle, pod_ip, count)
  
  request_handle:logInfo(string.format("REDIS-TRACKER: Connection established: %s to pod %s (total: %d)", connection_id, pod_ip, count))
end

function track_connection_end(request_handle, pod_ip, connection_id)
  -- Remove from active set
  redis_call(request_handle, "SREM", "active_connections:" .. pod_ip, connection_id)
  
  -- Clean up connection details
  redis_call(request_handle, "DEL", "connection:" .. connection_id)
  
  -- Update count
  local count = get_pod_connection_count(request_handle, pod_ip)
  redis_call(request_handle, "SET", "pod:established_count:" .. pod_ip, count)
  
  -- Update scaling data
  update_pod_scaling_metrics(request_handle, pod_ip, count)
  
  request_handle:logInfo(string.format("REDIS-TRACKER: Connection ended: %s from pod %s (remaining: %d)", connection_id, pod_ip, count))
end

function update_pod_scaling_metrics(request_handle, pod_ip, active_connections)
  local current_time = get_current_time()
  
  -- Calculate priority (lower connections = higher priority for scale down)
  local priority_score = 10 - active_connections
  
  -- Update scaling data using HMSET
  redis_call(request_handle, "HMSET", "pod:scaling_data:" .. pod_ip,
    "active_connections", active_connections,
    "last_updated", current_time,
    "scaling_priority", priority_score)
  redis_call(request_handle, "EXPIRE", "pod:scaling_data:" .. pod_ip, 3600)
  
  -- Add to scaling candidates (sorted set)
  redis_call(request_handle, "ZADD", "scaling:candidates:scale_down", priority_score, pod_ip)
  redis_call(request_handle, "EXPIRE", "scaling:candidates:scale_down", 300)
  
  -- Set readiness flags
  set_redis_readiness_status(request_handle)
end

function set_redis_readiness_status(request_handle)
  -- Set basic connectivity
  redis_call(request_handle, "SET", "redis:status:connected", "true")
  redis_call(request_handle, "EXPIRE", "redis:status:connected", 300)
  
  -- Set scaling readiness
  redis_call(request_handle, "SET", "redis:status:ready_for_scaling", "true")
  redis_call(request_handle, "EXPIRE", "redis:status:ready_for_scaling", 300)
end

function record_rate_limit_rejection(request_handle, pod_ip, client_ip)
  local current_time = get_current_time()
  
  -- Track in time windows using sorted sets
  local bucket_5m = math.floor(current_time / 300) * 300
  local bucket_15m = math.floor(current_time / 900) * 900
  local bucket_1h = math.floor(current_time / 3600) * 3600
  
  redis_call(request_handle, "ZINCRBY", "rate_limit_rejections:5m:" .. pod_ip, 1, bucket_5m)
  redis_call(request_handle, "ZINCRBY", "rate_limit_rejections:15m:" .. pod_ip, 1, bucket_15m)
  redis_call(request_handle, "ZINCRBY", "rate_limit_rejections:1h:" .. pod_ip, 1, bucket_1h)
  
  -- Set expiration for time buckets
  redis_call(request_handle, "EXPIRE", "rate_limit_rejections:5m:" .. pod_ip, 300)
  redis_call(request_handle, "EXPIRE", "rate_limit_rejections:15m:" .. pod_ip, 900)
  redis_call(request_handle, "EXPIRE", "rate_limit_rejections:1h:" .. pod_ip, 3600)
  
  request_handle:logInfo(string.format("REDIS-TRACKER: Rate limit rejection recorded for pod %s from client %s", pod_ip, client_ip))
end

function record_max_limit_rejection(request_handle, pod_ip, client_ip, current_connections)
  local current_time = get_current_time()
  
  -- Track in time windows using sorted sets
  local bucket_5m = math.floor(current_time / 300) * 300
  local bucket_15m = math.floor(current_time / 900) * 900
  local bucket_1h = math.floor(current_time / 3600) * 3600
  
  redis_call(request_handle, "ZINCRBY", "max_limit_rejections:5m:" .. pod_ip, 1, bucket_5m)
  redis_call(request_handle, "ZINCRBY", "max_limit_rejections:15m:" .. pod_ip, 1, bucket_15m)
  redis_call(request_handle, "ZINCRBY", "max_limit_rejections:1h:" .. pod_ip, 1, bucket_1h)
  
  -- Set expiration for time buckets
  redis_call(request_handle, "EXPIRE", "max_limit_rejections:5m:" .. pod_ip, 300)
  redis_call(request_handle, "EXPIRE", "max_limit_rejections:15m:" .. pod_ip, 900)
  redis_call(request_handle, "EXPIRE", "max_limit_rejections:1h:" .. pod_ip, 3600)
  
  -- Store context using HMSET
  redis_call(request_handle, "HMSET", "pod:max_limit_stats:" .. pod_ip,
    "last_rejection", current_time,
    "connections_at_rejection", current_connections or 0)
  
  request_handle:logInfo(string.format("REDIS-TRACKER: Max limit rejection recorded for pod %s from client %s (connections: %d)", 
    pod_ip, client_ip, current_connections or 0))
end

-- Main Envoy Filter Functions
function envoy_on_request(request_handle)
  -- Log every request to see if the script is being triggered
  request_handle:logInfo("REDIS-TRACKER: Request received")
  
  -- Get request details
  local method = request_handle:headers():get(":method") or "unknown"
  local path = request_handle:headers():get(":path") or "/"
  local upgrade_header = request_handle:headers():get("upgrade")
  local client_ip = get_client_ip(request_handle)
  
  request_handle:logInfo(string.format("REDIS-TRACKER: Request details: method=%s, path=%s, upgrade=%s, client=%s", 
    method, path, upgrade_header or "none", client_ip))
  
  -- Get current pod info
  local pod_ip = os.getenv("POD_IP") or "unknown-pod"
  local hostname = os.getenv("HOSTNAME") or "envoy-unknown"
  
  -- Generate connection ID for this request
  local current_time = get_current_time()
  local connection_id = generate_connection_id()
  
  -- Check if this is a WebSocket upgrade request
  if upgrade_header and string.lower(upgrade_header) == "websocket" then
    request_handle:logInfo("REDIS-TRACKER: WebSocket connection detected")
    
    -- DON'T track connection here - wait for response phase to get backend pod IP
    -- Just log the attempt for monitoring
    local success, result = pcall(function()
      redis_call(request_handle, "INCR", "ws:attempts")
      redis_call(request_handle, "EXPIRE", "ws:attempts", 7200)
      return "WebSocket attempt logged"
    end)
    
    if success then
      request_handle:logInfo("REDIS-TRACKER: WebSocket attempt logged")
    else
      request_handle:logError("REDIS-TRACKER: Failed to log WebSocket attempt: " .. tostring(result))
    end
  else
    -- Track regular HTTP requests for rate limiting
    local success, result = pcall(function()
      -- Rate limiting tracking by minute
      local minute_bucket = math.floor(current_time / 60)
      redis_call(request_handle, "INCR", "ws:rate_limit:" .. minute_bucket)
      redis_call(request_handle, "EXPIRE", "ws:rate_limit:" .. minute_bucket, 300) -- 5 minutes
      
      return "HTTP request tracked"
    end)
    
    if success then
      request_handle:logInfo("REDIS-TRACKER: HTTP request metrics posted successfully")
    else
      request_handle:logError("REDIS-TRACKER: Failed to post HTTP metrics: " .. tostring(result))
    end
  end
  
  -- Post test connectivity metric (keep for monitoring)
  local success, result = pcall(function()
    return redis_call(request_handle, "SET", "lua_test_key", "lua_working_" .. current_time)
  end)
  
  if success then
    request_handle:logInfo("REDIS-TRACKER: Test connectivity confirmed")
  else
    request_handle:logError("REDIS-TRACKER: Test connectivity failed: " .. tostring(result))
  end
  
  -- Store the connection_id in request headers for cleanup in response
  request_handle:headers():add("x-connection-id", connection_id)
  
  -- Continue with normal processing
end

function envoy_on_response(response_handle)
  -- Log every response to see if this is being triggered
  local status = response_handle:headers():get(":status") or "unknown"
  response_handle:logInfo(string.format("REDIS-TRACKER: Response processed: status=%s", status))
  
  -- Get upstream host from response headers (the actual backend pod IP)
  local upstream_host = response_handle:headers():get("x-upstream-host")
  local backend_pod_ip = "unknown-backend"
  
  if upstream_host then
    -- Extract IP from "IP:PORT" format (e.g., "172.245.10.137:8080" -> "172.245.10.137")
    backend_pod_ip = string.match(upstream_host, "([^:]+):?%d*") or upstream_host
    response_handle:logInfo(string.format("REDIS-TRACKER: Backend pod IP extracted: %s from upstream: %s", 
      backend_pod_ip, upstream_host))
  else
    response_handle:logInfo("REDIS-TRACKER: No upstream host header found")
  end
  
  -- Handle WebSocket connection tracking with correct backend pod IP
  if status == "101" then -- WebSocket upgrade successful
    local connection_id = response_handle:headers():get("x-connection-id")
    if connection_id and backend_pod_ip ~= "unknown-backend" then
      local client_ip = get_client_ip(response_handle)
      local current_time = get_current_time()
      
      local success, result = pcall(function()
        -- Track WebSocket connection with BACKEND pod IP (not Envoy pod IP)
        redis_call(response_handle, "INCR", "ws:backend_pod_conn:" .. backend_pod_ip)
        redis_call(response_handle, "EXPIRE", "ws:backend_pod_conn:" .. backend_pod_ip, 7200)
        
        -- Add to backend pod active connections
        redis_call(response_handle, "SADD", "ws:backend_active_pods", backend_pod_ip)
        redis_call(response_handle, "EXPIRE", "ws:backend_active_pods", 7200)
        
        -- Store connection metadata with backend pod IP
        redis_call(response_handle, "HMSET", "ws:backend_conn:" .. connection_id,
          "backend_pod_ip", backend_pod_ip,
          "client_ip", client_ip,
          "established_time", current_time,
          "upstream_host", upstream_host)
        redis_call(response_handle, "EXPIRE", "ws:backend_conn:" .. connection_id, 7200)
        
        return "Backend connection tracked"
      end)
      
      if success then
        response_handle:logInfo(string.format("REDIS-TRACKER: WebSocket connection tracked to backend pod: %s", 
          backend_pod_ip))
      else
        response_handle:logInfo("REDIS-TRACKER: Failed to track backend connection: " .. tostring(result))
      end
    end
  end
  
  -- Handle connection cleanup for failed WebSocket upgrades
  if status ~= "101" then
    local connection_id = response_handle:headers():get("x-connection-id")
    if connection_id then
      local pod_ip = os.getenv("POD_IP") or "unknown-pod"
      local hostname = os.getenv("HOSTNAME") or "envoy-unknown"
      
      local success, result = pcall(function()
        -- Only clean up if this was supposed to be a WebSocket connection
        local upgrade_header = response_handle:headers():get("upgrade")
        if upgrade_header and string.lower(upgrade_header) == "websocket" then
          response_handle:logInfo("REDIS-TRACKER: WebSocket upgrade failed, cleaning up")
          
          -- Decrement pod connection count
          redis_call(response_handle, "DECR", "ws:pod_conn:" .. pod_ip)
          
          -- Remove from global connections registry
          redis_call(response_handle, "SREM", "ws:all_connections", connection_id)
          
          -- Remove connection metadata
          redis_call(response_handle, "DEL", "ws:conn:" .. connection_id)
          
          -- Decrement proxy metrics
          redis_call(response_handle, "DECR", "ws:proxy:" .. hostname .. ":connections")
          
          -- Increment rejected count
          redis_call(response_handle, "INCR", "ws:rejected")
          redis_call(response_handle, "EXPIRE", "ws:rejected", 7200)
        end
        
        return "Cleanup completed"
      end)
      
      if success then
        response_handle:logInfo("REDIS-TRACKER: Connection cleanup completed")
      else
        response_handle:logError("REDIS-TRACKER: Connection cleanup failed: " .. tostring(result))
      end
    end
  end
end
