local header = require "kong.plugins.response-cache.http.header"

local function res_cc()
  return header.parse_directive(ngx.var.sent_http_cache_control)
end

local function cacheable_response(conf, cc)
  -- TODO refactor these searches to O(1)
  do
    local status = kong.response.get_status()
    local status_match = false
    for i = 1, #conf.response_code do
      if conf.response_code[i] == status then
        status_match = true
        break
      end
    end

    if not status_match then
      return false
    end
  end

  do
    local content_type = ngx.var.sent_http_content_type

    -- bail if we cannot examine this content type
    if not content_type or type(content_type) == "table" or
       content_type == "" then

      return false
    end

    local content_match = false
    for i = 1, #conf.content_type do

      if conf.content_type[i] == content_type then
        content_match = true
        break
      end
    end

    if not content_match then
      return false
    end
  end

  return true
end

return {
  res_cc = res_cc,
  is_cacheable = cacheable_response,
}
