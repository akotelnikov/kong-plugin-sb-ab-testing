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
