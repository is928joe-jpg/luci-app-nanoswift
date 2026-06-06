-- /usr/lib/lua/luci/controller/nanoswift.lua

module("luci.controller.nanoswift", package.seeall)

local json           = require "luci.jsonc"
local sys            = require "luci.sys"
local fs             = require "nixio.fs"

local CONF_FILE      = "/etc/nanoswift/configure.json"
local POOL_FILE      = "/etc/nanoswift/profile/proxies.json"
local SRC_RULES_FILE = "/etc/nanoswift/config/rules.txt"
local STATIC_DIR     = "/etc/nanoswift/static"

-- 统一的路径清理函数
local function clean_path(path, default)
    if not path or path == "" then
        return default
    end
    -- 去除首尾空格
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    -- 去除末尾斜杠
    path = path:gsub("/+$", "")
    return path
end

-- ============================================================
--  WS-TLS 加速节点替换函数
-- ============================================================
local function apply_wstls_accel(pool, conf)
    -- 只有当 wstls_accel 为 true 时才进行替换
    if not conf.service or not conf.service.wstls_accel then
        return false
    end

    -- 获取 cfnat-addr 配置
    local uci = require "luci.model.uci".cursor()
    local cfnat_addr = uci:get("cfnat", "main", "addr") or "0.0.0.0:2345"
    
    -- 解析 IP 和端口，格式 "IP:PORT"
    local cfnat_ip, cfnat_port = cfnat_addr:match("^([^:]+):(%d+)$")
    if not cfnat_ip or not cfnat_port then
        return false
    end
    cfnat_port = tonumber(cfnat_port)

    -- 获取 wstls_accel_select 的值，默认 0
    local accel_select = tonumber(conf.service.wstls_accel_select) or 0

    -- 新端口 = cfnat 端口 + accel_select
    local new_port = cfnat_port + accel_select

    -- 遍历所有 outbounds，替换符合条件的节点
    local replaced_count = 0
    for _, outbound in ipairs(pool.outbounds or {}) do
        -- 检查是否为 vless + ws + tls 节点
        if outbound.type == "vless" 
            and outbound.tls 
            and outbound.tls.enabled == true 
            and outbound.transport 
            and outbound.transport.type == "ws" then
            
            -- 保存原始信息（如果需要的话，可以加个 orig_server 字段）
            -- outbound.orig_server = outbound.server
            -- outbound.orig_server_port = outbound.server_port
            
            -- 执行替换
            outbound.server = cfnat_ip
            outbound.server_port = new_port
            replaced_count = replaced_count + 1
        end
    end

    return replaced_count > 0
end

function index()
    entry({ "admin", "services", "nanoswift" }, template("nanoswift/index"), _("Nanoswift"), 10)
    entry({ "admin", "services", "nanoswift", "service_settings_get" }, call("service_settings_get"))
    entry({ "admin", "services", "nanoswift", "service_settings_set" }, call("service_settings_set"))
    entry({ "admin", "services", "nanoswift", "proxies_get" }, call("proxies_get"))
    entry({ "admin", "services", "nanoswift", "proxies_set" }, call("proxies_set"))
    entry({ "admin", "services", "nanoswift", "update_proxies" }, call("update_proxies"))
    entry({ "admin", "services", "nanoswift", "proxy_tags" }, call("proxy_tags"))
    entry({ "admin", "services", "nanoswift", "proxies_remove" }, call("proxies_remove"))
    entry({ "admin", "services", "nanoswift", "groups_get" }, call("groups_get"))
    entry({ "admin", "services", "nanoswift", "groups_set" }, call("groups_set"))
    entry({ "admin", "services", "nanoswift", "config_rules_get" }, call("config_rules_get"))
    entry({ "admin", "services", "nanoswift", "rules_ui_get" }, call("rules_ui_get"))
    entry({ "admin", "services", "nanoswift", "rules_ui_set" }, call("rules_ui_set"))
    entry({ "admin", "services", "nanoswift", "generate" }, call("action_generate"))
    entry({ "admin", "services", "nanoswift", "service_control" }, call("service_control"))
    entry({ "admin", "services", "nanoswift", "singbox_status" }, call("singbox_status"))
    entry({ "admin", "services", "nanoswift", "cfnat_settings_get" }, call("cfnat_settings_get"))
    entry({ "admin", "services", "nanoswift", "cfnat_settings_set" }, call("cfnat_settings_set"))
    entry({ "admin", "services", "nanoswift", "config_backup_download" }, call("config_backup_download"))
    entry({ "admin", "services", "nanoswift", "config_backup_restore" }, call("config_backup_restore"))
end

local function load_conf()
    local txt = fs.readfile(CONF_FILE)
    local data = txt and json.parse(txt)
    if not data then
        data = {
            service = {
                enabled = false,
                delay = 10,
                rules_path = "/etc/nanoswift/rules/",
                work_dir = "/etc/nanoswift/run",
                singbox_bin = "/usr/bin/sing-box",
                srs_bin = "/usr/bin/srs",
                clash_secret = "123456",
                clash_port = "9090",
                mixed_port = "1080",
                srs_update_enabled = false,
                srs_cron = "1 5 */2 * *",
                wstls_accel = false,
                wstls_accel_select = "0"
            },
            subscriptions = { clash = {}, v2ray = {}, singbox_nodes = "" },
            groups = {},
            rules = {}
        }
    end
    if not data.service then data.service = {} end
    data.service.enabled = (data.service.enabled == true)
    data.service.delay = data.service.delay or 10
    data.service.rules_path = clean_path(data.service.rules_path, "/etc/nanoswift/rules") .. "/"
    data.service.work_dir = clean_path(data.service.work_dir, "/etc/nanoswift/run")
    data.service.singbox_bin = clean_path(data.service.singbox_bin, "/usr/bin/sing-box")
    data.service.srs_bin = clean_path(data.service.srs_bin, "/usr/bin/srs")
    data.service.clash_secret = data.service.clash_secret or "123456"
    data.service.clash_port = data.service.clash_port or "9090"
    data.service.mixed_port = data.service.mixed_port or "1080"
    data.service.srs_update_enabled = (data.service.srs_update_enabled == true)
    data.service.srs_cron = data.service.srs_cron or "1 5 */2 * *"
    data.service.wstls_accel = (data.service.wstls_accel == true)
    data.service.wstls_accel_select = data.service.wstls_accel_select or "0"

    if not data.subscriptions then data.subscriptions = { clash = {}, v2ray = {}, singbox_nodes = "" } end
    if not data.subscriptions.singbox_nodes then data.subscriptions.singbox_nodes = "" end
    if not data.groups then data.groups = {} end
    if not data.rules then data.rules = {} end
    return data
end

local function save_conf(conf)
    fs.writefile(CONF_FILE, json.stringify(conf, true))
end

-- ============================================================
--  SRS Cron 任务管理 
-- ============================================================
local function update_srs_cron(enabled, cron_expr, rules_path, srs_bin)
    local cron_file = "/etc/crontabs/root"
    local rules_file = "/etc/nanoswift/config/rules.txt"

    local srs_cmd = clean_path(srs_bin, "/usr/bin/srs")
    local output_path = clean_path(rules_path, "/etc/nanoswift/rules")

    local target_line = string.format("%s %s -o %s -i %s",
        cron_expr or "1 5 */2 * *", srs_cmd, output_path, rules_file)

    local content = ""
    if fs.access(cron_file) then
        content = fs.readfile(cron_file) or ""
    end

    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        if not line:match(srs_cmd) then
            table.insert(lines, line)
        end
    end

    if enabled then
        table.insert(lines, target_line)
    end

    local new_content = table.concat(lines, "\n") .. "\n"
    fs.writefile(cron_file, new_content)

    os.execute("/etc/init.d/cron reload 2>/dev/null")
end

-- ============================================================
--  UCI 配置管理 sing-box 服务
-- ============================================================
local function configure_singbox_uci(conf)
    local work_dir = conf.service.work_dir or "/etc/nanoswift/run"
    local conffile = "/etc/nanoswift/run/config.json"
    local delay = conf.service.delay or 10

    os.execute("uci set sing-box.main.workdir='" .. work_dir .. "'")
    os.execute("uci set sing-box.main.conffile='" .. conffile .. "'")
    os.execute("uci set sing-box.main.delay='" .. delay .. "'")
    os.execute("uci commit sing-box")
end

local function enable_singbox_service(enabled)
    if enabled then
        os.execute("uci set sing-box.main.enabled='1'")
        os.execute("uci commit sing-box")
        os.execute("/etc/init.d/sing-box enable 2>/dev/null")
        os.execute("/etc/init.d/sing-box restart 2>/dev/null")
    else
        os.execute("uci set sing-box.main.enabled='0'")
        os.execute("uci commit sing-box")
        os.execute("/etc/init.d/sing-box stop 2>/dev/null")
        os.execute("/etc/init.d/sing-box disable 2>/dev/null")
    end
end

-- ============================================================
--  基础辅助逻辑
-- ============================================================
local function load_pool()
    local txt = fs.readfile(POOL_FILE)
    return txt and json.parse(txt) or { outbounds = {} }
end

local function save_pool(pool)
    fs.writefile(POOL_FILE, json.stringify(pool, true))
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function pool_tags(pool)
    local tags = {}
    for _, o in ipairs((pool or {}).outbounds or {}) do
        if o and o.tag then tags[o.tag] = json.stringify(o) end
    end
    return tags
end

local function purge_removed(conf, removed_tags)
    local result = { groups = 0, members = 0, rules = 0 }
    for _, g in ipairs(conf.groups or {}) do
        if g and g.members then
            local members, changed = {}, false
            for _, m in ipairs(g.members) do
                if removed_tags[m] then
                    changed = true; result.members = result.members + 1
                else
                    table.insert(members, m)
                end
            end
            if changed then
                result.groups = result.groups + 1; g.members = members
            end
        end
    end
    for _, r in ipairs(conf.rules or {}) do
        if r and r.outbound and r.outbound ~= "" and removed_tags[r.outbound] then
            r.outbound = ""; result.rules = result.rules + 1
        end
    end
    return conf, result
end

-- ============================================================
--  核心 API 实现
-- ============================================================
function service_settings_get()
    luci.http.prepare_content("application/json")
    luci.http.write_json(load_conf().service)
end

function service_settings_set()
    local data = json.parse(luci.http.content())
    local conf = load_conf()

    -- 清理所有路径
    local work_dir = clean_path(data.work_dir, "/etc/nanoswift/run")
    local rules_path = clean_path(data.rules_path, "/etc/nanoswift/rules") .. "/"
    local singbox_bin = clean_path(data.singbox_bin, "/usr/bin/sing-box")
    local srs_bin = clean_path(data.srs_bin, "/usr/bin/srs")

    conf.service = {
        enabled = data.enabled == true,
        delay = tonumber(data.delay) or 10,
        rules_path = rules_path,
        work_dir = work_dir,
        singbox_bin = singbox_bin,
        srs_bin = srs_bin,
        clash_secret = data.clash_secret or "123456",
        clash_port = data.clash_port or "9090",
        mixed_port = data.mixed_port or "1080",
        srs_update_enabled = data.srs_update_enabled == true,
        srs_cron = data.srs_cron or "1 5 */2 * *",
        wstls_accel = (data.wstls_accel == true),
        wstls_accel_select = data.wstls_accel_select or "0"
    }
    save_conf(conf)

    -- 管理 SRS 更新 cron 任务
    update_srs_cron(
        conf.service.srs_update_enabled,
        conf.service.srs_cron,
        conf.service.rules_path,
        conf.service.srs_bin
    )

    -- 配置 sing-box 服务
    if conf.service.enabled then
        configure_singbox_uci(conf)
        enable_singbox_service(true)
    else
        enable_singbox_service(false)
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({ ok = true })
end

function update_proxies()
    local ok, result = pcall(function()
        local conf = load_conf()
        local old_pool = load_pool()
        local old_tags = pool_tags(old_pool)
        local all_outbounds = {}
        local tmp_file = "/tmp/ns_conv.json"
        local convert_bin = "/usr/bin/convert"

        local function run_convert(val, format, is_url)
            if not val or val == "" then return end
            local flag = is_url and "-r" or "-u"
            local cmd = string.format("%s %s %q -f %s -o %s 2>/dev/null", convert_bin, flag, val, format, tmp_file)
            sys.call(cmd)
            local txt = fs.readfile(tmp_file)
            if txt then
                local res = json.parse(txt)
                if res and res.outbounds then
                    for _, o in ipairs(res.outbounds) do table.insert(all_outbounds, o) end
                end
            end
            fs.unlink(tmp_file)
        end

        for _, u in ipairs(conf.subscriptions.clash or {}) do run_convert(u, "clash", true) end
        for _, s in ipairs(conf.subscriptions.v2ray or {}) do run_convert(s, "v2ray", s:match("^https?://") ~= nil) end

        -- singbox_nodes 添加入节点池
        if conf.subscriptions.singbox_nodes and conf.subscriptions.singbox_nodes ~= "" then
            local ok_sb, node_data = pcall(json.parse, conf.subscriptions.singbox_nodes)
            if ok_sb and node_data and node_data.outbounds then
                for _, node in ipairs(node_data.outbounds) do
                    table.insert(all_outbounds, node)
                end
            end
        end

        -- 处理 static 目录下的静态节点文件
        local singbox_bin = conf.service.singbox_bin or "/usr/bin/sing-box"
        local static_merged = "/tmp/statics.json"
        if not fs.access(STATIC_DIR) then
            fs.mkdir(STATIC_DIR)
        end
        if fs.access(STATIC_DIR) then
            local has_json = false
            for fname in fs.dir(STATIC_DIR) do
                if fname:match("%.json$") then
                    has_json = true
                    break
                end
            end
            if has_json then
                local merge_cmd = string.format("%s merge %s -C %s 2>&1", singbox_bin, static_merged, STATIC_DIR)
                local handle = io.popen(merge_cmd)
                local merge_output = handle:read("*a") or ""
                handle:close()
                if merge_output:match("FATAL") then
                    fs.unlink(static_merged)
                    error("\nstatic 目录节点合并失败: " .. merge_output)
                end
                if fs.access(static_merged) then
                    local merged_txt = fs.readfile(static_merged)
                    if merged_txt then
                        local ok_merged, merged_data = pcall(json.parse, merged_txt)
                        if ok_merged and merged_data and merged_data.outbounds and #merged_data.outbounds > 0 then
                            for _, node in ipairs(merged_data.outbounds) do
                                table.insert(all_outbounds, node)
                            end
                        end
                    end
                    fs.unlink(static_merged)
                end
            end
        end

        local new_pool = { outbounds = all_outbounds }
        local new_tags = pool_tags(new_pool)
        local added, removed, kept, changed = {}, {}, {}, {}
        for tag, fp in pairs(new_tags) do
            if old_tags[tag] then
                if old_tags[tag] == fp then kept[tag] = 1 else changed[tag] = 1 end
            else
                added[tag] = 1
            end
        end
        for tag in pairs(old_tags) do if not new_tags[tag] then removed[tag] = 1 end end

        local purge_result = { groups = 0, members = 0, rules = 0 }
        if count(removed) > 0 then conf, purge_result = purge_removed(conf, removed) end

        save_pool(new_pool); save_conf(conf)

        return {
            msg = string.format("新增:%d 保留:%d 变更:%d 删除:%d | 清理组:%d 成员:%d 规则:%d",
                count(added), count(kept), count(changed), count(removed),
                purge_result.groups, purge_result.members, purge_result.rules),
            added = count(added),
            removed = count(removed),
            changed = count(changed),
            kept = count(kept),
            purge = purge_result
        }
    end)
    luci.http.prepare_content("application/json")
    luci.http.write_json(ok and result or { msg = "更新失败: " .. tostring(result), error = true })
end

function action_generate()
    local success, result = pcall(function()
        local conf = load_conf()
        local pool = load_pool()

        -- ========== 在生成配置时应用 WS-TLS 加速节点替换 ==========
        local accel_applied = apply_wstls_accel(pool, conf)

        -- 确保 work_dir 正确传递给 gen.generate
        local gen = require "nanoswift.gen"
        local final = gen.generate({
            service = conf.service,
            groups = conf.groups,
            rules = conf.rules,
            pool = pool.outbounds or {}
        })

        -- config.json
        local config_path = "/etc/nanoswift/run/config.json"

        -- 确保目录存在
        local config_dir = "/etc/nanoswift/run"
        if not fs.access(config_dir) then
            fs.mkdir(config_dir)
        end

        fs.writefile(config_path, json.stringify(final, true))

        local sb_bin = conf.service.singbox_bin or "/usr/bin/sing-box"
        os.execute(string.format("%s format -c %s -w 2>/dev/null", sb_bin, config_path))
        local check_cmd = string.format("%s check -c %s 2>&1", sb_bin, config_path)
        local check_handle = io.popen(check_cmd)
        local check_output = check_handle:read("*a") or ""
        check_handle:close()
        if check_output:match("FATAL%[") then
            error("\n配置检查失败: " .. check_output)
        end

        -- 生成配置后，如果服务已启用，重启 sing-box
        if conf.service.enabled then
            configure_singbox_uci(conf)
            os.execute("/etc/init.d/sing-box restart 2>/dev/null")
        end

        local accel_msg = ""
        if accel_applied then
            accel_msg = "，已应用 WS-TLS 加速节点替换"
        end

        return { ok = true, msg = "配置已重新生成，核心配置已重载" .. accel_msg }
    end)
    luci.http.prepare_content("application/json")
    luci.http.write_json(success and result or { ok = false, msg = tostring(result) })
end

function proxies_get()
    luci.http.prepare_content("application/json")
    local conf = load_conf()
    luci.http.write_json({
        clash = conf.subscriptions.clash or {},
        v2ray = conf.subscriptions.v2ray or {},
        singbox_nodes = conf.subscriptions.singbox_nodes or ""
    })
end

function proxies_set()
    local data = json.parse(luci.http.content())
    local conf = load_conf()
    conf.subscriptions = {
        clash = data.clash or {},
        v2ray = data.v2ray or {},
        singbox_nodes = data.singbox_nodes or ""
    }
    save_conf(conf)
    luci.http.prepare_content("application/json")
    luci.http.write_json({ ok = true })
end

function proxy_tags()
    local pool = load_pool()
    local tags = {}
    for _, o in ipairs(pool.outbounds or {}) do if o.tag then table.insert(tags, o.tag) end end
    luci.http.prepare_content("application/json")
    luci.http.write_json({ tags = tags })
end

function proxies_remove()
    local data = json.parse(luci.http.content())
    local rm = {}
    for _, t in ipairs(data.tags or {}) do rm[t] = true end
    local pool = load_pool()
    local new_o = {}
    for _, o in ipairs(pool.outbounds or {}) do if not rm[o.tag] then table.insert(new_o, o) end end
    pool.outbounds = new_o; save_pool(pool)
    local conf = load_conf(); local purge_result; conf, purge_result = purge_removed(conf, rm); save_conf(conf)
    luci.http.prepare_content("application/json")
    luci.http.write_json({ ok = true, msg = "已移除并清理" })
end

function groups_get()
    luci.http.prepare_content("application/json")
    luci.http.write_json({ groups = load_conf().groups or {} })
end

function groups_set()
    local data = json.parse(luci.http.content())
    local conf = load_conf(); conf.groups = data.groups or {}; save_conf(conf)
    luci.http.prepare_content("application/json")
    luci.http.write_json({ ok = true })
end

function rules_ui_get()
    luci.http.prepare_content("application/json")
    luci.http.write_json({ rules = load_conf().rules or {} })
end

function rules_ui_set()
    local data = json.parse(luci.http.content())
    local conf = load_conf(); conf.rules = data.rules or {}; save_conf(conf)
    luci.http.prepare_content("application/json")
    luci.http.write_json({ ok = true })
end

function config_rules_get()
    local lines = {}
    local f = io.open(SRC_RULES_FILE, "r")
    if f then
        for line in f:lines() do
            line = line:gsub("^%s*(.-)%s*$", "%1")
            if line ~= "" and not line:match("^#") then table.insert(lines, line) end
        end
        f:close()
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({ lines = lines })
end

function service_control()
    local data = json.parse(luci.http.content())
    if data and data.action then
        sys.call("/etc/init.d/sing-box " .. data.action .. " 2>/dev/null")
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({ ok = true })
end

-- ============================================================
--  配置备份下载
-- ============================================================
function config_backup_download()
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = string.format("nanoswift_backup_%s.tar.gz", timestamp)
    local tmp_tar = "/tmp/" .. filename

    -- 确保目录存在
    if not fs.access(STATIC_DIR) then
        fs.mkdir(STATIC_DIR)
    end
    local profile_dir = "/etc/nanoswift/profile"
    if not fs.access(profile_dir) then
        fs.mkdir(profile_dir)
    end
    local run_dir = "/etc/nanoswift/run"
    if not fs.access(run_dir) then
        fs.mkdir(run_dir)
    end

    -- 打包 configure.json、static 目录、proxies.json、config.json
    local cmd = string.format(
        "cd /etc/nanoswift && tar -czf %s configure.json static/ profile/proxies.json run/config.json 2>/dev/null",
        tmp_tar
    )
    local ret = os.execute(cmd)
    if ret ~= 0 then
        luci.http.prepare_content("application/json")
        luci.http.write_json({ ok = false, msg = "打包失败" })
        return
    end

    -- 读取 tar 文件并发送
    local f = io.open(tmp_tar, "rb")
    if not f then
        luci.http.prepare_content("application/json")
        luci.http.write_json({ ok = false, msg = "无法读取备份文件" })
        return
    end

    local data = f:read("*a")
    f:close()
    os.remove(tmp_tar)

    luci.http.header("Content-Disposition", string.format('attachment; filename="%s"', filename))
    luci.http.header("Content-Type", "application/gzip")
    luci.http.header("Content-Length", tostring(#data))
    luci.http.write(data)
end

-- ============================================================
--  配置备份恢复
-- ============================================================
function config_backup_restore()
    local tmp_upload = "/tmp/ns_restore_upload.tar.gz"
    local tmp_extract = "/tmp/ns_restore_extract"

    -- 清理旧文件
    os.remove(tmp_upload)
    os.execute("rm -rf " .. tmp_extract)

    -- 直接从标准输入读取原始 POST 数据
    local raw_body = io.stdin:read("*a")

    if not raw_body or #raw_body == 0 then
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("未收到任何数据。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end

    -- 获取 boundary
    local content_type = luci.http.getenv("CONTENT_TYPE") or os.getenv("CONTENT_TYPE") or ""
    local boundary = content_type:match("boundary=(.+)")

    if not boundary then
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("无法解析上传数据格式。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end

    -- 手动提取文件内容
    local boundary_marker = "--" .. boundary
    local file_content = nil

    -- 查找文件部分
    local start_pos = raw_body:find(boundary_marker, 1, true)
    if start_pos then
        -- 跳到下一行
        local line_end = raw_body:find("\r\n", start_pos, true)
        if line_end then
            local headers_start = line_end + 2

            -- 查找双换行（头部结束）
            local body_start = raw_body:find("\r\n\r\n", headers_start, true)
            if body_start then
                body_start = body_start + 4

                -- 查找下一个 boundary
                local next_boundary = raw_body:find("\r\n" .. boundary_marker, body_start, true)
                if next_boundary then
                    file_content = raw_body:sub(body_start, next_boundary - 1)
                end
            end
        end
    end

    if not file_content or #file_content < 10 then
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("无法提取文件内容，数据长度：" + ]] .. tostring(#raw_body) .. [[ + "。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end

    -- 保存文件
    local f = io.open(tmp_upload, "wb")
    if not f then
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("无法创建临时文件。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end
    f:write(file_content)
    f:close()

    -- 验证是否为有效的 tar.gz 文件
    local check_ret = os.execute(string.format("tar -tzf %s >/dev/null 2>&1", tmp_upload))
    if check_ret ~= 0 then
        os.remove(tmp_upload)
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("上传的文件不是有效的 tar.gz 格式。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end

    -- 创建临时解压目录
    os.execute("mkdir -p " .. tmp_extract)

    -- 解压 tar 包
    local ret = os.execute(string.format("tar -xzf %s -C %s 2>/dev/null", tmp_upload, tmp_extract))
    if ret ~= 0 then
        os.remove(tmp_upload)
        os.execute("rm -rf " .. tmp_extract)
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("解压失败，备份文件可能已损坏。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end

    -- 检查解压后的文件结构
    if not fs.access(tmp_extract .. "/configure.json") then
        os.execute("rm -rf " .. tmp_extract)
        os.remove(tmp_upload)
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("备份文件缺少 configure.json。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end

    -- 1. 覆盖 configure.json
    local conf_data = fs.readfile(tmp_extract .. "/configure.json")
    if not conf_data then
        os.execute("rm -rf " .. tmp_extract)
        os.remove(tmp_upload)
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("无法读取备份中的 configure.json。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end

    -- 验证 JSON 格式
    local ok_json = pcall(json.parse, conf_data)
    if not ok_json then
        os.execute("rm -rf " .. tmp_extract)
        os.remove(tmp_upload)
        luci.http.header("Content-Type", "text/html; charset=utf-8")
        luci.http.write([[
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>错误</title>
<script>alert("备份中的 configure.json 格式无效。");window.history.back();</script>
</head><body></body></html>
        ]])
        return
    end

    -- 写入配置文件
    fs.writefile(CONF_FILE, conf_data)

    -- 2. 清空并恢复 static 目录
    if fs.access(STATIC_DIR) then
        os.execute("rm -rf " .. STATIC_DIR .. "/*")
    else
        fs.mkdir(STATIC_DIR)
    end

    local static_src = tmp_extract .. "/static"
    if fs.access(static_src) and fs.stat(static_src, "type") == "dir" then
        os.execute(string.format("cp -a %s/* %s/ 2>/dev/null", static_src, STATIC_DIR))
    end

    -- 3. 恢复 profile/proxies.json
    local proxies_src = tmp_extract .. "/profile/proxies.json"
    if fs.access(proxies_src) then
        local profile_dir = "/etc/nanoswift/profile"
        if not fs.access(profile_dir) then
            fs.mkdir(profile_dir)
        end
        os.execute(string.format("cp -f %s %s/ 2>/dev/null", proxies_src, profile_dir))
    end

    -- 4. 恢复 run/config.json
    local config_src = tmp_extract .. "/run/config.json"
    if fs.access(config_src) then
        local run_dir = "/etc/nanoswift/run"
        if not fs.access(run_dir) then
            fs.mkdir(run_dir)
        end
        os.execute(string.format("cp -f %s %s/ 2>/dev/null", config_src, run_dir))
    end
    
    -- 清理临时文件    os.execute("rm -rf " .. tmp_extract)
    os.remove(tmp_upload)

    -- 返回成功的 HTML 响应
    luci.http.header("Content-Type", "text/html; charset=utf-8")
    luci.http.write([[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>备份恢复成功</title>
<script>
alert("配置恢复成功");
window.location.href = "/cgi-bin/luci/admin/services/nanoswift";
</script>
</head>
<body></body>
</html>
    ]])
end

-- ============================================================
--  CFNAT UCI 配置管理
-- ============================================================
function cfnat_settings_get()
    local uci = require "luci.model.uci".cursor()
    local data = {}

    data.enabled = uci:get("cfnat", "main", "enabled") or "0"
    data.addr = uci:get("cfnat", "main", "addr") or "0.0.0.0:2345"
    data.colo = string.upper(uci:get("cfnat", "main", "colo") or "NRT")
    data.delay = uci:get("cfnat", "main", "delay") or "300"
    data.ipnum = uci:get("cfnat", "main", "ipnum") or "20"
    data.ips = uci:get("cfnat", "main", "ips") or "4"
    data.ipstart = uci:get("cfnat", "main", "ipstart") or ""
    data.log_level = uci:get("cfnat", "main", "log_level") or "info"
    data.num = uci:get("cfnat", "main", "num") or "5"
    data.port = uci:get("cfnat", "main", "port") or "443"
    data.http_port = uci:get("cfnat", "main", "http_port") or "80"
    data.random = uci:get("cfnat", "main", "random") or "true"
    data.baidu_proxy = uci:get("cfnat", "main", "baidu_proxy") or "false"
    data.task = uci:get("cfnat", "main", "task") or "300"
    data.carrier_listens = uci:get("cfnat", "main", "carrier_listens") or ""
    data.workdir = uci:get("cfnat", "main", "workdir") or "/etc/nanoswift/run"

    -- 检查服务运行状态
    local pid = sys.call("pgrep cfnat >/dev/null 2>&1")
    data.running = (pid == 0)

    luci.http.prepare_content("application/json")
    luci.http.write_json(data)
end

function cfnat_settings_set()
    local data = json.parse(luci.http.content())
    local uci = require "luci.model.uci".cursor()
    local enabled = (data.enabled == true or data.enabled == "1" or data.enabled == "true")

    uci:set("cfnat", "main", "enabled", enabled and "1" or "0")
    uci:set("cfnat", "main", "addr", data.addr or "0.0.0.0:2345")
    uci:set("cfnat", "main", "colo", string.upper(data.colo or "NRT"))
    uci:set("cfnat", "main", "delay", data.delay or "300")
    uci:set("cfnat", "main", "ipnum", data.ipnum or "20")
    uci:set("cfnat", "main", "ips", data.ips or "4")
    uci:set("cfnat", "main", "ipstart", data.ipstart or "")
    uci:set("cfnat", "main", "log_level", data.log_level or "info")
    uci:set("cfnat", "main", "num", data.num or "5")
    uci:set("cfnat", "main", "port", data.port or "443")
    uci:set("cfnat", "main", "http_port", data.http_port or "80")
    uci:set("cfnat", "main", "random", (data.random == true or data.random == "true") and "true" or "false")
    uci:set("cfnat", "main", "baidu_proxy",
        (data.baidu_proxy == true or data.baidu_proxy == "true") and "true" or "false")
    uci:set("cfnat", "main", "task", data.task or "300")
    uci:set("cfnat", "main", "carrier_listens", data.carrier_listens or "")
    uci:set("cfnat", "main", "workdir", data.workdir or "/etc/nanoswift/run")

    uci:commit("cfnat")

    -- 根据启用状态控制服务
    if enabled then
        os.execute("uci set cfnat.main.enabled='1'")
        os.execute("uci commit cfnat")
        os.execute("/etc/init.d/cfnat enable 2>/dev/null")
        os.execute("/etc/init.d/cfnat restart 2>/dev/null")
    else
        os.execute("uci set cfnat.main.enabled='0'")
        os.execute("uci commit cfnat")
        os.execute("/etc/init.d/cfnat stop 2>/dev/null")
        os.execute("/etc/init.d/cfnat disable 2>/dev/null")
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({ ok = true })
end

-- ============================================================
--  Sing-Box 服务状态检查
-- ============================================================
function singbox_status()
    local running = false

    local handle = io.popen("/etc/init.d/sing-box status 2>/dev/null")
    if handle then
        local status_output = handle:read("*a") or ""
        handle:close()
        if status_output:match("running") then
            running = true
        end
    end

    if not running then
        local pid = sys.call("pgrep -f 'sing-box' >/dev/null 2>&1")
        running = (pid == 0)
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({
        running = running,
        status = running and "running" or "stopped"
    })
end