-- Metrics Handler Lua Script for Envoy WebSocket Proxy
-- Provides Prometheus-compatible metrics endpoint as per documentation

local redis_http_cluster = "redis_http_proxy"

-- Redis HTTP Communication
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
    return nil
  end
end

-- Generate Prometheus-format metrics
function generate_prometheus_metrics(handle)
  local metrics = {}
  
  -- Total active connections (service level)
  local service_connections = redis_http_call(handle, 'SCARD "active_connections:backend.default.svc.cluster.local"')
  if service_connections and service_connections ~= "ERROR" then
    table.insert(metrics, string.format("# HELP websocket_connections_active_total Total active WebSocket connections"))
    table.insert(metrics, string.format("# TYPE websocket_connections_active_total gauge"))
    table.insert(metrics, string.format("websocket_connections_active_total %s", service_connections))
  end
  
  -- Rate limited connections
  local rate_limited = redis_http_call(handle, 'GET "connection_attempts_rate_limited:5m:backend.default.svc.cluster.local"')
  if rate_limited and rate_limited ~= "ERROR" and rate_limited ~= "None" then
    table.insert(metrics, string.format("# HELP websocket_connection_rate_limited_total Rate limited connection attempts"))
    table.insert(metrics, string.format("# TYPE websocket_connection_rate_limited_total counter"))
    table.insert(metrics, string.format("websocket_connection_rate_limited_total %s", rate_limited))
  end
  
  -- Max connection rejections
  local max_limited = redis_http_call(handle, 'GET "connection_attempts_max_limited:5m:backend.default.svc.cluster.local"')
  if max_limited and max_limited ~= "ERROR" and max_limited ~= "None" then
    table.insert(metrics, string.format("# HELP websocket_connections_rejected_total Connections rejected due to limits"))
    table.insert(metrics, string.format("# TYPE websocket_connections_rejected_total counter"))
    table.insert(metrics, string.format("websocket_connections_rejected_total %s", max_limited))
  end
  
  -- Per-pod metrics (if available)
  local available_pods = redis_http_call(handle, 'GET "available_pods"')
  if available_pods and available_pods ~= "ERROR" and available_pods ~= "None" then
    table.insert(metrics, string.format("# HELP websocket_connections_per_pod WebSocket connections per backend pod"))
    table.insert(metrics, string.format("# TYPE websocket_connections_per_pod gauge"))
    
    for pod_ip in string.gmatch(available_pods, "[^,]+") do
      local pod_connections = redis_http_call(handle, string.format('SCARD "active_connections:%s"', pod_ip))
      if pod_connections and pod_connections ~= "ERROR" then
        table.insert(metrics, string.format('websocket_connections_per_pod{pod_ip="%s"} %s', pod_ip, pod_connections))
      end
    end
  end
  
  -- Redis connectivity status
  local redis_connected = redis_http_call(handle, 'GET "redis:status:connected"')
  table.insert(metrics, string.format("# HELP redis_connected Redis connectivity status"))
  table.insert(metrics, string.format("# TYPE redis_connected gauge"))
  if redis_connected == "true" then
    table.insert(metrics, "redis_connected 1")
  else
    table.insert(metrics, "redis_connected 0")
  end
  
  return table.concat(metrics, "\n") .. "\n"
end

-- Main handler function
function envoy_on_request(request_handle)
  local path = request_handle:headers():get(":path")
  
  if path == "/websocket/metrics" then
    local metrics = generate_prometheus_metrics(request_handle)
    request_handle:respond(
      {[":status"] = "200", ["content-type"] = "text/plain; charset=utf-8"},
      metrics
    )
    return
  elseif path == "/websocket/health" then
    -- Health check endpoint
    local redis_connected = redis_http_call(request_handle, 'GET "redis:status:connected"')
    if redis_connected == "true" then
      request_handle:respond(
        {[":status"] = "200", ["content-type"] = "text/plain"},
        "OK - Redis connected"
      )
    else
      request_handle:respond(
        {[":status"] = "503", ["content-type"] = "text/plain"},
        "Service Unavailable - Redis disconnected"
      )
    end
    return
  else
    request_handle:respond(
      {[":status"] = "404", ["content-type"] = "text/plain"},
      "Not Found"
    )
    return
  end
end
