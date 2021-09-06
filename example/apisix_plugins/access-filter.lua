local core = require("apisix.core")
local jwt = require("resty.jwt")

local log = core.log
local sub_str = string.sub
local lower_str = string.lower

local DEFAULT_TOKEN_NAME = "Blade-Auth"
local DEFAULT_SING_KEY = "bladexisapowerfulmicroservicearchitectureupgradedandoptimizedfromacommercialproject"

local plugin_name = "access-filter"

local schema = {
    type = "object",
    properties = {
        token_name = {
            description = "The name of JWT token in Http header.",
            type = "string",
            default = DEFAULT_TOKEN_NAME,
        },
        sign_key = {
            description = "The sign key of JWT.",
            type = "string",
            default = DEFAULT_SING_KEY,
        },
    },
}

local _M = {
    version = 0.1,
    priority = 13,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


--- Main Logics


-- Get JWT token
local function get_jwt_token(conf, ctx)
    -- Get token from header
    local token = core.request.header(ctx, conf.token_name)
    if token then
        local prefix = sub_str(token, 1, 7)
        if lower_str(prefix) == "bearer " then
            return sub_str(token, 8)
        end
        return token
    end

    -- Get token from url argument
    token = ctx.var["arg_" .. conf.token_name]
    if token then
        return token
    end
end

-- Verify JWT token
local function verify_jwt_token(conf, ctx, jwt_token)
    -- Parse JWT
    local jwt_obj = jwt:load_jwt(jwt_token)
    if not jwt_obj.valid then
        return { message = jwt_obj.reason }
    end

    -- Verify JWT
    jwt_obj = jwt:verify_jwt_obj(conf.sign_key, jwt_obj)
    log.info("jwt object payload: ", core.json.delay_encode(jwt_obj.payload))
    if not jwt_obj.verified then
        return { message = jwt_obj.reason }
    end
end


-- Handle access
function _M.rewrite(conf, ctx)
    local jwt_token = get_jwt_token(conf, ctx)
    if not jwt_token then
        return 401, "Missing token"
    end

    local err = verify_jwt_token(conf, ctx, jwt_token)
    if err then
        return 401, err
    end
end

return _M
