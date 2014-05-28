local ngxex          = require 'ngxex'
local model_helpers  = require 'model_helpers'
local luajson        = require 'json'
local utf8_validator = require 'utf8_validator'

local helpers = {}

local remove_binary_strings = function(obj)
  if type(obj) == 'string' and not utf8_validator.validate(obj) then return '<binary>' end
  return obj
end

helpers.exit_json = function(object_to_serialize, status)
  helpers.send_json(object_to_serialize, status)
  ngx.exit(status)
end

helpers.print = function(str)
  local head_request = ngx.req.get_method() == 'HEAD'
  ngx.header['Content-Length'] = #str

  if not head_request then
    ngx.print(str)
  else
    ngx.eof() -- skipping print for head request
  end
end

helpers.send_json = function(object_to_serialize, status)
  ngx.status = status or ngx.HTTP_OK
  helpers.print(helpers.json_response(object_to_serialize))
end

helpers.json_response = function(object_to_serialize, status)
  ngx.header['Content-Type'] = 'application/json'

  if type(object_to_serialize) == 'table' and (next(object_to_serialize) == nil) then
    return '[]'
  else
    return luajson.encode(object_to_serialize, {preProcess = remove_binary_strings})
  end
end

helpers.request_json = function()
  if not ngx.ctx.req_json then
    ngx.req.read_body()
    ngx.ctx.req_json = helpers.decode_json_or_error(ngxex.req_get_all_body_data())
  end
  return ngx.ctx.req_json
end

helpers.jor_options = function(params)
  local options = {}
  local per_page = params and tonumber(params.per_page) or 20
  local max_per_page = 100

  options.reversed = not not params.reversed
  options.max_documents = per_page > max_per_page and max_per_page or per_page

  return options
end

helpers.jor_conditions_and_options = function(params, ordering)
  local conditions = helpers.decode_json_or_error(params.query or '{}')
  local options = helpers.jor_options(params)
  local last_id = params.last_id

  if last_id then
    ordering = ordering or options.reversed and '$lt' or '$gt'
    conditions._id = { [ordering] = tonumber(last_id) }
  end

  return conditions, options
end

helpers.decode_json_or_error = function(json_string, malformed_message, empty_message)

  malformed_message = malformed_message or "Malformed JSON: " .. tostring(json_string)
  empty_message =     empty_message or "Unexpected empty string. Expecting JSON-enconding string"

  if type(json_string) ~= 'string' then
    error({ status = ngx.HTTP_BAD_REQUEST, message = malformed_message })
  end

  if json_string == "" then
    error({ status = ngx.HTTP_BAD_REQUEST, message = empty_message })
  end


  local ok, result = pcall(luajson.decode, json_string)
  if ok then
    return result
  else
    malformed_message = malformed_message or result
    error({ status = ngx.HTTP_BAD_REQUEST, message = malformed_message })
  end
end

helpers.empty_json_array = function()
  return luajson.decode('[]')
end

return helpers