local cjson = require "cjson"
local uuid = require "resty.jit-uuid"
local http = require "resty.http"

local path_normalization = require "kong.plugins.sb-ab-testing.path_normalization"

local ngx = ngx
local kong = kong

local SB_USER_ID_COOKIE_NAME = 'sb_user_id'
local SB_AB_GROUP_NAME_COOKIE_NAME = 'sb_ab_group'
local COOKIE_MAX_AGE = 604800 -- 1 week

local _M = {}

local function generate_user_id()
  local request_id = kong.request.get_header("x-request-id")
  if not request_id or request_id == "" then
    request_id = uuid.generate_v4()
  end
  return request_id
end

local function fetch_ab_group_name(user_id, conf)
  local httpc = http.new()
  httpc:set_timeout(conf.timeout)

  local uri = string.format("https://%s%s", conf.ab_splitter_api.base_url, conf.ab_splitter_api.path)
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

local function modify_routes(ab_group_name, conf)
  if not ab_group_name then
    local log_message = string.format(
      "A/B group name can't be found in the site with _id %s and experiment_uuid %s",
      ab_group_name, conf.experiment_uuid)
    kong.log.notice(log_message)
    return
  end

  local target_group
  for i, group in ipairs(conf.groups) do
    if group.group_name == ab_group_name then
      target_group = group;
    end
  end

  -- if can't find a target_group for any reason we don't modify routes
  if not target_group then
    local log_message = string.format(
      "There's no the experiment group in the response. Routes remain default in the site with _id %s and experiment_uuid %s",
      ab_group_name, conf.experiment_uuid)
    kong.log.notice(log_message)
    return
  end

  local target_path = string.format("/%s/", target_group.site_name)
  local normalized_path = path_normalization.get_normalized_path(conf.path_transformation, target_path)
  kong.service.request.set_path(normalized_path)
end

local function update_cookie(user_id, ab_group_name)
  -- local original_cookie = ngx.header["Set-Cookie"]
  -- local remember_flags = string.format("; Max-Age=%d", COOKIE_MAX_AGE)

  -- local user_id_cookie_data = string.format("%s=%s%s", SB_USER_ID_COOKIE_NAME, user_id, remember_flags)
  -- local cookie_with_user_id = merge_cookies(original_cookie, #SB_USER_ID_COOKIE_NAME, SB_USER_ID_COOKIE_NAME, user_id_cookie_data)

  -- local updated_cookie_data = string.format("%s=%s%s", SB_AB_GROUP_NAME_COOKIE_NAME, ab_group_name, remember_flags)
  -- local updated_cookie = merge_cookies(cookie_with_user_id, #SB_AB_GROUP_NAME_COOKIE_NAME, SB_AB_GROUP_NAME_COOKIE_NAME, updated_cookie_data)

  -- ngx.header["Set-Cookie"] = updated_cookie

  local cookie_flags = string.format("; Max-Age=%d", COOKIE_MAX_AGE)
  kong.response.add_header("Set-Cookie", 
    string.format("%s=%s%s", SB_USER_ID_COOKIE_NAME, user_id, cookie_flags))
  kong.response.add_header("Set-Cookie",
    string.format("%s=%s%s", SB_AB_GROUP_NAME_COOKIE_NAME, ab_group_name, cookie_flags))
end

function _M.execute(conf)
  local user_id = ngx.var["cookie_" .. string.upper(SB_USER_ID_COOKIE_NAME)]
  if not user_id then
    user_id = generate_user_id()
  end

  -- ab_group_name is a document._id
  local ab_group_name = ngx.var["cookie_" .. string.upper(SB_AB_GROUP_NAME_COOKIE_NAME)]
  if not ab_group_name then
    ab_group_name = fetch_ab_group_name(user_id, conf)
  end

  modify_routes(ab_group_name, conf)
  update_cookie(user_id, ab_group_name)
end

return _M
