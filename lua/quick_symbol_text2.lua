local function init(env)
    local config = env.engine.schema.config
    -- 静态配置读取
    local quick_text_pattern = config:get_string("recognizer/patterns/quick_text")
    env.double_symbol_trigger = quick_text_pattern 
                               and string.sub(quick_text_pattern, 2, 2) 
                               or "'"
    
    -- 预计算双符号触发字符串
    env.double_trigger_string = env.double_symbol_trigger .. env.double_symbol_trigger
    env.double_more_trigger = "'`"
    
    -- 直接创建填充好的循环缓冲区
    env.commit_history = {}
    for i = 1, 100 do 
        env.commit_history[i] = false  -- 使用false标记空槽位
    end
    env.history_index = 1  -- 从1开始更符合Lua习惯
    env.history_count = 0
    
    -- 异步事件监听
    env.update_notifier = env.engine.context.update_notifier:connect(function(ctx)
        local input = ctx.input
        -- 提前返回减少深层判断
        if #input ~= 2 then return end
        
        -- 1. 最新记录
        if input == env.double_trigger_string then
            -- 使用模运算替代条件判断
            local last_index = (env.history_index - 2) % 100 + 1
            if env.commit_history[last_index] then
                env.engine:commit_text(env.commit_history[last_index])
                ctx:clear()
            end
        
        -- 2. 历史记录
        elseif input == env.double_more_trigger and env.history_count > 0 then
            -- 避免中间table创建
            local output = {}
            local start_idx = env.history_index - env.history_count
            if start_idx < 1 then start_idx = start_idx + 100 end
            
            for i = 1, env.history_count do
                local idx = (start_idx + i - 2) % 100 + 1
                output[i] = env.commit_history[idx]
            end
            
            env.engine:commit_text(table.concat(output))
            ctx:clear()
        end
    end)
    
    -- 提交通知器（使用直接索引赋值）
    env.commit_notifier = env.engine.context.commit_notifier:connect(function(ctx)
        local text = ctx:get_commit_text()
        if text == "" then return end
        
        env.commit_history[env.history_index] = text
        env.history_index = env.history_index % 100 + 1
        env.history_count = math.min(env.history_count + 1, 100)
    end)
end

local function fini(env)
    if env.update_notifier then env.update_notifier:disconnect() end
    if env.commit_notifier then env.commit_notifier:disconnect() end
end

    -- 处理器
local function processor(key_event, env)
    return #env.engine.context.input == 2
end

return { init = init, fini = fini, func = processor }