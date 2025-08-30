-- Simple test Lua script for Envoy
function envoy_on_request(request_handle)
  request_handle:logInfo("LUA WORKING: Request received")
  local path = request_handle:headers():get(":path") or "unknown"
  request_handle:logInfo("LUA WORKING: Path = " .. path)
end

function envoy_on_response(response_handle)
  response_handle:logInfo("LUA WORKING: Response sent")
end
