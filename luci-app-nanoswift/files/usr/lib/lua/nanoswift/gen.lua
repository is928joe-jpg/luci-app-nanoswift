local json = require "luci.jsonc"

local _M = {}

-- 统一的路径清理函数
local function clean_path(path, default)
    if not path or path == "" then
        return default
    end
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    path = path:gsub("/+$", "")
    return path
end

local function get_lan_ip()
    local handle = io.popen("uci get network.lan.ipaddr 2>/dev/null")
    local ip = handle:read("*l"); handle:close()
    if ip and ip ~= "" and not ip:match("^127%.") then return ip end
    handle = io.popen(
        "ubus call network.interface.lan status 2>/dev/null | grep -oE '\"address\":\"[0-9.]+' | head -1 | cut -d'\"' -f4")
    ip = handle:read("*l"); handle:close()
    if ip and ip ~= "" and not ip:match("^127%.") and not ip:match("^169%.") then return ip end
    return "0.0.0.0"
end

local function deep_copy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do copy[k] = deep_copy(v) end
    return copy
end

local function get_template(work_dir, secret)
    local inbound_lan_ip = get_lan_ip()
    return {
        log = { level = "fatal", timestamp = true },
        dns = {
            servers = {
                { type = "tls",    tag = "cloudflare", server = "1.1.1.1" },
                { type = "udp",    tag = "local",      server = "223.5.5.5" },
                { type = "fakeip", tag = "remote",     inet4_range = "198.18.0.0/15" }
            },
            rules = {
                {
                    rule_set = {
                        "geosite-geolocation-cn",
                        "geosite-bytedance"
                    },
                    server = "local"
                },
                { query_type = "A", server = "remote" }
            },
            independent_cache = true,
            strategy = "ipv4_only"
        },
        inbounds = {
            {
                type = "tun",
                interface_name = "sb-tun0",
                mtu = 9000,
                address = "198.18.0.1/30",
                auto_route = true,
                auto_redirect = true,
                strict_route = true,
                stack = "mixed"
            },
            {
                listen = inbound_lan_ip,
                listen_port = tonumber(mixed_port) or 1080,
                tag = "mixed-in",
                type = "mixed"
            }
        },
        outbounds = {},
        route = { rules = {}, rule_set = {}, default_domain_resolver = "local", auto_detect_interface = true },
        experimental = {
            cache_file = { enabled = true, path = "cache.db", store_fakeip = true, cache_id = "ID_wxv0ukqz", rdrc_timeout = "160h0m0s" },
            clash_api = {
                external_controller = "",
                external_ui = "/etc/nanoswift/run/dashboard",
                secret = secret or "",
                access_control_allow_origin = {},
                access_control_allow_private_network = true
            }
        }
    }
end

local function get_predefined_rule_sets()
    return {
        "geoip-cn", "geosite-geolocation-cn", "geosite-geolocation-!cn",
        "geosite-chinatelecom", "geosite-chinamobile", "geosite-chinaunicom", "geosite-bytedance",
        "geosite-telegram", "geoip-telegram"
    }
end

-- 解析单个规则
local function parse_rule_single(rule_str, outbound)
    local rule = { outbound = outbound }

    -- 端口范围格式: 1000-2000
    if rule_str:match("^(%d+)-(%d+)$") then
        local s, e = rule_str:match("^(%d+)-(%d+)$")
        rule.port = { tonumber(s), tonumber(e) }
        rule.network = "tcp"
        return rule
    end

    -- 单端口格式: 443
    if rule_str:match("^%d+$") then
        rule.port = tonumber(rule_str)
        rule.network = "tcp"
        return rule
    end

    -- IP 地址格式: 1.1.1.1 或 10.0.0.0/8 或 IPv6
    if rule_str:match("^%d+%.%d+%.%d+%.%d+") or rule_str:match("^[a-fA-F0-9:]+:") then
        rule.ip_cidr = rule_str
        return rule
    end

    -- 域名后缀格式（不以 . 开头，包含常见域名后缀）
    if rule_str:match("%.com$") or rule_str:match("%.cn$") or rule_str:match("%.org$") or
        rule_str:match("%.net$") or rule_str:match("%.gov$") or rule_str:match("%.edu$") then
        rule.domain_suffix = rule_str
        return rule
    end

    -- 域名后缀格式（以 . 开头）
    if rule_str:match("^%.") then
        rule.domain_suffix = rule_str:sub(2)
        return rule
    end

    -- SRS 规则集
    if rule_str:match("^geosite%-") or rule_str:match("^geoip%-") then
        rule.rule_set = rule_str:gsub("%.srs$", "")
        return rule
    end

    -- 域名关键词（去除可能的引号）
    local cleaned = rule_str:gsub('^"', ''):gsub('"$', '')
    rule.domain_keyword = cleaned
    return rule
end

-- 解析规则（支持多个值，用逗号分隔）
local function parse_rule(rule_str, outbound)
    -- 检查是否包含逗号（多个值）
    if rule_str:find(",") then
        local parts = {}
        for part in (rule_str .. ","):gmatch("([^,]+),") do
            local trimmed = part:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(parts, parse_rule_single(trimmed, nil))
            end
        end
        if #parts == 1 then
            local rule = parts[1]
            rule.outbound = outbound
            return rule
        else
            return {
                type = "logical",
                mode = "or",
                rules = parts,
                outbound = outbound
            }
        end
    else
        return parse_rule_single(rule_str, outbound)
    end
end

function _M.generate(opts)
    opts = opts or {}
    local service = opts.service or {}

    -- 使用 clean_path 统一处理路径
    local work_dir = clean_path(service.work_dir, "/etc/nanoswift/run")
    local rules_path = clean_path(service.rules_path, "/etc/nanoswift/rules") .. "/"

    local config = get_template(work_dir, service.clash_secret, service.mixed_port)

    local tag_counter, tag_mapping, new_pool = {}, {}, {}
    for _, node in ipairs(opts.pool or {}) do
        if node and node.tag then
            local ot = node.tag; local c = tag_counter[ot] or 0; tag_counter[ot] = c + 1
            local nt = (c > 0) and (ot .. "(" .. c .. ")") or ot
            if not tag_mapping[ot] then tag_mapping[ot] = {} end; tag_mapping[ot][nt] = true
            local new_node = deep_copy(node); new_node.tag = nt; table.insert(new_pool, new_node)
        end
    end
    local function get_mapped_tag(ot)
        if ot == "direct" then return "direct" end
        if ot == "reject" then return "reject" end
        if tag_mapping[ot] then for nt, _ in pairs(tag_mapping[ot]) do return nt end end
        return ot
    end

    -- 添加 direct 和 reject 出站
    config.outbounds = {
        { type = "direct", tag = "direct" },
        { type = "block",  tag = "reject" }
    }
    for _, node in ipairs(new_pool) do table.insert(config.outbounds, node) end
    local all_node_tags = {}
    for _, node in ipairs(new_pool) do table.insert(all_node_tags, node.tag) end
    for _, g in ipairs(opts.groups or {}) do
        if g.tag ~= "自动选择" and g.tag ~= "漏网之鱼" then
            local m = {}
            for _, mem in ipairs(g.members or {}) do table.insert(m, get_mapped_tag(mem)) end
            table.insert(config.outbounds,
                { type = g.type, tag = g.tag, outbounds = m, interrupt_exist_connections = false })
        end
    end
    if #all_node_tags > 0 then
        table.insert(config.outbounds, { type = "urltest", tag = "自动选择", outbounds = deep_copy(all_node_tags) })
        local fo = deep_copy(all_node_tags); table.insert(fo, "direct"); table.insert(fo, "自动选择")
        table.insert(config.outbounds, { type = "selector", tag = "漏网之鱼", outbounds = fo, default = "自动选择" })
    end

    -- ============================================
    -- 扫描 UI 规则，查找电报规则的出口
    -- ============================================
    local telegram_outbound = "自动选择"
    for _, r in ipairs(opts.rules or {}) do
        if r.rule and r.outbound and r.outbound ~= "" and r.outbound ~= "自动选择" then
            if (r.rule_type or "srs") == "srs" then
                local rule_str = r.rule .. ","
                for part in rule_str:gmatch("([^,]+),") do
                    local t = part:match("^%s*(.-)%s*$")
                    if t then
                        local clean_t = t:gsub("%.srs$", "")
                        if clean_t == "geosite-telegram" or clean_t == "geoip-telegram" then
                            telegram_outbound = get_mapped_tag(r.outbound)
                            break
                        end
                    end
                end
            end
        end
    end

    -- ============================================
    -- 提前解析 UI 规则，分类提取 reject 规则
    -- ============================================
    local used_rule_sets = {}
    local direct_rules = {} -- 出站为 direct 的规则
    local reject_rules = {} -- 出站为 reject 的规则（需紧接在私有IP直连之后）
    local proxy_rules = {}  -- 出站为 proxy/节点组 的规则

    for _, r in ipairs(opts.rules or {}) do
        if r.rule and r.outbound ~= "" then
            local mapped_out = get_mapped_tag(r.outbound)
            local rule_type = r.rule_type or "srs"

            if rule_type == "ip" or rule_type == "port" or rule_type == "port_range"
                or rule_type == "domain_suffix" or rule_type == "domain_keyword" then
                local rule_obj = parse_rule(r.rule, mapped_out)
                if rule_obj then
                    if mapped_out == "reject" then
                        -- reject 规则：使用 action 而不是 outbound
                        if rule_obj.type == "logical" then
                            rule_obj.action = "reject"
                            rule_obj.outbound = nil
                        else
                            rule_obj.action = "reject"
                            rule_obj.outbound = nil
                        end
                        table.insert(reject_rules, rule_obj)
                    elseif mapped_out == "direct" then
                        table.insert(direct_rules, rule_obj)
                    else
                        -- 其他规则（proxy）
                        table.insert(proxy_rules, rule_obj)
                    end
                end
            elseif rule_type == "srs" then
                -- 记录使用的规则集
                for part in (r.rule .. ","):gmatch("([^,]+),") do
                    local t = part:match("^%s*(.-)%s*$")
                    if t and (t:match("^geosite%-") or t:match("^geoip%-")) then
                        used_rule_sets[t:gsub("%.srs$", "")] = true
                    end
                end

                local parts = {}
                for part in (r.rule .. ","):gmatch("([^,]+),") do
                    table.insert(parts, part:match("^%s*(.-)%s*$"))
                end

                local rule_obj
                if #parts == 1 then
                    rule_obj = parse_rule_single(parts[1], mapped_out)
                else
                    local sub = {}
                    for _, p in ipairs(parts) do
                        table.insert(sub, parse_rule_single(p, nil))
                    end
                    rule_obj = { type = "logical", mode = "or", rules = sub, outbound = mapped_out }
                end

                if mapped_out == "reject" then
                    rule_obj.action = "reject"
                    rule_obj.outbound = nil
                    table.insert(reject_rules, rule_obj)
                elseif mapped_out == "direct" then
                    table.insert(direct_rules, rule_obj)
                else
                    table.insert(proxy_rules, rule_obj)
                end
            end
        end
    end

    -- ============================================
    -- 构建路由规则（按顺序）
    -- ============================================
    local route_rules = config.route.rules

    -- 1. 固定置顶规则
    table.insert(route_rules, { action = "sniff" })
    table.insert(route_rules, {
        type = "logical",
        mode = "or",
        rules = { { protocol = "dns" }, { port = 53 } },
        action = "hijack-dns"
    })

    -- 2. UI reject 规则（紧接在私有IP直连之后）
    for _, rule in ipairs(reject_rules) do
        table.insert(route_rules, rule)
    end

    -- 3. 私有IP直连
    table.insert(route_rules, { ip_is_private = true, outbound = "direct" })

    -- 4. 电报规则
    table.insert(route_rules, {
        type = "logical",
        mode = "or",
        rules = {
            { rule_set = "geoip-telegram" },
            { rule_set = "geosite-telegram" }
        },
        outbound = telegram_outbound
    })

    -- 5. 固定拒绝规则
    table.insert(route_rules, {
        type = "logical",
        mode = "or",
        rules = {
            { port = 853 },
            { network = "udp",  port = 443 },
            { protocol = "stun" }
        },
        action = "reject"
    })

    -- 6. 国内直连规则
    table.insert(route_rules, {
        type = "logical",
        mode = "or",
        rules = {
            { rule_set = "geosite-geolocation-cn" },
            { rule_set = "geoip-cn" },
            { rule_set = "geosite-geolocation-!cn", invert = true },
            { rule_set = "geosite-chinatelecom" },
            { rule_set = "geosite-chinamobile" },
            { rule_set = "geosite-chinaunicom" }
        },
        outbound = "direct"
    })

    -- 7. UI direct 类规则
    for _, rule in ipairs(direct_rules) do
        table.insert(route_rules, rule)
    end

    -- 8. UI proxy 分流规则
    for _, rule in ipairs(proxy_rules) do
        table.insert(route_rules, rule)
    end

    -- 9. 最后的 outbound 规则
    table.insert(route_rules, {
        network = "tcp",
        rule_set = "geosite-geolocation-!cn",
        outbound = "漏网之鱼"
    })

    -- ============================================
    -- 收集使用的 rule_set
    -- ============================================
    local fixed = { "geosite-telegram", "geoip-telegram", "geosite-geolocation-cn", "geoip-cn",
        "geosite-geolocation-!cn", "geosite-chinatelecom", "geosite-chinamobile",
        "geosite-chinaunicom", "geosite-bytedance" }
    for _, tag in ipairs(fixed) do used_rule_sets[tag] = true end
    for _, tag in ipairs(get_predefined_rule_sets()) do used_rule_sets[tag] = true end
    for tag in pairs(used_rule_sets) do
        local sub = tag:find("geoip") and "geoip/" or "geosite/"
        table.insert(config.route.rule_set, { type = "local", tag = tag, path = rules_path .. sub .. tag .. ".srs" })
    end

    local lan_ip = get_lan_ip()
    local clash_port = service.clash_port or "9090"
    config.experimental.clash_api.external_controller = lan_ip .. ":" .. clash_port
    config.experimental.clash_api.access_control_allow_origin = { "http://127.0.0.1", "http://" .. lan_ip }
    return config
end

return _M
