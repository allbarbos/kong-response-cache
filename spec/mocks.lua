local kong = {
  request = {
    get_method = function()
    end,
    get_query = function()
    end,
    get_headers = function()
    end,
  },
  response = {
    set_header = function(key, value)
    end,
    get_status = function()
    end,
  },
  log = {
    inspect = function()
    end,
    debug = function()
    end
  },
  client = {
    get_consumer = function()
      return nil
    end
  },
  router = {
    get_route = function()
    end
  },
}

local ngx = {
  var = {
    sent_http_content_type = "application/json",
  },
  re = {
    match = function(subject, regex)
    end,
    gsub = function(subject, regex, replace, options)
    end,
  },
  ctx = {
    router_matches = {
      uri_captures = {}
    }
  }
}


return {
  kong = kong,
  ngx = ngx,
}
