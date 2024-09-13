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

local function generate_user_id(conf)
  local user_id = kong.request.get_header("x-request-id")
  if not user_id or user_id == "" then
    user_id = uuid.generate_v4()
  end

  if conf.log then
    local log_message = string.format("New user-id %s has been assigned", user_id)
    kong.log.notice(log_message)
  end

  return user_id
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

  if not res or err then
    local log_message = string.format(
      "The A/B group retrieving request by the user-id %s and the experiment_uuid %s wasn't fulfilled",
      user_id, conf.experiment_uuid)
    kong.log.err(log_message)
    kong.log.err(err)
    return nil
  end
  if not res.body or res.body == "" then
    local log_message = string.format(
      "The A/B group retrieving request by the user-id %s and the experiment_uuid %s can't be parsed",
      user_id, conf.experiment_uuid)
    kong.log.err(log_message)
    return nil
  end
  if conf.log then
    local log_message = string.format(
      "The A/B group retrieving request by the user-id %s and the experiment_uuid %s was fulfilled with body %s", user_id,
      conf.experiment_uuid, res.body)
    kong.log.notice(log_message)
  end

  local body = cjson.decode(res.body)
  local group_name = body.group_name
  if not group_name then
    local log_message = string.format("The A/B Splitter didn't return a group_name for the user %s", user_id)
    kong.log.err(log_message)
    return nil
  end
  local is_user_splitted = body.is_user_splitted
  if not is_user_splitted then
    local log_message = string.format("The user with id %s can't be splitted", user_id)
    kong.log.err(log_message)
    return nil
  end

  if conf.log then
    local log_message = string.format("The group_name %s has been assigned to the user_id %s", group_name,
    user_id)
    kong.log.notice(log_message)
  end

  return group_name
end

local function modify_routes(ab_group_name, conf)
  if not ab_group_name then
    local log_message = string.format("There's no A/B group name for the experiment_uuid %s", conf.experiment_uuid)
    kong.log.err(log_message)
    return
  end

  local target_group
  for i, group in ipairs(conf.groups or {}) do
    if group.group_name == ab_group_name then
      target_group = group;
    end
  end

  -- if can't find a target_group for any reason we don't modify routes
  if not target_group then
    local log_message = string.format(
      "There's no published site for the A/B group name %s and experiment_uuid %s",
      ab_group_name, conf.experiment_uuid)
    kong.log.err(log_message)
    return
  end

  local target_path = string.format("/%s/", target_group.site_name)
  local normalized_path = path_normalization.get_normalized_path(conf.path_transformation, target_path)
  kong.service.request.set_path(normalized_path)
end

local function update_cookie(user_id, ab_group_name)
  if not user_id or not ab_group_name then
    return
  end

  local cookie_flags = string.format("; Max-Age=%d", COOKIE_MAX_AGE)
  local user_id_cookie = string.format("%s=%s%s", SB_USER_ID_COOKIE_NAME, user_id, cookie_flags)
  local ab_group_name_cookie = string.format("%s=%s%s", SB_AB_GROUP_NAME_COOKIE_NAME, ab_group_name, cookie_flags)
  kong.response.add_header("Set-Cookie", user_id_cookie)
  kong.response.add_header("Set-Cookie", ab_group_name_cookie)
end

function _M.execute(conf)
  local user_id = ngx.var["cookie_" .. string.upper(SB_USER_ID_COOKIE_NAME)]
  if not user_id then
    user_id = generate_user_id(conf)
  end

  -- ab_group_name is supposed to be a document._id
  local ab_group_name = ngx.var["cookie_" .. string.upper(SB_AB_GROUP_NAME_COOKIE_NAME)]
  if not ab_group_name then
    ab_group_name = fetch_ab_group_name(user_id, conf)
  end

  modify_routes(ab_group_name, conf)
  update_cookie(user_id, ab_group_name)
end

return _M
