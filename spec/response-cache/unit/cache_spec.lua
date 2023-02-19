local mocks = require "spec.mocks"
local cache = require "kong.plugins.response-cache.cache"
_G.kong = mocks.kong
_G.ngx = mocks.ngx

describe("build_key", function()
  local cfg

  before_each(function()
    stub(mocks.ngx.re, "gsub")
    stub(mocks.kong.request, "get_method")
    stub(mocks.kong.request, "get_query")
    stub(mocks.kong.request, "get_headers")
    stub(mocks.kong.router, "get_route")
    cfg = {
      cache_ttl = 0,
      content_type = {
        "application/json",
      },
      memory = {
        dictionary_name = "kong_db_cache"
      },
      redis = {
        database = 0,
        host = "cache",
        port = 6379,
        timeout = 2000
      },
      request_method = {
        "GET", "HEAD",
      },
      response_code = {
        200, 301, 404,
      },
      service_id = "ebd5ce94-0fe9-5923-9f3d-8e851cd6db76",
      strategy = "redis"
    }
  end)

  it("make cache key by path param", function()
    local pathParam = "test"
    mocks.ngx.ctx.router_matches.uri_captures = {
      pathParam,
      [0] = "/request/" .. pathParam,
      testID = pathParam
    }
    cfg.key_mapper = {
      {
        param = "testID",
        source = "path"
      },
    }

    local actual = cache.build_key(cfg)
    assert.equal(pathParam, actual)
  end)

  it("make cache key by default", function()
    mocks.ngx.re.gsub.returns("GET /request/test HTTP/1.1")
    mocks.kong.request.get_method.returns("GET")
    mocks.kong.request.get_query.returns({})
    mocks.kong.router.get_route.returns("036d43c4-8c90-53ec-bbbb-4686e56b75cb")
    mocks.kong.request.get_headers.returns({
      accept = "*/*",
      ["accept-encoding"] = "gzip, deflate, br",
      connection = "keep-alive",
      host = "test",
    })

    local actual = cache.build_key(cfg)
    assert.equal("7a2af7057deeaebc05a7c25c37f588027977d95d9fabe384a0ce9bf8368878ae", actual)
  end)
end)


describe("store_cache_value", function()

end)
