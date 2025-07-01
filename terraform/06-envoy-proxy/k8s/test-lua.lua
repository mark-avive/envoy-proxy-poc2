-- Simple test Lua script for Envoy
function envoy_on_request(request_handle)
  if envoy and envoy.log and envoy.log_levels then
    envoy.log(envoy.log_levels.info, "[TEST-LUA] Request received: " .. (request_handle:headers():get(":path") or "/"))
  end
  
  -- Add a header to verify the script is running
  request_handle:headers():add("x-lua-test", "working")
end

function envoy_on_response(response_handle)
  if envoy and envoy.log and envoy.log_levels then
    envoy.log(envoy.log_levels.info, "[TEST-LUA] Response status: " .. (response_handle:headers():get(":status") or "unknown"))
  end
end
