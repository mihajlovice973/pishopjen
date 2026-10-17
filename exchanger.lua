-- ============================================================
-- QQ-SHOP EXCHANGER v5.0 (GUI REDESIGN)
-- Полностью переработанный интерфейс по макету
-- ============================================================
local component = require("component")
local event = require("event")
local computer = require("computer")
local unicode = require("unicode")
local fs = require("filesystem")
local serialization = require("serialization")
local term = require("term")
local keyboard = require("keyboard")

local gpu = component.gpu
local pim = component.isAvailable("pim") and component.pim or nil
local me = component.isAvailable("me_interface") and component.me_interface or nil

-- Настройка разрешения (пытаемся выставить 160x50, как на скрине)
local W, H = 160, 50
local maxW, maxH = gpu.maxResolution()
if maxW < 160 then W, H = maxW, maxH end
pcall(gpu.setResolution, W, H)
W, H = gpu.getResolution()

-- ЦВЕТОВАЯ ПАЛИТРА (Строго по скриншоту)
local C = {
    bg = 0x080A10,          -- Глубокий темный фон
    panel = 0x0F141E,       -- Фон панелей
    border = 0x00E5FF,      -- Неоновый голубой (циан)
    border_dim = 0x005566,  -- Тусклый голубой
    text_main = 0xE0E6ED,   -- Белый текст
    text_dim = 0x6A7A8A,    -- Серый текст
    accent = 0x00E5FF,      -- Акцентный голубой
    green = 0x00FF88,       -- Зеленый (успех/онлайн)
    red = 0xFF4444,         -- Красный (ошибка)
    yellow = 0xFFD700,      -- Желтый (курс)
    select = 0x1A334D,      -- Подсветка выбранной строки
    header_bg = 0x112233,   -- Фон шапки таблицы
}

-- КОНФИГУРАЦИЯ
local VERSION = "v 4.4.7"
local AUTHOR = "KaRMa__"
local EXPORT_DIR = "UP"
local PUSH_DIR = "DOWN"

-- СПИСОК РУД (Можно заменить на файл)
local ore_list = {
    { take = { label = "Алмазная руда", name = "minecraft:diamond_ore", amount = 1 }, give = { label = "Алмаз", name = "minecraft:diamond", amount = 2 } },
    { take = { label = "Железная руда", name = "minecraft:iron_ore", amount = 3 }, give = { label = "Железный слиток", name = "minecraft:iron_ingot", amount = 7 } },
    { take = { label = "Золотая руда", name = "minecraft:gold_ore", amount = 3 }, give = { label = "Золотой слиток", name = "minecraft:gold_ingot", amount = 7 } },
    { take = { label = "Лазуритовая руда", name = "minecraft:lapis_ore", amount = 1 }, give = { label = "Лазурит", name = "minecraft:dye", damage = 4.0, amount = 7 } },
    { take = { label = "Красная руда", name = "minecraft:redstone_ore", amount = 1 }, give = { label = "Блок красного камня", name = "minecraft:redstone_block", amount = 1 } },
    { take = { label = "Угольная руда", name = "minecraft:coal_ore", amount = 1 }, give = { label = "Уголь", name = "minecraft:coal", amount = 3 } },
    { take = { label = "Руда ист. кварца", name = "appliedenergistics2:tile.OreQuartz", amount = 1 }, give = { label = "Кристалл ист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", amount = 3 } },
    { take = { label = "Заряж. руда ист. квар", name = "appliedenergistics2:tile.OreQuartzCharged", amount = 1 }, give = { label = "Заряж. крист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", damage = 1.0, amount = 3 } },
    { take = { label = "Кварцевая руда", name = "minecraft:quartz_ore", amount = 1 }, give = { label = "Кварц", name = "minecraft:quartz", amount = 4 } },
    { take = { label = "Медная руда", name = "IC2:blockOreCopper", amount = 3 }, give = { label = "Медный слиток", name = "IC2:itemIngot", amount = 7 } },
    { take = { label = "Оловянная руда", name = "IC2:blockOreTin", amount = 3 }, give = { label = "Оловянный слиток", name = "IC2:itemIngot", damage = 1.0, amount = 7 } },
    { take = { label = "Серебряная руда", name = "ThermalFoundation:Ore", damage = 2.0, amount = 1 }, give = { label = "Серебрянный слиток", name = "IC2:itemIngot", damage = 6.0, amount = 2 } },
    { take = { label = "Платиновая руда", name = "ThermalFoundation:Ore", damage = 5.0, amount = 1 }, give = { label = "Измельчённая платина", name = "ThermalFoundation:material", damage = 37.0, amount = 2 } },
    { take = { label = "Никелевая руда", name = "ThermalFoundation:Ore", damage = 4.0, amount = 1 }, give = { label = "Никелевый слиток", name = "ThermalFoundation:material", damage = 68.0, amount = 2 } },
    { take = { label = "Дракониевая руда", name = "DraconicEvolution:draconiumOre", amount = 1 }, give = { label = "Дракониевая пыль", name = "DraconicEvolution:draconiumDust", amount = 2 } },
    { take = { label = "Изумрудная руда", name = "minecraft:emerald_ore", amount = 1 }, give = { label = "Изумруд", name = "minecraft:emerald", amount = 2 } }
}

-- СОСТОЯНИЕ UI
local selected_idx = 1
local scroll_offset = 0
local total_me_items = 0
local status_msg = "QQ-SHOP готов. Ожидаю игрока на PIM."
local status_color = C.green
local player_name = "---"
local current_time = os.date("%d.%m.%Y %H:%M:%S")

-- ХЕЛПЕРЫ
local function ulen(t) return unicode.len(tostring(t or "")) end
local function clip(t, w)
    t = tostring(t or "")
    if ulen(t) <= w then return t end
    return unicode.sub(t, 1, w - 1) .. "…"
end

local function writeText(x, y, text, fg, bg)
    if y < 1 or y > H or x > W or x < 1 then return end
    if bg then gpu.setBackground(bg) end
    if fg then gpu.setForeground(fg) end
    gpu.set(x, y, tostring(text))
end

local function fillRect(x, y, w, h, bg)
    if w <= 0 or h <= 0 then return end
    gpu.setBackground(bg)
    gpu.fill(x, y, w, h, " ")
end

local function drawBox(x, y, w, h, title, border_col, bg_col)
    fillRect(x, y, w, h, bg_col)
    gpu.setForeground(border_col)
    gpu.setBackground(bg_col)
    
    -- Верхняя и нижняя границы
    gpu.set(x, y, "┌" .. string.rep("─", w - 2) .. "┐")
    gpu.set(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
    
    -- Боковые границы
    for i = 1, h - 2 do
        gpu.set(x, y + i, "│")
        gpu.set(x + w - 1, y + i, "│")
    end
    
    if title and title ~= "" then
        writeText(x + 2, y, " " .. title .. " ", border_col, bg_col)
    end
end

local function formatNum(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then return string.format("%.1fK", n / 1000)
    else return tostring(math.floor(n)) end
end

-- ЛОГИКА
local function updateME()
    if not me then return end
    total_me_items = 0
    for i, ore in ipairs(ore_list) do
        local dmg = ore.give.damage or 0
        local ok, item = pcall(function() return me.getItemDetail({ id = ore.give.name, dmg = dmg }).basic() end)
        if ok and item then
            ore.size = item.qty
            ore.maxSize = item.max_size or 64
            total_me_items = total_me_items + item.qty
        else
            ore.size = 0
            ore.maxSize = 64
        end
    end
end

-- ОТРИСОВКА ИНТЕРФЕЙСА
local function drawGUI()
    fillRect(1, 1, W, H, C.bg)

    -- ================= ШАПКА =================
    local header_h = 5
    fillRect(1, 1, W, header_h, C.bg)
    
    -- Логотип и текст
    writeText(3, 2, "QQ-SHOP", C.border, C.bg)
    writeText(3, 3, "RESOURCE EXCHANGER", C.text_main, C.bg)
    writeText(3, 4, "Обмен ресурсов • курс • история", C.text_dim, C.bg)
    
    -- Статус ONLINE (справа)
    writeText(W - 11, 2, "● ONLINE", C.green, C.bg)
    
    -- Декоративные полоски
    for i = 1, 4 do
        local bx = W - 45 + (i - 1) * 6
        writeText(bx, 2, "───", (i % 2 == 0) and C.border_dim or C.accent, C.bg)
    end
    
    -- Время
    writeText(W - ulen(current_time) - 3, 3, current_time, C.text_dim, C.bg)
    
    -- Разделитель
    gpu.setForeground(C.border)
    gpu.setBackground(C.bg)
    gpu.set(1, 5, string.rep("─", W))
    gpu.setForeground(C.accent)
    gpu.set(1, 6, string.rep("─", W))

    -- ================= ЛЕВАЯ ТАБЛИЦА =================
    local tbl_x, tbl_y = 2, 7
    local tbl_w = math.floor(W * 0.65)
    local tbl_h = H - 15
    drawBox(tbl_x, tbl_y, tbl_w, tbl_h, "", C.border_dim, C.panel)
    writeText(tbl_x + 2, tbl_y, " ОБМЕННИК РЕСУРСОВ ", C.text_main, C.panel)
    writeText(tbl_x + tbl_w - 18, tbl_y, " РУДА -> РЕСУРСЫ ", C.text_dim, C.panel)

    -- Заголовки таблицы
    local col_x = {
        tbl_x + 2,   -- #
        tbl_x + 5,   -- ВИД РУДЫ
        tbl_x + 28,  -- У ВАС
        tbl_x + 36,  -- В МЭ
        tbl_x + 48,  -- КУРС
        tbl_x + 58   -- ВЫДАЕТСЯ
    }
    
    local head_y = tbl_y + 2
    gpu.setForeground(C.text_dim)
    gpu.setBackground(C.header_bg)
    gpu.fill(tbl_x + 1, head_y, tbl_w - 2, 1, " ")
    writeText(col_x[1], head_y, "#", C.text_dim, C.header_bg)
    writeText(col_x[2], head_y, "ВИД РУДЫ", C.text_dim, C.header_bg)
    writeText(col_x[3], head_y, "У ВАС", C.text_dim, C.header_bg)
    writeText(col_x[4], head_y, "В МЭ", C.text_dim, C.header_bg)
    writeText(col_x[5], head_y, "КУРС", C.text_dim, C.header_bg)
    writeText(col_x[6], head_y, "ВЫДАЕТСЯ", C.text_dim, C.header_bg)
    
    gpu.setForeground(C.border_dim)
    gpu.setBackground(C.panel)
    gpu.set(tbl_x + 1, head_y + 1, string.rep("─", tbl_w - 2))

    -- Отрисовка списка
    local max_rows = tbl_h - 5
    if selected_idx > #ore_list then selected_idx = #ore_list end
    if selected_idx < 1 then selected_idx = 1 end
    if selected_idx > scroll_offset + max_rows then scroll_offset = selected_idx - max_rows end
    if selected_idx <= scroll_offset then scroll_offset = selected_idx - 1 end

    for i = 1, max_rows do
        local idx = scroll_offset + i
        local ore = ore_list[idx]
        if not ore then break end

        local row_y = head_y + 2 + i
        local is_sel = (idx == selected_idx)
        local bg_col = is_sel and C.select or C.panel
        local txt_col = is_sel and C.text_main or C.text_dim
        
        fillRect(tbl_x + 1, row_y, tbl_w - 2, 1, bg_col)
        
        writeText(col_x[1], row_y, string.format("%02d", idx), txt_col, bg_col)
        writeText(col_x[2], row_y, clip(ore.take.label, 20), txt_col, bg_col)
        
        -- "У вас" (здесь можно сделать реальный подсчет из PIM, если он есть)
        local user_has = 0 
        if pim then 
            -- (Опционально: можно добавить сканирование инвентаря игрока)
        end
        writeText(col_x[3], row_y, formatNum(user_has), txt_col, bg_col)
        
        writeText(col_x[4], row_y, formatNum(ore.size or 0), C.accent, bg_col)
        
        local rate_str = tostring(ore.take.amount) .. " > " .. tostring(ore.give.amount)
        writeText(col_x[5], row_y, rate_str, C.yellow, bg_col)
        
        writeText(col_x[6], row_y, clip(ore.give.label, 16), (ore.size or 0) > 0 and C.text_main or C.text_dim, bg_col)
    end

    -- ================= ПРАВАЯ ПАНЕЛЬ (ИНФО) =================
    local info_x = tbl_w + 4
    local info_w = W - info_x - 2
    local info_h = tbl_h
    drawBox(info_x, tbl_y, info_w, info_h, "", C.border_dim, C.panel)

    -- Кнопки меню
    local btn_y = tbl_y + 2
    writeText(info_x + 2, btn_y, "ОБНОВИТЬ", C.text_main, C.panel)
    writeText(info_x + 14, btn_y, "МЭ", C.text_dim, C.panel)
    writeText(info_x + 20, btn_y, "ИСТОРИЯ", C.text_dim, C.panel)
    
    gpu.setForeground(C.border_dim)
    gpu.setBackground(C.panel)
    gpu.set(info_x + 1, btn_y + 1, string.rep("─", info_w - 2))

    -- Информация о выбранной руде
    local sel_ore = ore_list[selected_idx] or ore_list[1]
    writeText(info_x + 2, tbl_y + 5, "ВЫБРАНА РУДА", C.text_dim, C.panel)
    writeText(info_x + 2, tbl_y + 7, clip(sel_ore.take.label, info_w - 4), C.accent, C.panel)
    writeText(info_x + 2, tbl_y + 9, "ИСТОРИЯ ИГРОКА: 0", C.text_dim, C.panel)
    
    gpu.setForeground(C.border_dim)
    gpu.setBackground(C.panel)
    gpu.set(info_x + 1, tbl_y + 11, string.rep("─", info_w - 2))
    
    -- Курс
    writeText(info_x + 2, tbl_y + 13, "КУРС ОБМЕНА:", C.text_dim, C.panel)
    local rate_str = tostring(sel_ore.take.amount) .. " -> " .. tostring(sel_ore.give.amount)
    writeText(info_x + info_w - ulen(rate_str) - 2, tbl_y + 13, rate_str, C.yellow, C.panel)
    
    writeText(info_x + 2, tbl_y + 15, "В ИНВЕНТАРЕ:", C.text_dim, C.panel)
    writeText(info_x + info_w - 4, tbl_y + 15, "0", C.text_main, C.panel)
    
    writeText(info_x + 2, tbl_y + 16, "БУДЕТ ВЫДАНО:", C.text_dim, C.panel)
    writeText(info_x + info_w - 4, tbl_y + 16, "0", C.text_main, C.panel)
    
    -- Статус ресурса
    local has_res = (sel_ore.size or 0) >= sel_ore.give.amount
    local res_text = has_res and "● РЕСУРС ДОСТУПЕН" or "● НЕТ В МЭ"
    local res_col = has_res and C.green or C.red
    writeText(info_x + 2, tbl_y + 18, res_text, res_col, C.panel)

    -- ================= НИЖНЯЯ ПАНЕЛЬ (ПАКЕТНЫЙ ОБМЕН) =================
    local bot_y = H - 8
    local bot_w = W - 4
    drawBox(2, bot_y, bot_w, 4, "", C.border_dim, C.panel)
    writeText(3, bot_y, " ПАКЕТНЫЙ ОБМЕН ", C.text_main, C.panel)
    
    writeText(4, bot_y + 1, "Встаньте на PIM для автоматического обмена", C.text_dim, C.panel)
    
    writeText(45, bot_y + 1, "ВИДОВ: 0", C.text_main, C.panel)
    writeText(45, bot_y + 2, "ПРИНИМАЕМ: 0", C.text_main, C.panel)
    writeText(45, bot_y + 3, "К ВЫДАЧЕ: 0", C.text_main, C.panel)
    
    writeText(W - 35, bot_y + 1, "СТАТУС PIM: ОЖИДАНИЕ", C.yellow, C.panel)
    writeText(W - 35, bot_y + 2, "CFG: v6", C.text_dim, C.panel)
    writeText(W - 35, bot_y + 3, "МЭ: ПОДКЛЮЧЕНА", C.green, C.panel)
    
    writeText(3, bot_y + 3, "ОБЩАЯ СТАТИСТИКА: " .. formatNum(total_me_items) .. " РУДЫ", C.text_main, C.panel)

    -- ================= СТАТУС БАР =================
    local st_y = H - 3
    fillRect(2, st_y, W - 4, 3, C.panel)
    gpu.setForeground(C.border)
    gpu.setBackground(C.panel)
    gpu.set(2, st_y, "│")
    for i = 1, 2 do gpu.set(2, st_y + i, "│") end
    
    writeText(4, st_y + 1, "СТАТУС ● " .. status_msg, status_color, C.panel)
    writeText(4, st_y + 2, "Для обмена встаньте на PIM. Руда принимается автоматически.", C.text_dim, C.panel)

    -- ================= ФУТЕР =================
    local foot_y = H
    fillRect(1, foot_y, W, 1, C.select)
    writeText(1, foot_y, string.rep("─", W), C.border_dim, C.select)
    local footer_text = "[ " .. player_name .. " ]  [ " .. VERSION .. " ]"
    writeText(W - ulen(footer_text) - 2, foot_y, footer_text, C.text_main, C.select)
end

-- ЛОГИКА ОБМЕНА
local function giveIngot(toGive, ore, index)
    if not me then return end
    local totalGive = 0
    local giveDamage = ore.give.damage or 0
    while totalGive < toGive do
        local giveSize = math.min(toGive - totalGive, ore.maxSize or 64)
        local ok, res = pcall(me.exportItem, { id = ore.give.name, dmg = giveDamage }, EXPORT_DIR, giveSize)
        if ok and res and res.size and res.size > 0 then
            totalGive = totalGive + res.size
            ore_list[index].size = math.max(0, (ore_list[index].size or 0) - res.size)
        else
            break
        end
    end
end

local function exchangeOre(ore, index)
    if not pim or not me then return end
    local slots = pim.getInventorySize()
    local data = pim.getAllStacks(0)
    
    for slot = 1, slots do
        local stack = data[slot]
        if stack and stack.id == ore.take.name and (stack.dmg or 0) == (ore.take.damage or 0) then
            local qty = stack.qty
            local takeSize = qty - (qty % ore.take.amount)
            if takeSize > 0 then
                local giveSize = (takeSize / ore.take.amount) * ore.give.amount
                if (ore.size or 0) >= giveSize then
                    local ok, takedOre = pcall(pim.pushItem, PUSH_DIR, slot, takeSize)
                    if ok and takedOre and takedOre > 0 then
                        local actualGive = math.floor(takedOre / ore.take.amount) * ore.give.amount
                        giveIngot(actualGive, ore, index)
                        status_msg = string.format("Обменяно %d %s на %d %s", takedOre, ore.take.label, actualGive, ore.give.label)
                        status_color = C.green
                        drawGUI()
                    end
                end
            end
        end
    end
end

-- ОБРАБОТКА СОБЫТИЙ
local function handleEvents()
    while true do
        local ev, p1, p2, p3, p4, p5 = event.pull(1)
        
        -- Обновление времени каждую секунду
        current_time = os.date("%d.%m.%Y %H:%M:%S")
        
        if ev == "player_on" or ev == "pim_player_enter" then
            player_name = p1
            status_msg = "Приветствую, " .. player_name .. "! Сканирую инвентарь..."
            status_color = C.accent
            drawGUI()
            os.sleep(1)
            updateME()
            exchangeOre(ore_list[selected_idx], selected_idx)
            status_msg = "QQ-SHOP готов. Ожидаю игрока на PIM."
            status_color = C.green
            
        elseif ev == "player_off" or ev == "pim_player_leave" then
            player_name = "---"
            status_msg = "QQ-SHOP готов. Ожидаю игрока на PIM."
            status_color = C.green
            
        elseif ev == "key_down" then
            local char, code = p3, p4
            if code == 200 then -- Up
                selected_idx = math.max(1, selected_idx - 1)
            elseif code == 208 then -- Down
                selected_idx = math.min(#ore_list, selected_idx + 1)
            elseif char == 13 then -- Enter
                if pim and me then
                    updateME()
                    exchangeOre(ore_list[selected_idx], selected_idx)
                end
            end
            
        elseif ev == "touch" then
            local x, y = p3, p4
            -- Клик по таблице
            local tbl_x, tbl_y = 2, 7
            local tbl_w = math.floor(W * 0.65)
            local tbl_h = H - 15
            local head_y = tbl_y + 2
            
            if x > tbl_x and x < tbl_x + tbl_w and y > head_y + 2 and y < head_y + 2 + (tbl_h - 5) then
                local clicked_row = math.floor(y - (head_y + 2)) + 1 + scroll_offset
                if clicked_row <= #ore_list then
                    selected_idx = clicked_row
                end
            end
            
            -- Клик по кнопке "ОБНОВИТЬ"
            local info_x = tbl_w + 4
            if x >= info_x + 2 and x <= info_x + 9 and y == tbl_y + 2 then
                updateME()
                status_msg = "Данные из МЭ обновлены."
                status_color = C.accent
            end
        end
        
        drawGUI()
    end
end

-- ЗАПУСК
updateME()
drawGUI()
handleEvents()
