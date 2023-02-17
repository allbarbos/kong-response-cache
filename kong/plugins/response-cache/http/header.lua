local ngx                = ngx
local ngx_re_match       = ngx.re.match
local lower              = string.lower

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

local function overwritable_header(header)
  local n_header = lower(header)

  return not hop_by_hop_headers[n_header] and not ngx_re_match(n_header, "ratelimit-remaining")
end

return {
  overwritable = overwritable_header
}
