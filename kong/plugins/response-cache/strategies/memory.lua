local cjson        = require "cjson.safe"

local ngx          = ngx
local type         = type
local shared       = ngx.shared
local setmetatable = setmetatable

local _M           = {}

--- Create new memory strategy object
-- @table opts Strategy options: contains 'dictionary_name' and 'ttl' fields
function _M.new(opts)
  local dict = shared[opts.dictionary_name]

  local self = {
    dict = dict,
    opts = opts,
  }

  return setmetatable(self, {
    __index = _M,
  })
end

--- Store a new request entity in the shared memory
-- @string key The request key
-- @table req_obj The request object, represented as a table containing
--   everything that needs to be cached
-- @int[opt] ttl The TTL for the request; if nil, use default TTL specified
--   at strategy instantiation time
function _M:store(key, req_obj, req_ttl)
  local ttl = req_ttl or self.opts.ttl

  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  local req_json = cjson.encode(req_obj)
  if not req_json then
    return nil, "could not encode request object"
  end

  local succ, err = self.dict:set(key, req_json, ttl)
  return succ and req_json or nil, err
end

--- Fetch a cached request
-- @string key The request key
-- @return Table representing the request
function _M:fetch(key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  local req_json, err = self.dict:get(key)
  if not req_json then
    if not err then
      return nil, "request object not in cache"
    else
      return nil, err
    end
  end

  local req_obj = cjson.decode(req_json)
  if not req_obj then
    return nil, "could not decode request object"
  end

  return req_obj
end

--- Purge an entry from the request cache
-- @return true on success, nil plus error message otherwise
function _M:purge(key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  self.dict:delete(key)
  return true
end

return _M
