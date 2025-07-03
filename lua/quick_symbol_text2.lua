-- 初始化符号输入的状态
local function init(env)
    local config = env.engine.schema.config
    -- 静态配置读取优化
    env.double_symbol_trigger = config:get_string("recognizer/patterns/quick_text") 
                               and string.sub(config:get_string("recognizer/patterns/quick_text"), 2, 2) 
                               or "'"
    env.double_more_trigger = "'`"
    
    -- 循环缓冲区实现
    env.commit_history = {}
    for i = 1, 100 do env.commit_history[i] = "" end  -- 预分配
    env.history_index = 0    -- 当前写入位置（从0开始便于计算）
    env.history_count = 0    -- 实际存储数量
    
    -- 提交通知器
    env.engine.context.commit_notifier:connect(function(ctx)
        local commit_text = ctx:get_commit_text()
        if commit_text == "" then return end
        
        -- 更新循环缓冲区（自动覆盖最旧记录）
        env.history_index = (env.history_index % 100) + 1
        env.commit_history[env.history_index] = commit_text
        env.history_count = math.min(env.history_count + 1, 100)
    end)
end

local function processor(key_event, env)
    local context = env.engine.context
    local input = context.input
    
    -- 快速长度检查
    if #input ~= 2 then return end
    
    -- 双符号触发（最新内容）
    if input == env.double_symbol_trigger .. env.double_symbol_trigger then
        if env.history_index > 0 then
            env.engine:commit_text(env.commit_history[env.history_index])
            context:clear()
            return 1
        end
    
    -- 历史记录触发
    elseif input == env.double_more_trigger and env.history_count > 0 then
        local buffer = env.text_buffer or {}
        local valid_count = 0
        
        -- 从旧到新遍历
        local oldest_index = (env.history_index - env.history_count) % 100
        for i = 1, env.history_count do
            local pos = (oldest_index + i - 1) % 100 + 1
            valid_count = valid_count + 1
            buffer[valid_count] = env.commit_history[pos]
        end
        
        -- 直接拼接有效部分
        env.engine:commit_text(table.concat(buffer, "", 1, valid_count))
        context:clear()
        return 1
    end
end

return { init = init, func = processor }