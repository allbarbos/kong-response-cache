local cjson                  = require "cjson.safe"
local redis                  = require "resty.redis"

local ngx                    = ngx
local type                   = type
local setmetatable           = setmetatable
local log_err                = kong.log.err
local log_debug              = kong.log.debug

local _M                     = {}
local redis_pool_size        = 100
local redis_max_idle_timeout = 10000

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
  return str and str ~= "" and str ~= nil
end

local function connect(db, host, port, timeout, password)
  local red, err_redis = redis:new()
  if err_redis then
    log_err("Error to creates a redis object: ", err_redis);
    return nil, err_redis
  end

  local redis_opts = {}
  redis_opts.pool = db and host .. ":" .. port .. ":" .. db

  red:set_timeout(timeout)
  local ok, err = red:connect(host, port, redis_opts)
  if not ok then
    log_err("Failed to connect to Redis: ", err)
    return nil, err
  end

  local times, err2 = red:get_reused_times()
  if err2 then
    log_err("Failed to get connect reused times: ", err2)
    return nil, err
  end

  if times == 0 then
    if is_present(password) then
      local ok3, err3 = red:auth(password)
      if not ok3 then
        log_err("Failed to auth Redis: ", err3)
        return nil, err
      end
    end

    if db ~= 0 then
      local ok4, err4 = red:select(db)
      if not ok4 then
        log_err("Failed to change Redis database: ", err4)
        return nil, err
      end
    end
  end
  return red
end

--- Puts the current Redis connection immediately into the ngx_lua cosocket connection pool
-------------------------------------
-- @param redisDb The current redis object
-- @param max_idle_timeout Max idle timeout (in ms) when the connection is in the pool
-- @param pool_size Max size of the pool every nginx worker process
-- @return Error
local function set_keepalive(redisDb, max_idle_timeout, pool_size)
  local _, err = redisDb:set_keepalive(
    max_idle_timeout or redis_max_idle_timeout,
    pool_size or redis_pool_size
  )

  if err then
    log_err("Failed to set Redis keepalive: ", err)
    return err
  end
end

--- Store a new request entity in the redis
-------------------------------------
-- @param key Cache key
-- @param req_obj The request object, represented as a table containing everything that needs to be cached
-- @param[opt] ttl The TTL for the request; if nil, use default TTL specified at strategy instantiation time
-- @return Table representing the request
function _M:store(key, req_obj, req_ttl)
  local red, err_redis = connect(
    self.opts.database,
    self.opts.host,
    self.opts.port,
    self.opts.timeout,
    self.opts.password
  )

  if not red then
    log_err("failed to get the Redis connection: ", err_redis)
    return nil, "there is no Redis connection established"
  end

  local ttl = req_ttl or self.opts.ttl
  log_debug("redis expire ttl: ", ttl)

  log_debug("redis key: ", key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  local req_json = cjson.encode(req_obj)
  if not req_json then
    return nil, "could not encode request object"
  end

  red:init_pipeline()
  red:set(key, req_json)

  if ttl > 0 then
    red:expire(key, ttl)
  end

  local _, err = red:commit_pipeline()
  if err then
    log_err("failed to commit the cache value to Redis: ", err)
    return nil, err
  end

  set_keepalive(red)

  return true and req_json
end

--- Fetch a cached request
-------------------------------------
-- @param key The request key
-- @return Table representing the request
function _M:fetch(key)
  local red, err_redis = connect(
    self.opts.database,
    self.opts.host,
    self.opts.port,
    self.opts.timeout,
    self.opts.password
  )

  if not red then
    log_err("failed to get the Redis connection: ", err_redis)
    return nil, "there is no Redis connection established"
  end

  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  local req_json, err = red:get(key)
  if req_json == ngx.null then
    if not err then
      return nil, "request object not in cache"
    else
      return nil, err
    end
  end

  set_keepalive(red)

  local req_obj = cjson.decode(req_json)
  if not req_obj then
    return nil, "could not decode request object"
  end

  return req_obj
end

--- Purge an entry from the request cache
-------------------------------------
-- @param key Cache key
-- @return true on success and error otherwise
function _M:purge(key)
  local red, err_redis = connect(
    self.opts.database,
    self.opts.host,
    self.opts.port,
    self.opts.timeout,
    self.opts.password
  )

  if not red then
    log_err("failed to get the Redis connection: ", err_redis)
    return nil, "there is no Redis connection established"
  end

  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  local _, err = red:del(key)
  if err then
    log_err("failed to delete the key from Redis: ", err)
    return nil, err
  end

  set_keepalive(red)

  return true
end

return _M
