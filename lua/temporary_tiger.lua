    code_table = require("tiger_code_table")

-- 全局历史记录表
global_commit_history = {}
global_commit_dict = {}       -- 文本到编码的映射
global_seq_words_dict = {}    -- 编码到文本列表的映射
global_max_history_size = 100 -- 最大历史记录数

-- 获取键值对 table 长度
function table_len(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- 正确的中文切片函数
function utf8_sub(str, start_char, end_char)
    local start_byte = utf8.offset(str, start_char)
    local end_byte = utf8.offset(str, end_char + 1) or #str + 1
    return string.sub(str, start_byte, end_byte - 1)
end

-- 将汉字转换为虎码编码
function get_tiger_code(word)
    local len = utf8.len(word)
    if len == 1 then
        return code_table[word]
    elseif len == 2 then
        return string.sub(code_table[utf8_sub(word, 1, 1)], 1, 2) .. string.sub(code_table[utf8_sub(word, 2, 2)], 1, 2)
    elseif len == 3 then
        return
            string.sub(code_table[utf8_sub(word, 1, 1)], 1, 1) .. string.sub(code_table[utf8_sub(word, 2, 2)], 1, 1) ..
                string.sub(code_table[utf8_sub(word, 3, 3)], 1, 2)
    elseif len >= 4 then
        return
            string.sub(code_table[utf8_sub(word, 1, 1)], 1, 1) .. string.sub(code_table[utf8_sub(word, 2, 2)], 1, 1) ..
                string.sub(code_table[utf8_sub(word, 3, 3)], 1, 1) ..
                string.sub(code_table[utf8_sub(word, len, len)], 1, 1)
    end

    return ""
end

-- 更新历史记录和编码映射
function update_history(commit_text)
    if commit_text == "" or utf8.len(commit_text) < 2 then
        return
    end
    
    -- 如果文本已存在，先移除旧记录
    if global_commit_dict[commit_text] then
        local old_code = global_commit_dict[commit_text]
        if global_seq_words_dict[old_code] then
            for i, text in ipairs(global_seq_words_dict[old_code]) do
                if text == commit_text then
                    table.remove(global_seq_words_dict[old_code], i)
                    break
                end
            end
            
            -- 如果编码对应的列表为空，移除该编码
            if #global_seq_words_dict[old_code] == 0 then
                global_seq_words_dict[old_code] = nil
            end
        end
        
        -- 从历史记录中移除
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
    
    -- 添加到历史记录
    table.insert(global_commit_history, commit_text)
    global_commit_dict[commit_text] = code
    
    -- 更新编码到文本的映射
    if not global_seq_words_dict[code] then
        global_seq_words_dict[code] = {}
    end
    table.insert(global_seq_words_dict[code], commit_text)
    
    -- 如果超过最大长度，移除最早记录
    if #global_commit_history > global_max_history_size then
        local removed_text = table.remove(global_commit_history, 1)
        local removed_code = global_commit_dict[removed_text]
        global_commit_dict[removed_text] = nil
        
        if global_seq_words_dict[removed_code] then
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
    end
end

-- ❶ 添加、删除候选项 ---
-- ------------------------------------------------------------------
local P = {}
function P.init(env)
    -- 连接提交通知器
    env.engine.context.commit_notifier:connect(function(ctx)
        local commit_text = ctx:get_commit_text()
        update_history(commit_text)
    end)
end

-- P 阶段按键处理 (已弃用，保留空实现)
function P.func(key_event, env)
    return 2
end

-- ❷ 读取、排序候选项 ---
-- ------------------------------------------------------------------
local F = {}

function F.init(env)
    -- 无需初始化，使用全局表
end

function F.func(input, env)
    local context = env.engine.context
    local input_code = context.input
    
    local new_candidates = {}
    local start_pos, end_pos
    
    -- 收集原始候选
    for cand in input:iter() do
        if not start_pos then
            start_pos = cand.start
            end_pos = cand._end
        end
        table.insert(new_candidates, cand)
    end
    
    -- 添加历史记录候选
    if global_seq_words_dict[input_code] then
        local words = global_seq_words_dict[input_code]
        -- 倒序添加（最近提交的优先）
        for i = #words, 1, -1 do
            local word = words[i]
            local new_cand = Candidate("word", start_pos, end_pos, word, "*")
            table.insert(new_candidates, 2, new_cand)
        end
    end
    
    -- 输出重新排序后的候选
    for _, cand in ipairs(new_candidates) do
        yield(cand)
    end
end

return {
    F = F,
    P = P
}