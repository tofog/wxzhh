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

-- 生成虎码编码
function get_tiger_code(word)
    word = filter_punctuation(word)
    local len = utf8.len(word)
    if len == 0 then return "" end

    if len == 1 then
        return code_table[word] or ""
    elseif len == 2 then
        local code1 = code_table[utf8_sub(word, 1, 1)] or ""
        local code2 = code_table[utf8_sub(word, 2, 2)] or ""
        return string.sub(code1, 1, 2) .. string.sub(code2, 1, 2)
    elseif len == 3 then
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

-- 历史记录管理核心函数
function update_history(commit_text)
    commit_text = filter_punctuation(commit_text)
    if commit_text == "" or utf8.len(commit_text) < 2 then
        return
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

    -- 生成新编码
    local code = get_tiger_code(commit_text)
    if code == "" then return end
    
    -- 添加新记录
    table.insert(global_commit_history, commit_text)
    global_commit_dict[commit_text] = code
    
    if not global_seq_words_dict[code] then
        global_seq_words_dict[code] = {}
    end
    table.insert(global_seq_words_dict[code], commit_text)
    
    -- 清理最早记录（队列超过容量时）
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

-- 输入法处理器模块
local P = {}
function P.init(env)
    env.engine.context.commit_notifier:connect(function(ctx)
        update_history(ctx:get_commit_text())
    end)
end
function P.func() return 2 end  -- 保留空实现

-- 候选词生成模块
local F = {}
function F.func(input, env)
    local context = env.engine.context
    local input_code = context.input
    local new_candidates = {}
    local start_pos, end_pos
    local has_original_candidates = false

    -- 收集原始候选词并标记是否存在
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

    -- 添加历史记录候选（智能插入第二位或作为唯一候选）
    if global_seq_words_dict[input_code] then
        if has_original_candidates then
            -- 有原始候选词时，按从新到旧顺序插入到第二个位置
            local insert_position = 2
            for i = #global_seq_words_dict[input_code], 1, -1 do
                local text = global_seq_words_dict[input_code][i]
                local cand = Candidate("history", start_pos, end_pos, text, "⭐")
                table.insert(new_candidates, insert_position, cand)
                insert_position = insert_position + 1
            end
        else
            -- 无原始候选词时，按从新到旧顺序直接添加
            for i = #global_seq_words_dict[input_code], 1, -1 do
                local text = global_seq_words_dict[input_code][i]
                local cand = Candidate("history", start_pos, end_pos, text, "⭐")
                table.insert(new_candidates, cand)
            end
        end
    end

    -- 返回最终候选列表
    for _, cand in ipairs(new_candidates) do
        yield(cand)
    end
end

return { F = F, P = P }
