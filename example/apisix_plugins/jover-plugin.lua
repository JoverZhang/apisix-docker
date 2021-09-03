local core = require("apisix.core")

local schema = {
    type = "object",
    properties = {
        body = {
            description = "body to replace response.",
            type = "string"
        },
    },
    required = { "body" },
}

local plugin_name = "jover-plugin"

local _M = {
    version = 0.1,
    priority = 12,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    core.log.warn("jovertest")
    return 200, conf.body
end

return _M
