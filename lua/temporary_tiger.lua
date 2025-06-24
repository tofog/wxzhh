code_table = require("tiger_code_table")

-- 全局历史记录结构
global_commit_history = {}             -- 历史记录队列（FIFO）
global_commit_dict = {}                 -- 文本到编码映射 {文本: 编码}
global_seq_words_dict = {}              -- 编码到文本列表映射 {编码: {文本1, 文本2}}

-- 配置参数
global_max_history_size = 100           -- 历史记录最大容量
local punctuation = {                   -- 需过滤的标点符号
    ["，"] = true, ["。"] = true, ["、"] = true,
    ["？"] = true, ["："] = true, ["！"] = true
}

-- 加载永久自造词表
function load_permanent_user_words()
    local filename = rime_api.get_user_data_dir() .. "/lua/user_words.lua"
    local f, err = loadfile(filename)
    if f then
        return f() or {}
    else
        -- 文件不存在时创建初始空文件
        local record = "local user_words = {\n}\nreturn user_words"
        local fd = io.open(filename, "w")
        if fd then
            fd:setvbuf("line")
            fd:write(record)
            fd:close()
            log.info("[tiger_user_words] Created initial user_words.lua")
        else
            log.error("[tiger_user_words] Failed to create user_words.lua: " .. (err or "unknown error"))
        end
        return {}
    end
end

-- 反转词表：{词 => 码} 转换为 {码 => [词1, 词2]}
function reverse_seq_words(user_words)
    local new_dict = {}
    for word, code in pairs(user_words) do
        if not new_dict[code] then
            new_dict[code] = {word}
        else
            table.insert(new_dict[code], word)
        end
    end
    return new_dict
end

-- 标点过滤函数
local function filter_punctuation(text)
    local result = ""
    for i = 1, utf8.len(text) do
        local char = utf8_sub(text, i, i)
        if not punctuation[char] then
            result = result .. char
        end
    end
    return result
end

-- UTF8安全切片
function utf8_sub(str, start_char, end_char)
    local start_byte = utf8.offset(str, start_char)
    local end_byte = utf8.offset(str, end_char + 1) or #str + 1
    return string.sub(str, start_byte, end_byte - 1)
end

-- 生成虎码编码（简化版，只处理长度>=3的词）
function get_tiger_code(word)
    word = filter_punctuation(word)
    local len = utf8.len(word)
    if len < 3 then return "" end  -- 只处理3字及以上词语

    if len == 3 then
        local code1 = code_table[utf8_sub(word, 1, 1)] or ""
        local code2 = code_table[utf8_sub(word, 2, 2)] or ""
        local code3 = code_table[utf8_sub(word, 3, 3)] or ""
        return string.sub(code1, 1, 1) .. string.sub(code2, 1, 1) .. string.sub(code3, 1, 2)
    else
        local code1 = code_table[utf8_sub(word, 1, 1)] or ""
        local code2 = code_table[utf8_sub(word, 2, 2)] or ""
        local code3 = code_table[utf8_sub(word, 3, 3)] or ""
        local code_last = code_table[utf8_sub(word, len, len)] or ""
        return string.sub(code1, 1, 1) .. string.sub(code2, 1, 1) .. string.sub(code3, 1, 1) .. string.sub(code_last, 1, 1)
    end
end

-- 写入永久自造词到文件
function write_permanent_word_to_file(env, word, code)
    -- 添加到内存表
    env.permanent_user_words[word] = code
    
    -- 序列化并写入文件
    local filename = rime_api.get_user_data_dir() .. "/lua/user_words.lua"
    local serialize_str = ""
    for w, c in pairs(env.permanent_user_words) do
        serialize_str = serialize_str .. string.format('    ["%s"] = "%s",\n', w, c)
    end
    
    local record = "local user_words = {\n" .. serialize_str .. "}\nreturn user_words"
    local fd = assert(io.open(filename, "w"))
    fd:setvbuf("line")
    fd:write(record)
    fd:close()
    
    -- 更新反转表
    env.permanent_seq_words_dict = reverse_seq_words(env.permanent_user_words)
end

-- 历史记录管理核心函数（重构为env方法）
local function make_update_history(env)
    return function(commit_text)
        commit_text = filter_punctuation(commit_text)
        if commit_text == "" or utf8.len(commit_text) < 3 then
            return
        end

        -- 获取当前输入编码
        local input_code = env.engine.context.input
        
        -- 新增：跳过原生4码简词
        if #input_code == 4 then
            local in_temp_dict = global_commit_dict[commit_text] ~= nil
            local in_permanent_dict = env.permanent_user_words[commit_text] ~= nil
            
            if not in_temp_dict and not in_permanent_dict then
                return  -- 原生简词不记录
            end
        end

        -- 生成新编码
        local code = get_tiger_code(commit_text)
        if code == "" then return end

        -- 检测是否存在重复记录
        local is_repeated = (global_commit_dict[commit_text] ~= nil)
        local is_shortcut = (#input_code == 4)  -- 简码输入标识

        -- 永久化逻辑（在历史记录更新前）
        if is_repeated and is_shortcut then
            if not env.permanent_user_words[commit_text] then
                write_permanent_word_to_file(env, commit_text, code)
            end
        end

        -- 删除已有记录
        if global_commit_dict[commit_text] then
            local old_code = global_commit_dict[commit_text]
            
            -- 从编码映射中移除
            if global_seq_words_dict[old_code] then
                for i, text in ipairs(global_seq_words_dict[old_code]) do
                    if text == commit_text then
                        table.remove(global_seq_words_dict[old_code], i)
                        break
                    end
                end
                if #global_seq_words_dict[old_code] == 0 then
                    global_seq_words_dict[old_code] = nil
                end
            end
            
            -- 从历史队列中移除
            for i, text in ipairs(global_commit_history) do
                if text == commit_text then
                    table.remove(global_commit_history, i)
                    break
                end
            end
            global_commit_dict[commit_text] = nil
        end
        
        -- 添加新记录
        table.insert(global_commit_history, commit_text)
        global_commit_dict[commit_text] = code
        
        if not global_seq_words_dict[code] then
            global_seq_words_dict[code] = {}
        end
        table.insert(global_seq_words_dict[code], commit_text)
        
        -- 清理最早记录
        if #global_commit_history > global_max_history_size then
            local removed_text = table.remove(global_commit_history, 1)
            local removed_code = global_commit_dict[removed_text]
            
            if removed_code and global_seq_words_dict[removed_code] then
                for i, text in ipairs(global_seq_words_dict[removed_code]) do
                    if text == removed_text then
                        table.remove(global_seq_words_dict[removed_code], i)
                        break
                    end
                end
                if #global_seq_words_dict[removed_code] == 0 then
                    global_seq_words_dict[removed_code] = nil
                end
            end
            global_commit_dict[removed_text] = nil
        end
    end
end

-- 输入法处理器模块
local P = {}
function P.init(env)
    -- 加载永久自造词表
    env.permanent_user_words = load_permanent_user_words()
    env.permanent_seq_words_dict = reverse_seq_words(env.permanent_user_words)
    
    -- 创建带env闭包的历史更新函数
    env.update_history = make_update_history(env)
    
    env.engine.context.commit_notifier:connect(function(ctx)
        env.update_history(ctx:get_commit_text())
    end)
end

function P.func() return 2 end  -- 保留空实现

-- 候选词生成模块（统一插入逻辑）
local F = {}
function F.func(input, env)
    local context = env.engine.context
    local input_code = context.input
    local new_candidates = {}
    local start_pos, end_pos
    local has_original_candidates = false

    -- 确保永久词表已初始化
    if env.permanent_seq_words_dict == nil then
        env.permanent_user_words = load_permanent_user_words()
        env.permanent_seq_words_dict = reverse_seq_words(env.permanent_user_words)
    end

    -- 收集原始候选词
    for cand in input:iter() do
        if not start_pos then
            start_pos = cand.start
            end_pos = cand._end
            has_original_candidates = true
        end
        table.insert(new_candidates, cand)
    end

    -- 确保位置信息存在
    if not start_pos then
        start_pos = 0
        end_pos = string.len(input_code)
    end

    -- 合并永久和临时自造词（永久在前，临时在后）
    local combined_words = {}
    local combined_count = 0
    
    -- 先添加永久自造词
    if env.permanent_seq_words_dict[input_code] then
        for _, word in ipairs(env.permanent_seq_words_dict[input_code]) do
            combined_count = combined_count + 1
            combined_words[combined_count] = {text = word, type = "permanent"}
        end
    end
    
    -- 再添加临时自造词
    if global_seq_words_dict[input_code] then
        for i = #global_seq_words_dict[input_code], 1, -1 do
            local word = global_seq_words_dict[input_code][i]
            combined_count = combined_count + 1
            combined_words[combined_count] = {text = word, type = "history"}
        end
    end

    -- 统一插入逻辑
    if combined_count > 0 then
        if has_original_candidates then
            -- 有原始候选时，从第二位开始插入
            local insert_position = 2
            for i = 1, combined_count do
                local cand = combined_words[i]
                local comment = (cand.type == "permanent") and "*" or "⭐"
                local new_cand = Candidate(cand.type, start_pos, end_pos, cand.text, comment)
                table.insert(new_candidates, insert_position, new_cand)
                insert_position = insert_position + 1
            end
        else
            -- 无原始候选时，直接添加
            for i = 1, combined_count do
                local cand = combined_words[i]
                local comment = (cand.type == "permanent") and "*" or "⭐"
                local new_cand = Candidate(cand.type, start_pos, end_pos, cand.text, comment)
                table.insert(new_candidates, new_cand)
            end
        end
    end

    -- 返回最终候选列表
    for _, cand in ipairs(new_candidates) do
        yield(cand)
    end
end

return { F = F, P = P }