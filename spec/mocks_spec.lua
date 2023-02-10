local spy = require 'luassert.spy'

local kong = {
  response = {
    exit = spy.new(function(status, body)
      return status, body
    end)
  },
  request = {
    get_headers = spy.new(function()
      return {}
    end),
  },
  log = {
    err = spy.new(function(err) end),
    info = spy.new(function(msg) end)
  }
}

return {
  kong = kong,
}
