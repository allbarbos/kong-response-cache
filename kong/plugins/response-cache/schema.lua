local typedefs = require "kong.db.schema.typedefs"
local strategies = require "kong.plugins.response-cache.strategies"

local PLUGIN_NAME = "response-cache"


local schema = {
  name = PLUGIN_NAME,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { consumer = typedefs.no_consumer },  -- this plugin cannot be configured on a consumer (typical for auth plugins)
    { protocols = typedefs.protocols_http },
    { config = {
        -- The 'config' record is the custom part of the plugin schema
        type = "record",
        fields = {
          -- a standard defined field (typedef), with some customizations
          -- { request_header = typedefs.header_name {
          --     required = true,
          --     default = "Hello-World" } },
          -- { response_header = typedefs.header_name {
          --     required = true,
          --     default = "Bye-World" } },
          -- { ttl = { -- self defined field
          --     type = "integer",
          --     default = 600,
          --     required = true,
          --     gt = 0, }
          -- }, -- adding a constraint for the value
          {
            request_method = {
              type = "array",
              default = { "GET", "HEAD" },
              elements = {
                type = "string",
                one_of = { "HEAD", "GET", "POST", "PATCH", "PUT" },
              },
              required = true,
            }
          },
          {
            strategy = {
              type = "string",
              one_of = strategies.STRATEGY_TYPES,
              required = true,
            }
          },
          {
            data_mapper = {
              type = "array",
              required = false,
              elements = {
                type = "record",
                fields = {
                  {
                    param = {
                      type = "string",
                      required = true,
                    }
                  },
                  {
                    source = {
                      type = "string",
                      required = true,
                      one_of = {
                        "path",
                      },
                    }
                  },
                }
              }
            }
          },
          {
            redis = {
              type = "record",
              fields = {
                {
                  host = {
                    type = "string",
                  }
                },
                {
                  port = {
                    between = { 0, 65535 },
                    type = "integer",
                    default = 6379,
                  }
                },
                {
                  password = {
                    type = "string",
                    len_min = 0,
                  }
                },
                {
                  timeout = {
                    type = "number",
                    default = 2000,
                  }
                },
                {
                  database = {
                    type = "integer",
                    default = 0,
                  }
                },
              },
            }
          },
          {
            memory = {
              type = "record",
              fields = {
                { dictionary_name = {
                  type = "string",
                  required = true,
                  default = "kong_db_cache",
                }},
              },
            }
          },
          {
            response_code = {
              type = "array",
              default = { 200, 301, 404 },
              elements = { type = "integer", between = {100, 900} },
              len_min = 1,
              required = true,
            }
          },
          {
            content_type = {
              type = "array",
              default = { "text/plain","application/json" },
              elements = { type = "string" },
              required = true,
            }
          },
          {
            cache_ttl = {
              type = "integer",
              default = 300,
              gt = 0,
            }
          },
        },
        -- entity_checks = {
        --   -- add some validation rules across fields
        --   -- the following is silly because it is always true, since they are both required
        --   { at_least_one_of = { "request_header", "response_header" }, },
        --   -- We specify that both header-names cannot be the same
        --   { distinct = { "request_header", "response_header"} },
        -- },
      },
    },
  },
}

return schema
