local typedefs = require "kong.db.schema.typedefs"

local PLUGIN_NAME = "sb-ab-testing"

local schema = {
  name = PLUGIN_NAME,
  fields = {
    { protocols = typedefs.protocols { default = { "http", "https" } } },
    {
      config = {
        type = "record",
        fields = {
          { experiment_uuid = { type = "string", required = true } },
          {
            ab_splitter_api = {
              type = "record",
              fields = {
                { base_url = { type = "string", required = true, default = "ab-splitter.xsolla.com" } },
                { timeout = { type = "integer", required = true,  default = 60000 } },
              }
            }
          },
          {
            conditions = {
              type = "array",
              elements = {
                type = "record",
                fields = {
                  { name = { type = "string", required = true } },
                  { value = { type = "string", required = true } },
                }
              },
            }
          },
          {
            groups = {
              type = "array",
              elements = {
                type = "record",
                fields = {
                  { group_name = { type = "string", required = true } },
                  { site_name = { type = "string", required = true } },
                  { site_percent = { type = "integer", required = true } },
                }
              },
            }
          }
        }
      },
    },
  },
}

return schema
