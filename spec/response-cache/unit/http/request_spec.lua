local mocks = require "spec.mocks"
local request = require "kong.plugins.response-cache.http.request"
_G.kong = mocks.kong

describe("Test if request", function()
  local conf = {
    request_method = { "GET", "HEAD" },
  }

  before_each(function()
    stub(mocks.kong.request, "get_method")
  end)

  it("is cacheable", function()
    kong.request.get_method.returns("GET")
    local actual = request.is_cacheable(conf)

    assert.is_true(actual)
  end)

  it("not is cacheable", function()
    kong.request.get_method.returns("NOK")
    local actual = request.is_cacheable(conf)

    assert.is_not_true(actual)
  end)
end)

describe("Test if cache header", function()
  local ctx = {}

  before_each(function()
    spy.on(mocks.kong.response, "set_header")
  end)

  it("is set", function()
    request.signal_cache(ctx, "cache_key_test", "Hit")

    assert.spy(mocks.kong.response.set_header).was_called_with("X-Cache-Status", "Hit")
    assert.are.equal(ctx.response_cache.cache_key, "cache_key_test")
  end)

  it("is set to default", function()
    request.signal_cache(ctx, "cache_key_test")

    assert.spy(mocks.kong.response.set_header).was_called_with("X-Cache-Status", "Miss")
    assert.are.equal(ctx.response_cache.cache_key, "cache_key_test")
  end)
end)
