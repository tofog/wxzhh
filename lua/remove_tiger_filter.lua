local M = {}

-- 局部化高频函数
local utf8_len = utf8.len
local table_insert = table.insert
local string_gmatch = string.gmatch
local string_sub = string.sub
local string_match = string.match

-- 获取辅助码
function M.run_fuzhu(cand, initial_comment)
    local full_fuzhu_list, first_fuzhu_list = {}, {}

    for segment in string_gmatch(initial_comment, "[^%s]+") do
        local match = string_match(segment, ";(.+)$")
        if match then
            for sub_match in string_gmatch(match, "[^,]+") do
                table_insert(full_fuzhu_list, sub_match)
                local first_char = string_sub(sub_match, 1, 1)
                if first_char and first_char ~= "" then
                    table_insert(first_fuzhu_list, first_char)
                end
            end
        end
    end

    return full_fuzhu_list, first_fuzhu_list
end

-- 第一套候选词映射（虎单模式）
local letter_map_tiger = {
    q = "都", w = "得", e = "也", r = "了", t = "我", y = "到", u = "的", i = "为", o = "是", p = "行",
    a = "来", s = "说", d = "中", f = "一", g = "就", h = "道", j = "人", k = "能", l = "而", 
    z = "可", x = "和", c = "不", v = "要", b = "如", n = "在", m = "大"
}

-- 第二套候选词映射（虎词模式）
local letter_map_tigress = {
    q = "特别", w = "怎么", e = "突然", r = "因为", t = "我们", y = "当然", u = "工作", i = "为什么", o = "自己", p = "起来",
    a = "那个", s = "出来", d = "哪个", f = "开始", g = "地方", h = "孩子", j = "什么", k = "没有", l = "而且", 
    z = "可以", x = "应该", c = "不是", v = "这个", b = "如果", n = "现在", m = "所以"
}

-- 新增：候选词生成函数
function M.generate_single_tiger(env, input_char)
    local context = env.engine.context
    local cand_text = letter_map_tiger[input_char] or ""
    if cand_text == "" then return end
    
    -- 创建候选词对象
    local cand = Candidate("manual", 0, utf8_len(context.input), cand_text, "")
    return cand
end

function M.generate_single_tigress(env, input_char)
    local context = env.engine.context
    local cand_text = letter_map_tigress[input_char] or ""
    if cand_text == "" then return end
    
    -- 创建候选词对象
    local cand = Candidate("manual", 0, utf8_len(context.input), cand_text, "")
    return cand
end

-- 初始化
function M.init(env)
    local config = env.engine.schema.config
    env.settings = {
        fuzhu_type = config:get_string("super_comment/fuzhu_type") or ""
    }
end

-- 判断是否为字母或数字
local function is_alnum(text)
    return text:match("[%w%s]") ~= nil
end

-- 判断是否包含数字但不包含字母
local function contains_digit_no_alpha(text)
    return text:match("%d") ~= nil and not text:match("[%a]")
end

-- 判断是否包含字母
local function contains_alpha(text)
    return text:match("[%a]") ~= nil
end

-- 判断注释是否不包含分号
local function contains_no_semicolons(comment)
    return not comment:find(";")
end

-- 定义汉字范围
local charset = {
    ["[基本]"] = {first = 0x4e00, last = 0x9fff},
    ["[扩A]"] = {first = 0x3400, last = 0x4dbf},
    ["[扩B]"] = {first = 0x20000, last = 0x2a6df},
    ["[扩C]"] = {first = 0x2a700, last = 0x2b73f},
    ["[扩D]"] = {first = 0x2b740, last = 0x2b81f},
    ["[扩E]"] = {first = 0x2b820, last = 0x2ceaf},
    ["[扩F]"] = {first = 0x2ceb0, last = 0x2ebef},
    ["[扩G]"] = {first = 0x30000, last = 0x3134f},
    ["[扩H]"] = {first = 0x31350, last = 0x323af},
    ["[扩I]"] = {first = 0x2EBF0, last = 0x2EE5D},
}

-- 检查文本是否包含至少一个汉字
local function contains_chinese(text)
    for i in utf8.codes(text) do
        local c = utf8.codepoint(text, i)
        for _, range in pairs(charset) do
            if c >= range.first and c <= range.last then
                return true
            end
        end
    end
    return false
end

-- 字母计数辅助函数
local function count_letters(s)
    local count = 0
    for _ in string_gmatch(s, "%a") do count = count + 1 end
    return count
end

-- 主逻辑
function M.func(input, env)
    local context = env.engine.context
    local input_preedit = context:get_preedit().text
    -- 缓存输入码和长度
    local input_str = context.input
    local input_len = utf8_len(input_str)
    
    -- 候选词存储
    local candidates = {}        -- 全部候选词
    local fh_candidates = {}     -- 符号候选词
    local fc_candidates = {}     -- 反查候选词
    local qz_candidates = {}     -- 前缀候选词
    local sj_candidates = {}     -- 时间候选词
    local digit_candidates = {}  -- 包含数字但不包含字母的候选词
    local alnum_candidates = {}  -- 包含字母的候选词
    local punct_candidates = {}  -- 快符候选词
    local unique_candidates = {} -- 没有注释的候选词
    local tiger_sentence = {}    -- 虎句
    local pinyin_candidates = {}

    -- 候选词收集
    for cand in input:iter() do
        table_insert(candidates, cand)
    end
    
    -- 优化点：提前计算并缓存 is_radical_mode
    local seg = context.composition:back()
    env.is_radical_mode = seg and (
        seg:has_tag("radical_lookup") 
        or seg:has_tag("reverse_stroke") 
        or seg:has_tag("add_user_dict")
        or seg:has_tag("tiger_add_user")
    ) or false
    
    local is_prefix_input = input_preedit:find("^[VRNU/;]")
    
    for _, cand in ipairs(candidates) do
        -- 缓存候选词属性
        local text = cand.text
        local preedit = cand.preedit
        local comment = cand.comment
        local cand_type = cand.type
        
        if cand_type == "time" or cand_type == "date" or cand_type == "day_summary" or cand_type == "xq" or cand_type == "oww" or cand_type == "ojq" or cand_type == "holiday_summary" or cand_type == "birthday_reminders" then
            table_insert(sj_candidates, cand)
        elseif is_prefix_input then
            table_insert(qz_candidates, cand)
        elseif cand_type == "punct" then
            table_insert(fh_candidates, cand)
        elseif env.is_radical_mode then
            table_insert(fc_candidates, cand)
        elseif contains_digit_no_alpha(text) then
            table_insert(digit_candidates, cand)
        elseif contains_alpha(text) then
            table_insert(alnum_candidates, cand)
        elseif not contains_chinese(text) then
            table_insert(punct_candidates, cand)
        elseif comment == "" then
            table_insert(unique_candidates, cand)
        elseif contains_no_semicolons(comment) then 
            table_insert(tiger_sentence, cand)
        else
            table_insert(pinyin_candidates, cand)
        end
    end

    -- 时间候选词
    for _, cand in ipairs(sj_candidates) do
        yield(cand)
    end

    -- 前缀候选词
    for _, cand in ipairs(qz_candidates) do
        yield(cand)
    end
    
    -- 反查候选词
    for _, cand in ipairs(fc_candidates) do
        yield(cand)
    end

    -- 输出包含数字但不包含字母的候选词
    for _, cand in ipairs(digit_candidates) do
        yield(cand)
    end
    
    -- 符号候选词
    for _, cand in ipairs(fh_candidates) do
        yield(cand)
    end

    local tiger_tigress = {}    -- 虎单与虎词
    local other_tigress = {}
    local useless_candidates = {}
    local yc_candidates = {}    -- 预测候选词
    local short_tiger = {}
    
    for _, cand in ipairs(unique_candidates) do
        local text = cand.text
        local preedit = cand.preedit
        local comment = cand.comment
        
        local cletter_count = count_letters(preedit)
        local iletter_count = count_letters(input_str)
        
        if iletter_count == 0 then
            table_insert(yc_candidates, cand)
        elseif utf8_len(preedit) >= 5 then
            table_insert(tiger_sentence, cand)
        elseif iletter_count ~= cletter_count then
            table_insert(useless_candidates, cand)
        elseif cand.type == "phrase" and not preedit:find("[_*]") then
            table_insert(short_tiger, cand)
        else
            table_insert(tiger_tigress, cand)
        end
    end
    
    -- 预测候选词
    for _, cand in ipairs(yc_candidates) do
        yield(cand)
    end
    
    local tigress_candidates = {}    -- 虎词候选词
    local tiger_candidates = {}      -- 虎单候选词
    for _, cand in ipairs(tiger_tigress) do
        if utf8_len(cand.text) >= 2 then
            table_insert(tigress_candidates, cand)
        else
            table_insert(tiger_candidates, cand)
        end
    end

    -- 虎句
    local before_tigress = {}
    local now_sentence = {}
    for _, cand in ipairs(tiger_sentence) do
        local preedit = cand.preedit
        local inletter_count = count_letters(input_str)
        local caletter_count = count_letters(preedit)
        
        if inletter_count ~= caletter_count then
            table_insert(before_tigress, cand)
        else
            table_insert(now_sentence, cand)
        end
    end
    
    -- 符号
    local zerofh = {} 
    local onekf = {} 
    local twokf = {} 
    local otkf = {} 
    local useless_kf = {} 
    for _, cand in ipairs(punct_candidates) do
        local preedit = cand.preedit
        local canletter_count = count_letters(preedit)
        local inpletter_count = count_letters(input_str)
        local preedit_len = utf8_len(preedit)
        
        if canletter_count == 0 then 
            table_insert(zerofh, cand)
        elseif inpletter_count ~= preedit_len then
            table_insert(useless_kf, cand)
        elseif canletter_count == 1 then 
            table_insert(onekf, cand)
        elseif canletter_count == 2 then 
            table_insert(twokf, cand)
        else
            table_insert(otkf, cand)
        end
    end

    if context:get_option("english_word") then
        for _, cand in ipairs(alnum_candidates) do
            yield(cand)
        end
    else
        
        -- 🐯 虎单开关与虎词开关 (功能逻辑完全不变)
        if not context:get_option("tiger-sentence") and not context:get_option("yin") and not context:get_option("english_word") and not env.is_radical_mode and not is_prefix_input and #sj_candidates == 0 then
            if context:get_option("tiger") and context:get_option("tigress") then
                if input_len < 4 then
                   for _, cand in ipairs(tiger_tigress) do
                       yield(cand)
                   end
                elseif input_len == 4 and #tiger_tigress == 1 then
                    env.engine:commit_text(tiger_tigress[1].text)
                    context:clear()
                elseif input_len == 4 and #tiger_tigress == 0 and #punct_candidates ~= 0 then                
                elseif input_len == 4 and #tiger_tigress == 0 then                
                    context:clear()                      
                else
                   if input_len == 4 then
                      for _, cand in ipairs(tiger_tigress) do         
                          yield(cand)       
                      end                    
                 local previous = tiger_tigress[1].text            
                 tiger_four = previous
                                         
                   elseif input_len == 5 then
                       env.engine:commit_text(tiger_four) 
                 tiger_four = ""
                       local last_input = string_sub(input_str, -1)     
                       
                       -- 虎单候选词生成 (位置1)
                       local manual_cand = M.generate_single_tiger(env, last_input)
                       if manual_cand then
                           yield(manual_cand)
                       end
                       -- 虎词候选词生成 (位置1)
                       local manual_cand = M.generate_single_tigress(env, last_input)
                       if manual_cand then
                           yield(manual_cand)
                       end
                       env.engine.context.input = last_input
                   else
                   end          
                end                 
            elseif context:get_option("tiger") then
                if input_len < 4 then       
                   for _, cand in ipairs(tiger_candidates) do
                       yield(cand)
                   end
                   for _, cand in ipairs(onekf) do
                       yield(cand)
                   end     
                elseif input_len == 4 and #tiger_candidates == 1 then
                    env.engine:commit_text(tiger_candidates[1].text)
                    context:clear()        
                elseif input_len == 4 and #tiger_candidates == 0 and #punct_candidates ~= 0 then
                elseif input_len == 4 and #tiger_candidates == 0 then
                    context:clear()                        
                else
                   if input_len == 4 then
                      for _, cand in ipairs(tiger_candidates) do         
                          yield(cand)       
                      end                    
                   
                 local previous = tiger_candidates[1].text                
                 tiger_four = previous
                                         
                   elseif input_len == 5 then
                       env.engine:commit_text(tiger_four) 
                 tiger_four = ""
                       local last_input = string_sub(input_str, -1)             
                       
                       -- 虎单候选词生成 (位置2)
                       local manual_cand = M.generate_single_tiger(env, last_input)
                       if manual_cand then
                           yield(manual_cand)
                       end
                       env.engine.context.input = last_input
                   else
                   end          
                end                 

            elseif context:get_option("tigress") then
                if input_len < 4 then        
                   for _, cand in ipairs(tigress_candidates) do
                       yield(cand)
                   end
                elseif input_len == 4 and #tigress_candidates == 1 then
                    env.engine:commit_text(tigress_candidates[1].text)
                    context:clear()  
                elseif input_len == 4 and #tigress_candidates == 0 and #punct_candidates ~= 0 then                 
                elseif input_len == 4 and #tigress_candidates == 0 then                 
                    context:clear()                               
                else
                   if input_len == 4 then
                      for _, cand in ipairs(tigress_candidates) do         
                          yield(cand)       
                      end                    
                      
                 local previous = tigress_candidates[1].text               
                 tiger_four = previous
                                         
                   elseif input_len == 5 then
                       env.engine:commit_text(tiger_four) 
                 tiger_four = ""
                       local last_input = string_sub(input_str, -1)             
                       
                       -- 虎词候选词生成 (位置3)
                       local manual_cand = M.generate_single_tigress(env, last_input)
                       if manual_cand then
                           yield(manual_cand)
                       end
                       env.engine.context.input = last_input
                   else
                   end          
                end 
            else                
            end
        elseif context:get_option("tiger") and context:get_option("tigress") then
            for _, cand in ipairs(tiger_tigress) do
                yield(cand)
            end
        elseif context:get_option("tiger") then
            for _, cand in ipairs(tiger_candidates) do
                yield(cand)
            end
            for _, cand in ipairs(onekf) do
                yield(cand)
            end
        elseif context:get_option("tigress") then
            for _, cand in ipairs(tigress_candidates) do
                yield(cand)
            end
        else
        end
    
        for _, cand in ipairs(zerofh) do
          yield(cand)
        end
        for _, cand in ipairs(twokf) do
          yield(cand)
        end
        for _, cand in ipairs(otkf) do
          yield(cand)
        end
        
        -- 🐯 虎句开关 (功能逻辑完全不变)
        if context:get_option("tiger-sentence") and not input_preedit:find("`") then
          for _, cand in ipairs(now_sentence) do
            yield(cand)
          end
          if not context:get_option("chinese_english") and not context:get_option("yin") then
              for _, cand in ipairs(before_tigress) do
                 yield(cand)
              end
              for _, cand in ipairs(useless_candidates) do
                 yield(cand)
              end
          end
        end
    end
        
    -- 提前获取第一个候选项
    local first_cand = nil
    local yin_candidates = {}
    if context:get_option("yin") and not context:get_option("english_word") or input_preedit:find("`") then
      for _, cand in ipairs(pinyin_candidates) do
          if not first_cand then first_cand = cand end
          table_insert(yin_candidates, cand)
      end
    end
    
    -- 如果输入码长 > 4，则直接输出默认排序
    for _, cand in ipairs(yin_candidates) do 
        if input_len > 4 then
            yield(cand) 
        end
    end
    
    -- 如果第一个候选是字母/数字，则直接返回默认候选
    if first_cand and is_alnum(first_cand.text) then
        for _, cand in ipairs(yin_candidates) do yield(cand) end
        return
    end
    
    local single_char_cands, alnum_cands, other_cands = {}, {}, {}

    if input_len >= 3 and input_len <= 4 then
        -- 分类候选
        for _, cand in ipairs(yin_candidates) do
            local text = cand.text
            if is_alnum(text) then
                table_insert(alnum_cands, cand)
            elseif utf8_len(text) == 1 then
                table_insert(single_char_cands, cand)
            else
                table_insert(other_cands, cand)
            end
        end
        
        local last_char = string_sub(input_str, -1)
        local last_two = string_sub(input_str, -2)
        local has_match = false
        local moved, reordered = {}, {}

        -- 如果 `other_cands` 为空，说明所有非字母数字候选都是单字
        if #other_cands == 0 then
            for _, cand in ipairs(single_char_cands) do
                table_insert(moved, cand)
                has_match = true
            end
        else
            -- 匹配 `first` 和 `full`
            for _, cand in ipairs(single_char_cands) do
                local full, first = M.run_fuzhu(cand, cand.comment or "")
                local matched = false

                if input_len == 4 then
                    for _, code in ipairs(full) do
                        if code == last_two then
                            matched = true
                            has_match = true
                            break
                        end
                    end
                else
                    for _, code in ipairs(first) do
                        if code == last_char then
                            matched = true
                            has_match = true
                            break
                        end
                    end
                end

                if matched then
                    table_insert(moved, cand)
                else
                    table_insert(reordered, cand)
                end
            end
        end
        
        -- 动态排序逻辑
        if has_match then
            for _, v in ipairs(other_cands) do yield(v) end
            for _, v in ipairs(moved) do yield(v) end
            for _, v in ipairs(reordered) do yield(v) end
            for _, v in ipairs(alnum_cands) do yield(v) end
        else
            for _, v in ipairs(other_cands) do yield(v) end
            for _, v in ipairs(alnum_cands) do yield(v) end
            for _, v in ipairs(moved) do yield(v) end
            for _, v in ipairs(reordered) do yield(v) end
        end

    else  -- 处理 input_len < 3 的情况
        for _, cand in ipairs(yin_candidates) do yield(cand) end
    end
    
    if context:get_option("yin") then
        for _, cand in ipairs(alnum_candidates) do
            yield(cand)
        end
    elseif context:get_option("chinese_english") then
        for _, cand in ipairs(alnum_candidates) do
            yield(cand)
        end
    end
end

return M