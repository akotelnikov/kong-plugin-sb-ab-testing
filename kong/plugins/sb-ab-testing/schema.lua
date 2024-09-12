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
          {
            ab_splitter_api = {
              type = "record",
              fields = {
                { base_url = { type = "string", required = true, default = "ab-splitter.xsolla.com" } },
                { path = { type = "string", required = true, default = "/v3/split/by_user_id" } },
                { timeout = { type = "integer", required = true, default = 10000 } },
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
          { experiment_uuid = { type = "string", required = true } },
          {
            groups = {
              type = "array",
              elements = {
                type = "record",
                fields = {
                  { group_name = { type = "string", required = true } },
                  { site_name = { type = "string", required = true } },
                }
              },
            }
          },
          {
            path_transformation = {
              type = "record",
              fields = {
                { enabled = { type = "boolean", required = true, default = true } },
                { log = { type = "boolean", required = true, default = false } },
                { prefix = { type = "string", required = false } }
              }
            }
          }
        }
      },
    },
  },
}

return schema