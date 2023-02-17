local kong = {
  request = {
    get_method = function()
    end,
  },
  response = {
    set_header = function(key, value)
    end,
    get_status = function()
    end,
  },
}

local ngx = {
  var = {
    sent_http_content_type = "application/json",
  },
  re = {
    match = function(subject, regex)
    end,
  }
}

return {
  kong = kong,
  ngx = ngx,
}
