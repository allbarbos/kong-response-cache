local cjson = require "cjson.safe"
local redis = require "resty.redis"

local ngx          = ngx
local type         = type
local setmetatable = setmetatable
local kong_err     = kong.log.err

local _M = {}

--- Create new redis strategy object
function _M.new(opts)
  local self = {
    opts = opts,
  }

  return setmetatable(self, {
    __index = _M,
  })
end

local function is_present(str)
  return str and str ~= "" and str ~= null
end

local function connect(db, host, port, timeout, password)
  -- kong.log.inspect("connect", db, host, port, timeout, password)
  local red, err_redis = redis:new()
  if err_redis then
    kong_err("error connecting to Redis: ", err_redis);
    return nil, err_redis
  end

  local redis_opts = {}
  redis_opts.pool = db and host .. ":" .. port .. ":" .. db

  red:set_timeout(timeout)
  local ok, err = red:connect(host, port, redis_opts)
  if not ok then
    kong_err("failed to connect to Redis: ", err)
    return nil, err
  end

  local times, err2 = red:get_reused_times()
  if err2 then
    kong_err("failed to get connect reused times: ", err2)
    return nil, err
  end

  if times == 0 then
    if is_present(password) then
      local ok3, err3 = red:auth(password)
      if not ok3 then
        kong_err("failed to auth Redis: ", err3)
        return nil, err
      end
    end

    if db ~= 0 then
      -- Only call select first time, since we know the connection is shared
      -- between instances that use the same redis database
      local ok4, err4 = red:select(db)
      if not ok4 then
        kong_err("failed to change Redis database: ", err4)
        return nil, err
      end
    end
  end
  return red
end


--- Store a new request entity in the redis
-- @string key The request key
-- @table req_obj The request object, represented as a table containing
--   everything that needs to be cached
-- @int[opt] ttl The TTL for the request; if nil, use default TTL specified
--   at strategy instantiation time
function _M:store(key, req_obj, req_ttl)
  local red, err_redis = connect(
    self.opts.database,
    self.opts.host,
    self.opts.port,
    self.opts.timeout,
    self.opts.password
  )

  if not red then
    kong_err("failed to get the Redis connection: ", err_redis)
    return nil, "there is no Redis connection established"
  end

  local ttl = req_ttl or self.opts.ttl

  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  kong.log.inspect("req_obj", req_obj)

  -- encode request table representation as JSON
  local req_json = cjson.encode(req_obj)
  if not req_json then
    return nil, "could not encode request object"
  end

  -- Hago efectivo el guardado
  -- inicio la transacción
  red:init_pipeline()
  -- guardo
  red:set(key, req_json)
  -- TTL
  red:expire(key, ttl)

  -- ejecuto la transacción
  local _, err = red:commit_pipeline()
  if err then
    kong_err("failed to commit the cache value to Redis: ", err)
    return nil, err
  end

  -- keepalive de la conexión: max_timeout, connection pool
  local ok, err2 = red:set_keepalive(10000, 100)
  if not ok then
    kong_err("failed to set Redis keepalive: ", err2)
    return nil, err2
  end

  return true and req_json or nil, err
end


--- Fetch a cached request
-- @string key The request key
-- @return Table representing the request
function _M:fetch(key)
  local red, err_redis = connect(
    self.opts.database,
    self.opts.host,
    self.opts.port,
    self.opts.timeout,
    self.opts.password
  )

  -- Compruebo si he conectado a Redis bien
  if not red then
    kong_err("failed to get the Redis connection: ", err_redis)
    return nil, "there is no Redis connection established"
  end

  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  -- retrieve object from shared dict
  local req_json, err = red:get(key)
  if req_json == ngx.null then
    if not err then
      -- devuelvo nulo pero diciendo que no está en la caché, no que haya habido error realmente
      -- habrá que guardar la respuesta entonces
      return nil, "request object not in cache"
    else
      return nil, err
    end
  end

  local ok, err2 = red:set_keepalive(10000, 100)
  if not ok then
    kong_err("failed to set Redis keepalive: ", err2)
    return nil, err2
  end

  -- decode object from JSON to table
  local req_obj = cjson.decode(req_json)
  if not req_obj then
      return nil, "could not decode request object"
  end

  return req_obj
end


--- Purge an entry from the request cache
-- @return true on success, nil plus error message otherwise
function _M:purge(key)
  local red, err_redis = connect(
    self.opts.database,
    self.opts.host,
    self.opts.port,
    self.opts.timeout,
    self.opts.password
  )

  -- Compruebo si he conectado a Redis bien
  if not red then
    kong_err("failed to get the Redis connection: ", err_redis)
    return nil, "there is no Redis connection established"
  end

  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  -- borro entrada de redis
  local deleted, err = red:del(key)
  if err then
    kong_err("failed to delete the key from Redis: ", err)
    return nil, err
  end

  local ok, err2 = red:set_keepalive(10000, 100)
  if not ok then
    kong_err("failed to set Redis keepalive: ", err2)
    return nil, err2
  end

  return true
end


function _M:flush(free_mem)
  local red, err_redis = connect(
    self.opts.database,
    self.opts.host,
    self.opts.port,
    self.opts.timeout,
    self.opts.password
  )

  -- Compruebo si he conectado a Redis bien
  if not red then
    kong_err("failed to get the Redis connection: ", err_redis)
    return nil, "there is no Redis connection established"
  end

  -- aquí borro toda la cache de redis de forma asíncrona
  local flushed, err = red:flushdb("async")
  if err then
    kong_err("failed to flush the database from Redis: ", err)
    return nil, err
  end

  local ok, err2 = red:set_keepalive(10000, 100)
  if not ok then
    kong_err("failed to set Redis keepalive: ", err2)
    return nil, err2
  end

  return true
end

return _M

--- Reset TTL for a cached request
-- function _M:touch(key, req_ttl, timestamp)
--   if type(key) ~= "string" then
--     return nil, "key must be a string"
--   end

--   -- check if entry actually exists
--   -- BUSCAR NO REDIS
--   local req_json, err = self.dict:get(key)
--   if not req_json then
--     if not err then
--       return nil, "request object not in cache"

--     else
--       return nil, err
--     end
--   end

--   -- decode object from JSON to table
--   local req_obj = cjson.decode(req_json)
--   if not req_obj then
--     return nil, "could not decode request object"
--   end

--   -- refresh timestamp field
--   req_obj.timestamp = timestamp or time()

--   -- store it again to reset the TTL
--   return _M:store(key, req_obj, req_ttl)
-- end


--- Marks all entries as expired and remove them from the memory
-- @param free_mem Boolean indicating whether to free the memory; if false,
--   entries will only be marked as expired
-- @return true on success, nil plus error message otherwise
