local mocks = require "spec.mocks"
local header = require "kong.plugins.response-cache.http.header"
_G.ngx = mocks.ngx

describe("Test if", function()
  before_each(function()
    stub(mocks.ngx.re, "match")
  end)

  it("is hop-by-hop header", function()
    mocks.ngx.re.match.returns(true, nil)
    local actual = header.overwritable("keep-alive")
    assert.is_not_true(actual)
  end)

  it("is not hop-by-hop header", function()
    mocks.ngx.re.match.returns(true, nil)
    local actual = header.overwritable("content-type")
    assert.is_true(actual)
  end)
end)
