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
                { path = { type = "string", required = true, default = "/v3/split/by_experiment_uuid" } },
                { timeout = { type = "integer", required = true, default = 10000 } },
              }
            }
          },
          {
            experiment = {
              type = "record",
              fields = {
                { uuid = { type = "string", required = true } },
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
                { datetime_start = { type = "integer", required = true } },
                { datetime_end = { type = "integer", required = true } },
              }
            },
            { log = { type = "boolean", required = true, default = false } },
            {
              path_transformation = {
                type = "record",
                fields = {
                  { enabled = { type = "boolean", required = true, default = true } },
                  { log = { type = "boolean", required = true, default = false } },
                  { prefix = { type = "string", required = false, default = "/sites" } }
                }
              }
            }
          }
        }
      }
    }
  }
}

return schema
