local ngx           = ngx
local ngx_re_gmatch = ngx.re.gmatch
local ngx_re_match  = ngx.re.match
local kong          = kong
local concat        = table.concat
local lower         = string.lower

local tab_new = require("table.new")

local EMPTY = {}
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
    local _, err = ngx_re_match(m[0], [[^\s*([^=]+)(?:=(.+))?]], "oj", nil, res)
    if err then
      kong.log.err(err)
    end

    t[lower(res[1])] = tonumber(res[2]) or res[2] or true
    m = iter()
  end

  return t
end

local function overwritable_header(header)
  local n_header = lower(header)

  return not hop_by_hop_headers[n_header] and not ngx_re_match(n_header, "ratelimit-remaining")
end

return {
  parse_directive = parse_directive_header,
  overwritable = overwritable_header
}
