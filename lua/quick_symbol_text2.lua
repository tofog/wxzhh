

-- 初始化符号输入的状态
local function init(env)
    local config = env.engine.schema.config

    if config:get_string("recognizer/patterns/quick_text") then
        env.double_symbol_pattern_text1 = "^" .. string.sub(config:get_string("recognizer/patterns/quick_text"), 2, 2)  .. "$" 
    else
        env.double_symbol_pattern_text1 = "''"
    end
    
    env.double_symbol_pattern_text2 = "''"
    
    -- 初始化最后提交内容
    env.last_commit_text = "欢迎使用万象拼音！"
    
    -- 连接提交通知器
    env.engine.context.commit_notifier:connect(function(ctx)
        local commit_text = ctx:get_commit_text()
        if commit_text ~= "" then
            env.last_commit_text = commit_text  -- 更新最后提交内容到env
        end
    end)
end

-- 处理符号和文本的重复上屏逻辑
local function processor(key_event, env)
    local engine = env.engine
    local context = engine.context
    local input = context.input

    -- 检查用户是否双击'
    if string.match(input, env.double_symbol_pattern_text2) or string.match(input, env.double_symbol_pattern_text1) then
        -- 提交历史记录中的最新文本
        engine:commit_text(env.last_commit_text)  -- 从env获取最后提交内容
        context:clear()
        return 1  -- 终止处理
    end
end
return { init = init, func = processor }