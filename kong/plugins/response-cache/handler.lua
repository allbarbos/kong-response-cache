local plugin           = {
  PRIORITY = 100,
  VERSION = "0.0.2",
}

local ngx              = ngx
local kong             = kong
local floor            = math.floor
local time             = ngx.time
local resp_get_headers = ngx.resp and ngx.resp.get_headers

local cache            = require "kong.plugins.response-cache.cache"
local header           = require "kong.plugins.response-cache.http.header"
local request          = require "kong.plugins.response-cache.http.request"
local response         = require "kong.plugins.response-cache.http.response"

local STRATEGY_PATH    = "kong.plugins.response-cache.strategies"

function plugin:access(conf)
  if not request.is_cacheable(conf) then
    kong.response.set_header("X-Cache-Status", "Bypass")
    return
  end

  local cache_key, err = cache.build_key(conf)
  if err then
    kong.log.err(err)
    return
  end

  kong.response.set_header("X-Cache-Key", cache_key)

  local strategy = require(STRATEGY_PATH)({
    strategy_name = conf.strategy,
    strategy_opts = conf[conf.strategy],
  })

  local ctx = kong.ctx.plugin
  local res, err = strategy:fetch(cache_key)
  if err == "request object not in cache" then -- TODO make this a utils enum err
    ctx.req_body = kong.request.get_raw_body()
    return request.signal_cache(ctx, cache_key)
  elseif err then
    kong.log.err(err)
    return
  end

  if res.version ~= cache.CACHE_VERSION then
    kong.log.notice("cache format mismatch, purging ", cache_key)
    strategy:purge(cache_key)
    return request.signal_cache(ctx, cache_key, "Bypass")
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
    if not header.overwritable(k) then
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
  if not response_cache then
    return
  end

  if response.is_cacheable(conf) then
    response_cache.res_headers = resp_get_headers(0, true)
  else
    kong.response.set_header("X-Cache-Status", "Bypass")
    ctx.response_cache = nil
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
      ngx.timer.at(0, cache.store_cache_value, conf, strategy, ctx.req_body, kong.response.get_status(), response_cache)
    end
  end
end

return plugin
