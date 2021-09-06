local core = require("apisix.core")
local nacos = require('apisix.discovery.nacos')
local roundrobin = require("apisix.balancer.roundrobin")
local http = require('resty.http')

local sub_str = string.sub
local log = core.log
local nacos_nodes = nacos.nodes

local schema = {
    type = "object",
    properties = {},
    required = {},
}

local plugin_name = "oss-proxy"

local _M = {
    version = 0.1,
    priority = 14,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


--- Main Logics


local function request(request_uri, path, headers, body, method)
    local url = request_uri .. path
    log.notice('request url:', url)

    if body and 'table' == type(body) then
        local err
        body, err = core.json.encode(body)
        if not body then
            return nil, 'invalid body : ' .. err
        end
        headers['Content-Type'] = 'application/json'
    end

    local httpc = http.new()
    httpc:set_timeouts(10000, 10000, 10000)
    local res, err = httpc:request_uri(url, {
        method = method,
        headers = headers,
        body = body,
    })

    if not res then
        return nil, err
    end

    if not res.body or res.status ~= 200 then
        return nil, 'status = ' .. res.status
    end

    local json_str = res.body
    local data, err = core.json.decode(json_str)
    if not data then
        return nil, err
    end
    return data
end

local function get_url(request_uri, path)
    local headers = {}
    headers['Accept'] = 'application/json'
    return request(request_uri, path, headers, nil, 'GET')
end

local function get_resource_service_node(conf, ctx)
    local nodes = nacos_nodes('blade-resource')
    local server_list = {}
    for _, node in ipairs(nodes) do
        server_list[node.host .. ':' .. node.port] = node.weight
    end

    -- TODO: 放置全局
    local picker = roundrobin.new(server_list)
    local server, err = picker.get(ctx)
    if not server then
        return nil, err
    end
    return server
end

local function get_oss_link(host, file_name, tenant_id)
    local data, err = get_url('http://' .. host, '/client/file-link-tenant_id?fileName=' .. file_name .. '&tenantId=' .. tenant_id)
    if not data then
        return nil, err
    end
    return data.data
end

local function get_file(link)
    local headers = {
        ['Content-Type'] = 'application/octet-stream'
    }
    local httpc = http.new()
    httpc:set_timeouts(10000, 10000, 10000)
    local res, err = httpc:request_uri(link, {
        method = 'GET',
        headers = headers,
    })
    if not res then
        return nil, err
    end
    return res.body
end

function _M.access(conf, ctx)
    local file_name = sub_str(ctx.var.uri, 6)
    log.notice("file name: ", file_name)

    local node_host = get_resource_service_node(conf, ctx)

    local link, err = get_oss_link(node_host, file_name, ctx.ext_var.jwt_obj.tenant_id)
    if not link then
        return 500, err
    end

    log.notice("link: ", link)
    return 200, get_file(link)
end

return _M
