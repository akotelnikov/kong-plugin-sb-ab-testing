local access = require "kong.plugins.sb-ab-testing.access"

local plugin = {
  PRIORITY = 900,
  VERSION = "0.1",
}

function plugin:access(conf)
  access.execute(conf)
end

return plugin
