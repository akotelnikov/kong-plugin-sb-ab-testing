local kong = kong

local _M = {}

function _M.execute(conf)
  kong.log.inspect(conf)   -- check the logs for a pretty-printed config!
end

return _M
