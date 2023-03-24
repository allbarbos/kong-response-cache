local mocks = require "spec.mocks"
local response = require "kong.plugins.response-cache.http.response"
_G.kong = mocks.kong
_G.ngx = mocks.ngx

describe("Test if response", function()
  local conf = {
    response_code = { 200, 301, 404 },
    content_type = { "text/plain", "application/json" },
  }

  before_each(function()
    stub(mocks.kong.response, "get_status")
  end)

  it("is cacheable", function()
    kong.response.get_status.returns(200)
    local actual = response.is_cacheable(conf)

    assert.is_true(actual)
  end)

  it("is not cacheable", function()
    kong.response.get_status.returns(500)
    local actual = response.is_cacheable(conf)

    assert.is_not_true(actual)
  end)

  it("cannot be cached when the content-type is empty", function()
    _G.ngx.var.sent_http_content_type = ""
    kong.response.get_status.returns(200)
    local actual = response.is_cacheable(conf)

    assert.is_not_true(actual)
  end)

  it("cannot be cached when the content type is not allowed", function()
    _G.ngx.var.sent_http_content_type = "test"
    kong.response.get_status.returns(200)
    local actual = response.is_cacheable(conf)

    assert.is_not_true(actual)
  end)
end)
