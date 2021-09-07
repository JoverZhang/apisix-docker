local core = require('apisix.core')
local nacos = require('apisix.discovery.nacos')
local roundrobin = require('apisix.balancer.roundrobin')
local http = require('resty.http')

local sub_str = string.sub
local log = core.log
local nacos_nodes = nacos.nodes

local schema = {
    type = 'object',
    properties = {},
    required = {},
}

local plugin_name = 'oss-proxy'

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


---Get resource service node
---
---@param conf table
---@param ctx table
---@return string  ip address of node
local function get_resource_service_node(conf, ctx)
    local nodes = nacos_nodes('blade-resource')
    if not nodes then
        return nil, 'No active resource-service found'
    end

    local server_list = {}
    for _, node in ipairs(nodes) do
        server_list[node.host .. ':' .. node.port] = node.weight
    end

    -- TODO: 放置到全局
    local picker = roundrobin.new(server_list)
    local server, err = picker.get(ctx)
    if not server then
        return nil, err
    end
    return server
end

---Get OSS link from resource service
---
---@param host string
---@param file_name string
---@param tenant_id string
---@return (string, string) (oss link, error message)
local function get_oss_link(host, file_name, tenant_id)
    local url = 'http://' .. host .. '/client/file-link-tenant_id?fileName=' .. file_name .. '&tenantId=' .. tenant_id

    local httpc = http.new()
    httpc:set_timeouts(10000, 10000, 10000)
    local res, err = httpc:request_uri(url, {
        method = 'GET',
        headers = { ['Accept'] = 'application/json' },
    })

    if not res then
        return nil, err
    end
    if not res.body or res.status ~= 200 then
        return nil, 'status = ' .. res.status
    end

    -- To json
    local data, err = core.json.decode(res.body)
    if not data then
        return nil, err
    end
    return data.data
end

---Get file from link
---
---@param link string
---@return (table, string) (response body, error message)
local function get_file(link)
    local httpc = http.new()
    httpc:set_timeouts(10000, 10000, 10000)
    local res, err = httpc:request_uri(link, {
        method = 'GET',
        headers = { ['Content-Type'] = 'application/octet-stream' },
    })
    if not res then
        return nil, err
    end
    return res.body
end

---Handle access
---
---@param conf table
---@param ctx table
---@return (number, table) (status, body)
function _M.access(conf, ctx)
    local file_name = sub_str(ctx.var.uri, 6)
    log.notice('file name: ', file_name)

    local node_host, err = get_resource_service_node(conf, ctx)
    if not node_host then
        return 500, err
    end

    local link, err = get_oss_link(node_host, file_name, ctx.ext_var.jwt_obj.tenant_id)
    if not link then
        return 500, err
    end

    log.notice('link: ', link)
    return 200, get_file(link)
end

return _M
