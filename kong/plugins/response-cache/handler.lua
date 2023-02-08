local plugin = {
  PRIORITY = 100,
  VERSION = "1.0.0",
}

local ngx              = ngx
local kong             = kong
local concat           = table.concat
local lower            = string.lower
local floor            = math.floor
local time             = ngx.time
local ngx_re_gmatch    = ngx.re.gmatch
local ngx_re_match     = ngx.re.match
local ngx_re_sub       = ngx.re.gsub
local resp_get_headers = ngx.resp and ngx.resp.get_headers

local cache = require "kong.plugins.response-cache.cache_key"
local tab_new = require("table.new")

local CACHE_VERSION = 1
local EMPTY = {}
local STRATEGY_PATH = "kong.plugins.response-cache.strategies"

-- http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5.1
-- note content-length is not strictly hop-by-hop but we will be
-- adjusting it here anyhow
local hop_by_hop_headers = {
  ["connection"]          = true,
  ["keep-alive"]          = true,
  ["proxy-authenticate"]  = true,
  ["proxy-authorization"] = true,
  ["te"]                  = true,
  ["trailers"]            = true,
  ["transfer-encoding"]   = true,
  ["upgrade"]             = true,
  ["content-length"]      = true,
}

local function parse_directive_header(h)
  if not h then
    return EMPTY
  end

  if type(h) == "table" then
    h = concat(h, ", ")
  end

  local t    = {}
  local res  = tab_new(3, 0)
  local iter = ngx_re_gmatch(h, "([^,]+)", "oj")

  local m = iter()
  while m do
    local _, err = ngx_re_match(m[0], [[^\s*([^=]+)(?:=(.+))?]],
                                "oj", nil, res)
    if err then
      kong.log.err(err)
    end

    -- store the directive token as a numeric value if it looks like a number;
    -- otherwise, store the string value. for directives without token, we just
    -- set the key to true
    t[lower(res[1])] = tonumber(res[2]) or res[2] or true

    m = iter()
  end

  return t
end

local function req_cc()
  return parse_directive_header(ngx.var.http_cache_control)
end

local function res_cc()
  return parse_directive_header(ngx.var.sent_http_cache_control)
end

local function cacheable_request(conf, cc)
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

  -- check for explicit disallow directives
  -- TODO note that no-cache isnt quite accurate here
  if conf.cache_control and (cc["no-store"] or cc["no-cache"] or
     ngx.var.authorization) then
    return false
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

local function overwritable_header(header)
  local n_header = lower(header)

  return not hop_by_hop_headers[n_header]
     and not ngx_re_match(n_header, "ratelimit-remaining")
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


function plugin:access(conf)
  local cc = req_cc()

  if not cacheable_request(conf, cc) then
    kong.response.set_header("X-Cache-Status", "Bypass")
    return
  end

  local cache_key, err

  if conf.data_mapper then
    for _, mapper in pairs(conf.data_mapper) do
      if mapper.source == "path" then
        cache_key = ngx.ctx.router_matches.uri_captures[mapper.param]
      end
    end
  else
    local consumer = kong.client.get_consumer()
    local route = kong.router.get_route()
    local uri = ngx_re_sub(ngx.var.request, "\\?.*", "", "oj")
    cache_key, err = cache.build_cache_key(consumer and consumer.id,
                                                route    and route.id,
                                                kong.request.get_method(),
                                                uri,
                                                kong.request.get_query(),
                                                kong.request.get_headers(),
                                                conf)
  end

  if err then
    kong.log.err(err)
    return
  end

  kong.response.set_header("X-Cache-Key", cache_key)

  -- try to fetch the cached object from the computed cache key
  local strategy = require(STRATEGY_PATH)({
    strategy_name = conf.strategy,
    strategy_opts = conf[conf.strategy],
  })

  local ctx = kong.ctx.plugin
  local res, err = strategy:fetch(cache_key)
  if err == "request object not in cache" then -- TODO make this a utils enum err
    ctx.req_body = kong.request.get_raw_body()

    -- this request is cacheable but wasn't found in the data store
    -- make a note that we should store it in cache later,
    -- and pass the request upstream
    return signal_cache_req(ctx, cache_key)
  elseif err then
    kong.log.err(err)
    return
  end

  if res.version ~= CACHE_VERSION then
    kong.log.notice("cache format mismatch, purging ", cache_key)
    strategy:purge(cache_key)
    return signal_cache_req(ctx, cache_key, "Bypass")
  end

  local response_data = {
    res = res,
    req = {
      body = res.req_body,
    },
    server_addr = ngx.var.server_addr,
  }

  kong.ctx.shared.response_cache_hit = response_data

  local nctx = ngx.ctx
  nctx.KONG_PROXIED = true

  for k in pairs(res.headers) do
    if not overwritable_header(k) then
      res.headers[k] = nil
    end
  end

  res.headers["Age"] = floor(time() - res.timestamp)
  res.headers["X-Cache-Status"] = "Hit"

  return kong.response.exit(res.status, res.body, res.headers)
end

function plugin:header_filter(conf)
  local ctx = kong.ctx.plugin
  local response_cache = ctx.response_cache
  -- don't look at our headers if
  -- a) the request wasn't cacheable, or
  -- b) the request was served from cache
  if not response_cache then
    return
  end

  local cc = res_cc()

  -- if this is a cacheable request, gather the headers and mark it so
  if cacheable_response(conf, cc) then
    response_cache.res_headers = resp_get_headers(0, true)
  else
    kong.response.set_header("X-Cache-Status", "Bypass")
    ctx.response_cache = nil
  end

end

local function store_cache_value(premature, strategy, req_body, status, response_cache)
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

  -- local ttl = conf.storage_ttl or conf.cache_control and response_cache.res_ttl or conf.cache_ttl

  -- Almaceno la respuesta y sus datos en caché
  local ok, err = strategy:store(response_cache.cache_key, res)
  if not ok then
      kong.log.err(err)
  end
end

function plugin:body_filter(conf)
  local ctx = kong.ctx.plugin
  local response_cache = ctx.response_cache
  if not response_cache then
    return
  end

  local body = kong.response.get_raw_body()
  if body then
    local strategy = require(STRATEGY_PATH)({
      strategy_name = conf.strategy,
      strategy_opts = conf[conf.strategy],
    })

    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]

    response_cache.res_body = (response_cache.res_body or "") .. (chunk or "")

    if eof then
        -- Retardo el guardado ya que en body_filter no puedo hacer conexiones cosocket que son las necesarias para conectar a redis
        ngx.timer.at(0, store_cache_value, strategy, ctx.req_body, kong.response.get_status(), response_cache)
    end
  end
end

return plugin
