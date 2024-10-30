local cjson = require "cjson"
local uuid = require "resty.jit-uuid"
local http = require "resty.http"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"

local ngx = ngx
local kong = kong

-- local REGULAR_AB_TEST_TYPE = 'regular'
local AUTHORIZED_USERS_ONLY_AB_TEST_TYPE = 'authorized-users-only'

local SB_USER_ID_COOKIE_NAME = 'sb_user_id'
local SB_AB_GROUP_NAME_COOKIE_NAME = 'sb_ab_group'
local SB_XSOLLA_LOGIN_TOKEN_COOKIE_NAME = 'xsolla_login_token_sb'
local COOKIE_MAX_AGE = 604800 -- 1 week

local _M = {}

local function parse_user_id_from_token(conf)
  local token = ngx.var["cookie_" .. string.upper(SB_XSOLLA_LOGIN_TOKEN_COOKIE_NAME)]
  if not token then
    return
  end
  local jwt, err = jwt_decoder:new(token)
  if err then
    local log_message = string.format("The token can't be decoded; %s", tostring(err))
    kong.log.err(log_message)
    return
  end

  local user_id
  -- if that would be necessary we will add more providers in future
  if jwt.claims.provider == "kabam" then
    if jwt.claims and jwt.claims.partner_data and jwt.claims.partner_data.custom_parameters and jwt.claims.partner_data.custom_parameters.mcoc then
      user_id = tostring(jwt.claims.partner_data.custom_parameters.mcoc)
    else
      local log_message = string.format("There's no partner_data.custom_parameters.mcoc in the token %s", token)
      kong.log.err(log_message)
    end
  end

  if user_id and conf.log then
    local log_message = string.format("The user-id %s has been parsed from the auth cookie", user_id)
    kong.log.notice(log_message)
  end
  return user_id
end

local function generate_user_id(conf)
  local user_id = kong.request.get_header("x-request-id")
  if not user_id or user_id == "" then
    user_id = uuid.generate_v4()
  end

  if conf.log then
    local log_message = string.format("A new user-id %s has been assigned", user_id)
    kong.log.notice(log_message)
  end

  return user_id
end

local function parse_user_conditions(user_id, conf)
  local user_agent = string.lower(kong.request.get_header("User-Agent"))

  local device = "desktop"
  if string.find(user_agent, "mobile") or string.find(user_agent, "android") or string.find(user_agent, "iphone") then
    device = "mobile"
  end

  local os = "unknown"
  if string.find(user_agent, "android") then
    os = "android"
  end
  if string.find(user_agent, "iphone") then
    os = "ios"
  end

  local conditions = {
    [1] = {
      name = "device",
      value = device
    },
    [2] = {
      name = "os",
      value = os
    }
  }

  local country = kong.request.get_header("x-geoip-country") or ""
  if country and country ~= "" then
    table.insert(conditions, {
      name = "country",
      value = country
    })
  end

  if conf.log then
    local log_message = string.format("The user %s is identified with a device %s, an OS %s and a country %s", user_id,
      device, os,
      country)
    kong.log.notice(log_message)
  end

  return conditions
end

local function fetch_ab_group_name(user_id, conf)
  if not user_id then
    local log_message = string.format("There's no user-id has been provided while fetching an A/B group name")
    kong.log.err(log_message)
    return nil
  end

  local httpc = http.new()
  httpc:set_timeout(conf.ab_splitter_api.timeout)

  local uri = string.format("https://%s%s", conf.ab_splitter_api.base_url, conf.ab_splitter_api.path)
  local body = cjson.encode({
    experiment_uuid = conf.experiment.uuid,
    user_id = user_id,
    conditions = parse_user_conditions(user_id, conf)
  })
  local res, err = httpc:request_uri(uri, {
    method = "POST",
    body = body,
  })

  if not res or err then
    local log_message = string.format(
      "The A/B group retrieving request by the user-id %s and the experiment %s wasn't fulfilled; %s",
      user_id, conf.experiment.uuid, tostring(err))
    kong.log.err(log_message)
    return nil
  end
  if not res.body or res.body == "" then
    local log_message = string.format(
      "The A/B group retrieving request by the user-id %s and the experiment %s can't be parsed",
      user_id, conf.experiment.uuid)
    kong.log.err(log_message)
    return nil
  end
  if conf.log then
    local log_message = string.format(
      "The A/B group retrieving request by the user-id %s and the experiment %s was fulfilled with body %s", user_id,
      conf.experiment.uuid, res.body)
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
    local log_message = string.format("The group_name %s has been assigned to the user-id %s", group_name,
      user_id)
    kong.log.notice(log_message)
  end

  return group_name
end

local function get_service_path()
  local service = kong.router.get_service()
  if service then
    -- For example "/my-game/"
    return service.path
  end
  return ""
end

local function modify_routes(ab_group_name, conf)
  if not ab_group_name then
    local log_message = string.format("There's no A/B group name for the experiment %s", conf.experiment.uuid)
    kong.log.err(log_message)
    return
  end

  local target_group
  for i, group in ipairs(conf.experiment.groups or {}) do
    if group.group_name == ab_group_name then
      target_group = group;
    end
  end

  -- if can't find a target_group for any reason we don't modify routes
  if not target_group then
    local log_message = string.format(
      "There's no published site for the A/B group name %s and the experiment %s",
      ab_group_name, conf.experiment.uuid)
    kong.log.err(log_message)
    return
  end

  if conf.log then
    local log_message = string.format("Due to an A/B testing policy the service will be changed to %s",
      target_group.site_name)
    kong.log.notice(log_message)
  end

  local req_service_path = string.gsub(get_service_path(), '%-', "%%-") -- making a pattern from a string with -
  local req_path = kong.request.get_path()
  local target_path = string.format("/%s/", target_group.site_name)     -- changing from my-site to /my-site/

  local path_with_experiment = string.gsub(req_path, req_service_path, target_path)
  -- kong.service.request.set_path(path_with_experiment)

  -- used to build service req path in the kong-plugin-google-storage-adapter
  kong.ctx.shared.ab_testing_path = path_with_experiment

  if conf.log then
    local log_message = string.format("The path has been changed to %s due to the A/B testing policy",
      path_with_experiment)
    kong.log.notice(log_message)
  end
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
  local datetime_now = os.time()
  local is_experiment_active = datetime_now > conf.experiment.datetime_start and
      datetime_now < conf.experiment.datetime_end
  if not is_experiment_active then
    return
  end

  local user_id = ngx.var["cookie_" .. string.upper(SB_USER_ID_COOKIE_NAME)]
  if not user_id then
    if conf.experiment.type == AUTHORIZED_USERS_ONLY_AB_TEST_TYPE then
      user_id = parse_user_id_from_token(conf)
    else
      -- conf.experiment.type == REGULAR_AB_TEST_TYPE
      user_id = generate_user_id(conf)
    end
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
