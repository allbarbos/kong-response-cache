local fmt = string.format
local ipairs = ipairs
local type = type
local pairs = pairs
local sort = table.sort
local insert = table.insert
local concat = table.concat
local time = ngx.time

local sha256_hex = require "kong.tools.utils".sha256_hex

local EMPTY = {}
local CACHE_VERSION = 1

local function keys(t)
  local res = {}
  for k, _ in pairs(t) do
    res[#res+1] = k
  end

  return res
end


-- Return a string with the format "key=value(:key=value)*" of the
-- actual keys and values in args that are in vary_fields.
--
-- The elements are sorted so we get consistent cache actual_keys no matter
-- the order in which params came in the request
local function generate_key_from(args, vary_fields)
  local cache_key = {}

  for _, field in ipairs(vary_fields or {}) do
    local arg = args[field]
    if arg then
      if type(arg) == "table" then
        sort(arg)
        insert(cache_key, field .. "=" .. concat(arg, ","))

      elseif arg == true then
        insert(cache_key, field)

      else
        insert(cache_key, field .. "=" .. tostring(arg))
      end
    end
  end

  return concat(cache_key, ":")
end


-- Return the component of cache_key for vary_query_params in params
--
-- If no vary_query_params are configured in the plugin, return
-- all of them.
local function params_key(params, plugin_config)
  if not (plugin_config.vary_query_params or EMPTY)[1] then
    local actual_keys = keys(params)
    sort(actual_keys)
    return generate_key_from(params, actual_keys)
  end

  return generate_key_from(params, plugin_config.vary_query_params)
end



-- Return the component of cache_key for vary_headers in params
--
-- If no vary_query_params are configured in the plugin, return
-- the empty string.
local function headers_key(headers, plugin_config)
  if not (plugin_config.vary_headers or EMPTY)[1] then
    return ""
  end

  return generate_key_from(headers, plugin_config.vary_headers)
end



local function prefix_uuid(consumer_id, route_id)
  if consumer_id and route_id then
    return fmt("%s:%s", consumer_id, route_id)
  end

  if route_id then
    return route_id
  end

  return "default"
end



local function build_cache_key(consumer_id, route_id, method, uri, params_table, headers_table, conf)
  local prefix_digest  = prefix_uuid(consumer_id, route_id)
  local params_digest  = params_key(params_table, conf)
  local headers_digest = headers_key(headers_table, conf)

  return sha256_hex(fmt("%s|%s|%s|%s|%s", prefix_digest, method, uri, params_digest, headers_digest))
end


local function store_cache_value(premature, conf, strategy, req_body, status, response_cache)
  local res = {
    status = status,
    headers = response_cache.res_headers,
    body = response_cache.res_body,
    body_len = #response_cache.res_body,
    timestamp = time(),
    ttl = response_cache.res_ttl,
    version = CACHE_VERSION,
    req_body = req_body,
  }

  local ttl = conf.storage_ttl or conf.cache_control and response_cache.res_ttl or conf.cache_ttl
  local ok, err = strategy:store(response_cache.cache_key, res, ttl)
  if not ok then
      kong.log.err(err)
  end
end

return {
  CACHE_VERSION = CACHE_VERSION,
  params_key = params_key,
  headers_key = headers_key,
  prefix_uuid = prefix_uuid,
  build_cache_key = build_cache_key,
  store_cache_value = store_cache_value,
}
