local schema_name = "万象虎"
local software_name = rime_api.get_distribution_code_name()
local software_version = rime_api.get_distribution_version()

-- 初始化统计表
input_stats = input_stats or {
    daily = {count = 0, length = 0, fastest = 0, ts = 0},
    weekly = {count = 0, length = 0, fastest = 0, ts = 0},
    monthly = {count = 0, length = 0, fastest = 0, ts = 0},
    yearly = {count = 0, length = 0, fastest = 0, ts = 0},
    lengths = {},
    daily_max = 0,
    recent = {}
}

-- 时间计算函数
local function start_of_day(t)
    return os.time{year=t.year, month=t.month, day=t.day, hour=0}
end
local function start_of_week(t)
    local d = t.wday == 1 and 6 or (t.wday - 2)
    return os.time{year=t.year, month=t.month, day=t.day - d, hour=0}
end
local function start_of_month(t)
    return os.time{year=t.year, month=t.month, day=1, hour=0}
end
local function start_of_year(t)
    return os.time{year=t.year, month=1, day=1, hour=0}
end

-- 判断统计命令
local function is_summary_command(text)
    return text == "/rtj" or text == "/ztj" or text == "/ytj" or text == "/ntj" 
        or text == "/tj" or text == "/tjql" or text == "/st" or text == "/en"
end

-- 更新统计数据
local function update_stats(input_length)
    local now = os.date("*t")
    local now_ts = os.time(now)

    local day_ts = start_of_day(now)
    local week_ts = start_of_week(now)
    local month_ts = start_of_month(now)
    local year_ts = start_of_year(now)

    if input_stats.daily.ts ~= day_ts then
        input_stats.daily = {count = 0, length = 0, fastest = 0, ts = day_ts}
        input_stats.daily_max = 0
        input_stats.recent = {}
    end
    if input_stats.weekly.ts ~= week_ts then
        input_stats.weekly = {count = 0, length = 0, fastest = 0, ts = week_ts}
    end
    if input_stats.monthly.ts ~= month_ts then
        input_stats.monthly = {count = 0, length = 0, fastest = 0, ts = month_ts}
    end
    if input_stats.yearly.ts ~= year_ts then
        input_stats.yearly = {count = 0, length = 0, fastest = 0, ts = year_ts}
    end

    -- 更新统计记录
    local update = function(stat)
        stat.count = stat.count + 1
        stat.length = stat.length + input_length
    end
    update(input_stats.daily)
    update(input_stats.weekly)
    update(input_stats.monthly)
    update(input_stats.yearly)

    if input_length > input_stats.daily_max then
        input_stats.daily_max = input_length
    end

    input_stats.lengths[input_length] = (input_stats.lengths[input_length] or 0) + 1

    -- 最近一分钟统计
    local ts = os.time()
    table.insert(input_stats.recent, {ts = ts, len = input_length})
    local threshold = ts - 60
    local total = 0
    local i = 1
    while i <= #input_stats.recent do
        if input_stats.recent[i].ts >= threshold then
            total = total + input_stats.recent[i].len
            i = i + 1
        else
            table.remove(input_stats.recent, i)
        end
    end
    if total > input_stats.daily.fastest then input_stats.daily.fastest = total end
    if total > input_stats.weekly.fastest then input_stats.weekly.fastest = total end
    if total > input_stats.monthly.fastest then input_stats.monthly.fastest = total end
    if total > input_stats.yearly.fastest then input_stats.yearly.fastest = total end
end

-- 表序列化工具
table.serialize = function(tbl)
    local lines = {"{"}
    for k, v in pairs(tbl) do
        local key = (type(k) == "string") and ("[\"" .. k .. "\"]") or ("[" .. k .. "]")
        local val
        if type(v) == "table" then
            val = table.serialize(v)
        elseif type(v) == "string" then
            val = '"' .. v .. '"'
        else
            val = tostring(v)
        end
        table.insert(lines, string.format("    %s = %s,", key, val))
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

-- 保存统计到文件
local function save_stats()
    local path = rime_api.get_user_data_dir() .. "/lua/input_stats.lua"
    local file = io.open(path, "w")
    if not file then return end
    file:write("input_stats = " .. table.serialize(input_stats) .. "\n")
    file:close()
end

-- 日统计报告
local function format_daily_summary()
    local s = input_stats.daily
    if s.count == 0 then return "※ 今天没有任何记录。" end
    return string.format(
        "※ 今天的统计：\n%s\n◉ 今天\n共上屏[%d]次\n共输入[%d]字\n最快一分钟输入了[%d]字\n%s\n◉ 方案：%s\n◉ 平台：%s %s\n%s",
        string.rep("─", 14), s.count, s.length, s.fastest,
        string.rep("─", 14), schema_name, software_name, software_version,
        string.rep("─", 14))
end

-- 周统计报告
local function format_weekly_summary()
    local s = input_stats.weekly
    if s.count == 0 then return "※ 本周没有任何记录。" end
    return string.format(
        "※ 本周的统计：\n%s\n◉ 本周共上屏[%d]次\n共输入[%d]字\n最快一分钟输入了[%d]字\n周内单日最多一次输入[%d]字\n%s\n◉ 方案：%s\n◉ 平台：%s %s\n%s",
        string.rep("─", 14), s.count, s.length, s.fastest, input_stats.daily_max,
        string.rep("─", 14), schema_name, software_name, software_version,
        string.rep("─", 14))
end

-- 月统计报告
local function format_monthly_summary()
    local s = input_stats.monthly
    if s.count == 0 then return "※ 本月没有任何记录。" end
    return string.format(
        "※ 本月的统计：\n%s\n◉ 本月共上屏[%d]次\n共输入[%d]字\n最快一分钟输入了[%d]字\n%s\n◉ 方案：%s\n◉ 平台：%s %s\n%s",
        string.rep("─", 14), s.count, s.length, s.fastest,
        string.rep("─", 14), schema_name, software_name, software_version,
        string.rep("─", 14))
end

-- 年统计报告
local function format_yearly_summary()
    local s = input_stats.yearly
    if s.count == 0 then return "※ 本年没有任何记录。" end
    local length_counts = {}
    for length, count in pairs(input_stats.lengths) do
        table.insert(length_counts, {length = length, count = count})
    end
    table.sort(length_counts, function(a, b) return a.count > b.count end)
    local fav = length_counts[1] and length_counts[1].length or 0
    return string.format(
        "※ 本年的统计：\n%s\n◉ 本年共上屏[%d]次\n共输入[%d]字\n最快一分钟输入了[%d]字\n您最常输入长度为[%d]的词组\n%s\n◉ 方案：%s\n◉ 平台：%s %s\n%s",
        string.rep("─", 14), s.count, s.length, s.fastest, fav,
        string.rep("─", 14), schema_name, software_name, software_version,
        string.rep("─", 14))
end

-- 新增：临时统计报告（使用最后斜杠时间作为结束时间）
local function format_custom_summary(temp_stats)
    -- 确定结束时间：优先使用最后斜杠时间，若无则使用当前时间
    local end_ts = temp_stats.last_slash_time or os.time()
    local duration_sec = end_ts - temp_stats.start_time
    local minutes = duration_sec / 60
    
    -- 计算速度（字/分钟）
    local speed = 0
    if minutes > 0 then
        speed = math.floor((temp_stats.length / minutes) * 100) / 100  -- 保留两位小数
    end
    
    return string.format(
        "%s\n"..
        "◉ 开始时间：%s\n"..
        "◉ 结束时间：%s\n"..
        "◉ 统计时长：%d分 %d秒\n"..
        "◉ 输入条数：%d条\n"..
        "◉ 总字数：%d字\n"..
        "◉ 平均速度：%.2f 字/分钟\n"..
        "◉ 最快一分钟输入：%d字\n"..
        "%s\n",
        string.rep("─", 14),
        os.date("%Y-%m-%d %H:%M:%S", temp_stats.start_time),
        os.date("%Y-%m-%d %H:%M:%S", end_ts),
        math.floor(minutes), math.floor(duration_sec % 60),
        temp_stats.count,
        temp_stats.length,
        speed,
        temp_stats.fastest,
        string.rep("─", 14)
    )
end

-- 转换器：处理所有统计命令
local function translator(input, seg, env)
    if input:sub(1, 1) ~= "/" then return end
    local summary = ""
    
    -- 开始临时统计 - 设置标志但不立即开始
    if input == "/st" then
        -- 设置等待状态，确认上屏空内容后才真正开始
        env.pending_start = true
        yield(Candidate("info", seg.start, seg._end, "", ""))

    -- 结束临时统计并生成报告
    elseif input == "/en" then
        if env.is_collecting then
            env.is_collecting = false
            local report = format_custom_summary(env.temp_stats)
            yield(Candidate("stat", seg.start, seg._end, report, "input_stats_summary"))
        else
            yield(Candidate("stat", seg.start, seg._end, "※ 当前没有进行中的统计", ""))
        end

    -- 记录斜杠时间（仅当临时统计激活时记录）
    elseif env.is_collecting and input == "/" then
        -- 仅记录斜杠时间，不产生候选
        env.temp_stats.last_slash_time = os.time()
        yield(Candidate("info", seg.start, seg._end, "", ""))

    -- 其他统计命令
    else
        if input == "/rtj" then
            summary = format_daily_summary()
        elseif input == "/ztj" then
            summary = format_weekly_summary()
        elseif input == "/ytj" then
            summary = format_monthly_summary()
        elseif input == "/ntj" then
            summary = format_yearly_summary()
        elseif input == "/tj" then
            summary = format_daily_summary() .. "\n\n" .. format_weekly_summary() .. "\n\n" .. format_monthly_summary() .. "\n\n" .. format_yearly_summary()
        elseif input == "/tjql" then
            input_stats = {
                daily = {count = 0, length = 0, fastest = 0, ts = 0},
                weekly = {count = 0, length = 0, fastest = 0, ts = 0},
                monthly = {count = 0, length = 0, fastest = 0, ts = 0},
                yearly = {count = 0, length = 0, fastest = 0, ts = 0},
                lengths = {},
                daily_max = 0,
                recent = {}
            }
            save_stats()
            summary = "※ 所有统计数据已清空。"
        end

        if summary ~= "" then
            yield(Candidate("stat", seg.start, seg._end, summary, "input_stats_summary"))
        end
    end
end

-- 加载历史统计数据
local function load_stats_from_lua_file()
    local path = rime_api.get_user_data_dir() .. "/lua/input_stats.lua"
    local ok, result = pcall(function()
        local env = {}
        local f = loadfile(path, "t", env)
        if f then f() end
        return env.input_stats
    end)
    if ok and type(result) == "table" then
        input_stats = result
    else
        input_stats = {
            daily = {count = 0, length = 0, fastest = 0, ts = 0},
            weekly = {count = 0, length = 0, fastest = 0, ts = 0},
            monthly = {count = 0, length = 0, fastest = 0, ts = 0},
            yearly = {count = 0, length = 0, fastest = 0, ts = 0},
            lengths = {},
            daily_max = 0,
            recent = {}
        }
    end
end

local function init(env)
    local ctx = env.engine.context

    -- 初始化统计状态
    env.is_collecting = false
    env.pending_start = false
    env.temp_stats = nil

    -- 加载历史数据
    load_stats_from_lua_file()

    -- 注册提交通知回调
    ctx.commit_notifier:connect(function()
        local commit_text = ctx:get_commit_text()
        if not commit_text then return end

        -- 处理等待开始的状态（输入/st后上屏空内容）
        if env.pending_start and commit_text == "" then
            env.is_collecting = true
            env.temp_stats = {
                count = 0,
                length = 0,
                fastest = 0,
                recent = {},
                last_slash_time = nil,  -- 记录最后斜杠时间
                start_time = os.time()  -- 开始统计时间
            }
            env.pending_start = false
        end
        
        -- 重置等待状态（如果上屏的不是空内容）
        if env.pending_start and commit_text ~= "" then
            env.pending_start = false
        end
        
        -- 排除统计命令和报告内容
        if commit_text == "" or is_summary_command(commit_text) then return end
        local cand = ctx:get_selected_candidate()
        if cand and cand.comment == "input_stats_summary" then return end

        -- 计算输入长度
        local input_length = utf8.len(commit_text) or string.len(commit_text)

        -- 更新全局统计
        update_stats(input_length)
        save_stats()

        -- 更新临时统计（如果正在统计中）
        if env.is_collecting then            
            env.temp_stats.count = env.temp_stats.count + 1
            env.temp_stats.length = env.temp_stats.length + input_length

            -- 更新最近一分钟输入速度
            local ts = os.time()
            table.insert(env.temp_stats.recent, {ts = ts, len = input_length})
            local threshold = ts - 60
            local total = 0
            local i = 1
            while i <= #env.temp_stats.recent do
                if env.temp_stats.recent[i].ts >= threshold then
                    total = total + env.temp_stats.recent[i].len
                    i = i + 1
                else
                    table.remove(env.temp_stats.recent, i)
                end
            end
            if total > env.temp_stats.fastest then
                env.temp_stats.fastest = total
            end
        end
    end)
end

return { init = init, func = translator }
