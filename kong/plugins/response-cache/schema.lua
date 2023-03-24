local typedefs = require "kong.db.schema.typedefs"
local strategies = require "kong.plugins.response-cache.strategies"

local PLUGIN_NAME = "response-cache"

local schema = {
  name = PLUGIN_NAME,
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
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
          key_mapper = {
            type = "array",
            required = false,
            elements = {
              type = "record",
              fields = {
                {
                  source = {
                    type = "string",
                    required = true,
                    one_of = {
                      "path",
                    },
                  }
                },
                {
                  param = {
                    type = "string",
                    required = true,
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
              } },
            },
          }
        },
        {
          response_code = {
            type = "array",
            default = { 200, 301, 404 },
            elements = { type = "integer", between = { 100, 900 } },
            len_min = 1,
            required = true,
          }
        },
        {
          content_type = {
            type = "array",
            default = { "text/plain", "application/json" },
            elements = { type = "string" },
            required = true,
          }
        },
        {
          cache_ttl = {
            type = "integer",
            required = true,
            default = 0,
          }
        },
      },
    },
    },
  },
}

return schema
