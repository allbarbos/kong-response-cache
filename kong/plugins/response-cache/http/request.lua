local header = require "kong.plugins.response-cache.http.header"

local function req_cc()
  return header.parse_directive(ngx.var.http_cache_control)
end

local function is_cacheable(conf, cc)
  -- TODO refactor these searches to O(1)
  do
    local method = kong.request.get_method()
    local method_match = false
    for i = 1, #conf.request_method do
      if conf.request_method[i] == method then
        method_match = true
        break
      end
    end

    if not method_match then
      return false
    end
  end

  return true
end

-- indicate that we should attempt to cache the response to this request
local function signal_cache_req(ctx, cache_key, cache_status)
  ctx.response_cache = {
    cache_key = cache_key,
  }
  kong.response.set_header("X-Cache-Status", cache_status or "Miss")
end

return {
  req_cc = req_cc,
  is_cacheable = is_cacheable,
  signal_cache = signal_cache_req,
}
