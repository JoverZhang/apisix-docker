local core = require("apisix.core")

local schema = {
    type = "object",
}

local plugin_name = "access-filter"

local _M = {
    version = 0.1,
    priority = 13,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


--- Logics

local AUTH_KEY = "Blade-Auth"

local function process_authkey(conf, ctx, authkey)
    core.log.warn("key: " .. authkey)
    if authkey == "abc" then
        core.log.warn("true")
        return true
    end
    core.log.warn("false")
    return false
end

function _M.header_filter(conf, ctx)
    local authkey = core.request.header(ctx, AUTH_KEY)
    local allow_access = process_authkey(conf, ctx, authkey)

    if not allow_access then
        return 500
    end
end

return _M
