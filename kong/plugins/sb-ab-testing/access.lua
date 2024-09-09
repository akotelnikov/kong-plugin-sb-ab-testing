local cjson = require "cjson"
local uuid = require "resty.jit-uuid"
local http = require "resty.http"

local ngx = ngx
local kong = kong

local SB_USER_ID_COOKIE_NAME = 'sb_user_id'
local SB_AB_GROUP_NAME_COOKIE_NAME = 'sb_ab_group'

local _M = {}

local function get_user_id()
  local request_id = kong.request.get_header("x-request-id")
  if not request_id or request_id == "" then
    request_id = uuid.generate_v4()
  end
end

local function fetch_ab_group_name(user_id, conf)
  local httpc = http.new()
  httpc:set_timeout(conf.timeout)

  local uri = "https://" .. conf.ab_splitter_api.base_url .. "/v3/split/by_user_id"
  local body = cjson.encode({
    experiment_uuid = conf.experiment_uuid,
    user_id = user_id,
  })
  local res, err = httpc:request_uri(uri, {
    method = "POST",
    body = body,
  })

  if not res then
    kong.log.err(err)
  end

  local body = res.body
  if body and body ~= "" then
    body = cjson.decode(body)
  end

  return body.group_name
end

local function modify_routes()
end

function _M.execute(conf)
  local user_id = ngx.var["cookie_" .. string.upper(SB_USER_ID_COOKIE_NAME)]
  if not user_id then
     user_id = get_user_id()
  end
  local ab_group_name = ngx.var["cookie_" .. string.upper(SB_AB_GROUP_NAME_COOKIE_NAME)]
  if !ab_group_name then
    ab_group_name = fetch_ab_group_name(user_id, conf)
  end
  modify_routes(ab_group_name, conf)
  -- update_cookie(user_id, ab_group)
  get_ab_group()
end

return _M
