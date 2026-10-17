local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local serialization = require("serialization")

if not fs.exists("/lib/inspect.lua") then
    shell.execute("wget -q https://raw.githubusercontent.com/kikito/inspect.lua/master/inspect.lua /lib/inspect.lua")
end
local inspect = require("inspect")

local me = com.isAvailable("me_interface") and com.me_interface or error("Интерфейс не подключен")
local pim = com.isAvailable("pim") and com.pim or error("PIM не подключен")
local gpu = com.gpu

-- Разрешение экрана (по скриншоту широкий формат)
local wantW, wantH = 160, 50
local maxW, maxH = gpu.maxResolution()
local w, h = math.min(wantW, maxW), math.min(wantH, maxH)
if not pcall(gpu.setResolution, w, h) then
    for _, res in ipairs({ {160, 50}, {120, 40}, {80, 25} }) do
        if pcall(gpu.setResolution, res[1], res[2]) then
            w, h = res[1], res[2]
            break
        end
    end
end

local EXPORT_DIR = "UP"          
local PUSH_DIR = "DOWN"          
local STATS_FILE = "exchanger_stats.txt"   
local MAX_LIMIT = 500000

-- ЦВЕТОВАЯ ПАЛИТРА ПОД СКРИНШОТ
local C = {
    bg = 0x101116,        -- Темный фон
    panel_bg = 0x1A1B26,  -- Фон панелей
    table_bg = 0x1A1B26,
    table_highlight = 0x292E42,
    border = 0x33CCFF,    -- Голубая рамка
    text_main = 0xCDD6F4, -- Белый текст
    text_dim = 0x7F849C,  -- Серый текст
    text_dark = 0x585B70,
    accent = 0x00FFFF,    -- Яркий голубой
    green = 0xA6E3A1,
    red = 0xF38BA8,
    orange = 0xFAB387,
    yellow = 0xF9E2AF,
    blue = 0x89B4FA,
    purple = 0xCBA6F7
}

-- Координаты зон
local HEADER_H = 5
local TABLE_X, TABLE_Y = 2, 7
local TABLE_W = w - 36
local TABLE_H = h - 17

local INFO_X, INFO_Y = w - 33, 7
local INFO_W, INFO_H = 31, h - 17

local BOTTOM_X, BOTTOM_Y = 2, h - 9
local BOTTOM_W, BOTTOM_H = w - 3, 4

local STATUS_X, STATUS_Y = 2, h - 4
local STATUS_W, STATUS_H = w - 3, 3

-- Данные руды
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

-- Вспомогательные функции рисования
local function ulen(t) return unicode.len(tostring(t or "")) end
local function clip(t, w)
    t = tostring(t or "")
    if w <= 0 then return "" end
    if ulen(t) <= w then return t end
    return unicode.sub(t, 1, w - 1) .. "…"
end

local function writeText(x, y, t, fg, bg)
    if y < 1 or y > h or x > w or x < 1 then return end
    if bg then gpu.setBackground(bg) end
    if fg then gpu.setForeground(fg) end
    gpu.set(x, y, t)
end

local function fillRect(x, y, ww, hh, bg)
    if ww <= 0 or hh <= 0 then return end
    gpu.setBackground(bg)
    gpu.fill(x, y, ww, hh, " ")
end

local function drawBox(x, y, ww, hh, border_color, bg_color, title)
    fillRect(x, y, ww, hh, bg_color)
    gpu.setForeground(border_color)
    gpu.setBackground(bg_color)
    gpu.set(x, y, "┌" .. string.rep("─", ww - 2) .. "┐")
    for i = 1, hh - 2 do
        gpu.set(x, y + i, "│")
        gpu.set(x + ww - 1, y + i, "│")
    end
    gpu.set(x, y + hh - 1, "└" .. string.rep("─", ww - 2) .. "┘")
    if title and title ~= "" then
        local t = clip(title, ww - 6)
        writeText(x + 2, y, "■ " .. t, border_color, bg_color)
    end
end

local function padRight(s, len)
    s = tostring(s or "")
    local l = ulen(s)
    if l >= len then return clip(s, len) end
    return s .. string.rep(" ", len - l)
end

local function formatNumber(num)
    local symbols = { "", "K", "M", "B", "T" }
    local formattedNum = num
    local symbolIndex = 1
    while formattedNum >= 1000 do
        formattedNum = formattedNum / 1000
        symbolIndex = symbolIndex + 1
    end
    formattedNum = string.format("%.1f", formattedNum)
    if formattedNum:sub(-2) == ".0" then
        formattedNum = formattedNum:sub(1, -3)
    end
    return formattedNum .. symbols[symbolIndex]
end

-- Логика обновления данных из МЭ
local totalOreInME = 0
local function updIngotsSize()
    totalOreInME = 0
    for _, ore in ipairs(ore_list) do
        local giveDamage = ore.give.damage or 0
        local success, item = pcall(function()
            return me.getItemDetail({ id = ore.give.name, dmg = giveDamage }).basic()
        end)
        if success and item then
            ore.size = item.qty
            totalOreInME = totalOreInME + item.qty
            ore.maxSize = item.max_size or 64
        else
            ore.size = 0
            ore.maxSize = 64
        end
    end
end

-- Переменные состояния UI
local selected_index = 1
local scroll_y = 0
local status_msg = "QQ-SHOP готов. Ожидаю игрока на PIM."
local status_color = C.green
local player_name = "---"

-- ОТРИСОВКА ИНТЕРФЕЙСА
local function drawInterface()
    fillRect(1, 1, w, h, C.bg)

    -- 1. ШАПКА
    writeText(3, 2, "QQ-SHOP", C.border, C.bg)
    writeText(3, 3, "RESOURCE EXCHANGER", C.text_main, C.bg)
    writeText(3, 4, "Обмен ресурсов • курс • история", C.text_dim, C.bg)
    
    writeText(w - 12, 2, "● ONLINE", C.green, C.bg)
    -- Декоративные полоски
    for i = 1, 5 do
        writeText(w - 40 + i*4, 2, "███", (i % 2 == 0) and C.border or C.panel_bg, C.bg)
    end
    local t = os.date("%d.%m.%Y %H:%M:%S")
    writeText(w - ulen(t) - 2, 4, t, C.text_dim, C.bg)
    
    gpu.setForeground(C.border)
    gpu.setBackground(C.bg)
    gpu.set(1, 5, string.rep("─", w))
    gpu.setForeground(0x00AAFF)
    gpu.set(1, 6, string.rep("═", w))

    -- 2. ЛЕВАЯ ТАБЛИЦА
    drawBox(TABLE_X, TABLE_Y, TABLE_W, TABLE_H, C.border, C.panel_bg, "ОБМЕННИК РЕСУРСОВ")
    writeText(TABLE_X + 2, TABLE_Y, "ОБМЕННИК РЕСУРСОВ", C.text_main, C.panel_bg)
    writeText(TABLE_X + TABLE_W - 15, TABLE_Y, "РУДА -> РЕСУРСЫ", C.text_dim, C.panel_bg)

    local col_w = { 4, 22, 8, 10, 10, 15 }
    local cx = { TABLE_X + 2, TABLE_X + 6, TABLE_X + 28, TABLE_X + 36, TABLE_X + 46, TABLE_X + 56 }
    
    local header_y = TABLE_Y + 2
    writeText(cx[1], header_y, "#", C.text_dim, C.panel_bg)
    writeText(cx[2], header_y, "ВИД РУДЫ", C.text_dim, C.panel_bg)
    writeText(cx[3], header_y, "У ВАС", C.text_dim, C.panel_bg)
    writeText(cx[4], header_y, "В МЭ", C.text_dim, C.panel_bg)
    writeText(cx[5], header_y, "КУРС", C.text_dim, C.panel_bg)
    writeText(cx[6], header_y, "ВЫДАЕТСЯ", C.text_dim, C.panel_bg)
    
    gpu.setForeground(C.text_dark)
    gpu.setBackground(C.panel_bg)
    gpu.set(TABLE_X + 1, header_y + 1, string.rep("─", TABLE_W - 2))

    local max_rows = TABLE_H - 5
    if selected_index > #ore_list then selected_index = #ore_list end
    if selected_index < 1 then selected_index = 1 end
    if selected_index > scroll_y + max_rows then scroll_y = selected_index - max_rows end
    if selected_index <= scroll_y then scroll_y = selected_index - 1 end
    if scroll_y < 0 then scroll_y = 0 end

    for i = 1, max_rows do
        local idx = scroll_y + i
        local ore = ore_list[idx]
        if not ore then break end

        local row_y = header_y + 2 + i
        local bg = (idx == selected_index) and C.table_highlight or C.panel_bg
        
        fillRect(TABLE_X + 2, row_y, TABLE_W - 3, 1, bg)
        
        local is_available = (ore.size or 0) >= ore.give.amount
        local text_color = is_available and C.text_main or C.text_dim
        if idx == selected_index then text_color = C.white end

        writeText(cx[1], row_y, string.format("%02d", idx), C.text_dim, bg)
        writeText(cx[2], row_y, clip(ore.take.label, 20), text_color, bg)
        writeText(cx[3], row_y, "0", C.text_dim, bg) -- У вас (можно заменить на реальный подсчет)
        writeText(cx[4], row_y, formatNumber(ore.size or 0), C.border, bg)
        writeText(cx[5], row_y, formatNumber(ore.take.amount) .. " -> " .. formatNumber(ore.give.amount), C.yellow, bg)
        writeText(cx[6], row_y, clip(ore.give.label, 14), C.text_main, bg)
        
        if i < max_rows and idx < #ore_list then
            gpu.setForeground(C.text_dark)
            gpu.setBackground(C.panel_bg)
            gpu.set(TABLE_X + 2, row_y + 1, string.rep("─", TABLE_W - 4))
        end
    end

    -- 3. ПРАВАЯ ПАНЕЛЬ ИНФО
    drawBox(INFO_X, INFO_Y, INFO_W, INFO_H, C.border, C.panel_bg)
    
    -- Кнопки меню
    local btn_y = INFO_Y + 2
    writeText(INFO_X + 2, btn_y, "ОБНОВИТЬ", C.text_main, C.panel_bg)
    writeText(INFO_X + 13, btn_y, "МЭ", C.purple, C.panel_bg)
    writeText(INFO_X + 20, btn_y, "ИСТОРИЯ", C.orange, C.panel_bg)
    
    gpu.setForeground(C.border)
    gpu.setBackground(C.panel_bg)
    gpu.set(INFO_X + 1, btn_y + 1, string.rep("─", INFO_W - 2))

    local sel_ore = ore_list[selected_index] or ore_list[1]
    
    writeText(INFO_X + 2, INFO_Y + 5, "ВЫБРАНА РУДА", C.text_main, C.panel_bg)
    writeText(INFO_X + 2, INFO_Y + 7, sel_ore.take.label, C.border, C.panel_bg)
    writeText(INFO_X + 2, INFO_Y + 9, "ИСТОРИЯ ИГРОКА: 0", C.text_dim, C.panel_bg)
    
    gpu.setForeground(C.text_dark)
    gpu.setBackground(C.panel_bg)
    gpu.set(INFO_X + 1, INFO_Y + 11, string.rep("─", INFO_W - 2))

    writeText(INFO_X + 2, INFO_Y + 13, "КУРС ОБМЕНА:", C.text_main, C.panel_bg)
    local rate_str = formatNumber(sel_ore.take.amount) .. " -> " .. formatNumber(sel_ore.give.amount)
    writeText(INFO_X + INFO_W - ulen(rate_str) - 2, INFO_Y + 13, rate_str, C.orange, C.panel_bg)

    writeText(INFO_X + 2, INFO_Y + 15, "В ИНВЕНТАРЕ:", C.text_dim, C.panel_bg)
    writeText(INFO_X + INFO_W - 4, INFO_Y + 15, "0", C.text_main, C.panel_bg)

    writeText(INFO_X + 2, INFO_Y + 16, "БУДЕТ ВЫДАНО:", C.text_dim, C.panel_bg)
    writeText(INFO_X + INFO_W - 4, INFO_Y + 16, "0", C.text_main, C.panel_bg)

    local avail = (sel_ore.size or 0) >= sel_ore.give.amount
    local avail_text = avail and "● РЕСУРС ДОСТУПЕН" or "● НЕТ В МЭ"
    local avail_color = avail and C.green or C.red
    writeText(INFO_X + 2, INFO_Y + 18, avail_text, avail_color, C.panel_bg)

    -- 4. НИЖНЯЯ ПАНЕЛЬ (Пакетный обмен)
    drawBox(BOTTOM_X, BOTTOM_Y, BOTTOM_W, BOTTOM_H, C.border, C.panel_bg, "ПАКЕТНЫЙ ОБМЕН")
    writeText(BOTTOM_X + 2, BOTTOM_Y + 1, "Встаньте на PIM для автоматического обмена", C.text_dim, C.panel_bg)
    
    writeText(BOTTOM_X + 45, BOTTOM_Y + 1, "ВИДОВ: 0", C.text_main, C.panel_bg)
    writeText(BOTTOM_X + 45, BOTTOM_Y + 2, "ПРИНИМАЕМ: 0", C.text_main, C.panel_bg)
    writeText(BOTTOM_X + 45, BOTTOM_Y + 3, "К ВЫДАЧЕ: 0", C.text_main, C.panel_bg)
    
    writeText(BOTTOM_X + BOTTOM_W - 30, BOTTOM_Y + 1, "СТАТУС PIM: ОЖИДАНИЕ", C.yellow, C.panel_bg)
    writeText(BOTTOM_X + BOTTOM_W - 30, BOTTOM_Y + 2, "CFG: v6", C.text_dim, C.panel_bg)
    writeText(BOTTOM_X + BOTTOM_W - 30, BOTTOM_Y + 3, "МЭ: ПОДКЛЮЧЕНА", C.green, C.panel_bg)

    writeText(BOTTOM_X + 2, BOTTOM_Y + BOTTOM_H - 1, "ОБЩАЯ СТАТИСТИКА: " .. formatNumber(totalOreInME) .. " РУДЫ", C.text_main, C.panel_bg)

    -- 5. СТАТУС БЛОК
    fillRect(STATUS_X, STATUS_Y, STATUS_W, STATUS_H, C.panel_bg)
    gpu.setForeground(C.border)
    gpu.setBackground(C.panel_bg)
    gpu.set(STATUS_X, STATUS_Y, "│")
    for i = 1, STATUS_H - 2 do
        gpu.set(STATUS_X, STATUS_Y + i, "│")
    end
    
    writeText(STATUS_X + 2, STATUS_Y + 1, "СТАТУС ● " .. status_msg, status_color, C.panel_bg)
    writeText(STATUS_X + 2, STATUS_Y + 2, "Для обмена встаньте на PIM. Руда принимается автоматически.", C.text_dim, C.panel_bg)

    -- 6. ФУТЕР (Нижняя полоса)
    local footer_y = h
    fillRect(1, footer_y, w, 1, C.table_highlight)
    writeText(1, footer_y, string.rep("─", w), C.border, C.table_highlight)
    writeText(w - 22, footer_y, "[ " .. player_name .. " ] [ v 4.4.7 ]", C.text_main, C.table_highlight)
end

-- ЛОГИКА ОБМЕНА
local function giveIngot(toGive, ore, index)
    local totalGive = 0
    local giveDamage = ore.give.damage or 0
    while totalGive < toGive do
        local giveSize = math.min(toGive - totalGive, ore.maxSize)
        local success, res = pcall(me.exportItem, { id = ore.give.name, dmg = giveDamage }, EXPORT_DIR, giveSize)
        if success and res and res.size and res.size > 0 then
            totalGive = totalGive + res.size
            ore_list[index].size = ore_list[index].size - res.size
        else
            status_msg = "Ошибка выдачи слитков!"
            status_color = C.red
            drawInterface()
            os.sleep(1)
        end
    end
end

local function exchangeOre(slot, ore, index)
    local curSlot = pim.getStackInSlot(slot)
    if not curSlot then return false end
    local userOreSize = curSlot.qty
    local takeSize = userOreSize - (userOreSize % ore.take.amount)
    if takeSize == 0 then return true end
    local giveSize = (takeSize / ore.take.amount) * ore.give.amount
    if ore.size < giveSize then return false end
    
    local takedOre = pim.pushItem(PUSH_DIR, slot, takeSize)
    if takedOre and takedOre > 0 then
        local actualGive = math.floor(takedOre / ore.take.amount) * ore.give.amount
        status_msg = string.format("Меняю %d %s на %d %s", takedOre, ore.take.label, actualGive, ore.give.label)
        status_color = C.white
        drawInterface()
        giveIngot(actualGive, ore, index)
    end
    return true
end

local function checkInventory()
    status_msg = "Сканирую инвентарь..."
    status_color = C.border
    drawInterface()
    
    local size = pim.getInventorySize()
    local data = pim.getAllStacks(0)
    for slot = 1, size do
        if data[slot] then
            for index, ore in pairs(ore_list) do
                local needDamage = ore.take.damage or 0
                if data[slot].id == ore.take.name and data[slot].dmg == needDamage then
                    exchangeOre(slot, ore, index)
                end
            end
        end
    end
    status_msg = "QQ-SHOP готов. Ожидаю игрока на PIM."
    status_color = C.green
    updIngotsSize()
    drawInterface()
end

-- Обработка событий
local function main()
    updIngotsSize()
    drawInterface()
    
    while true do
        local ev, p1, p2, p3, p4, p5 = event.pull(1)
        
        if ev == "player_on" then
            player_name = p1
            status_msg = "Приветствую, " .. player_name .. "! Начинаю обмен"
            status_color = C.green
            drawInterface()
            checkInventory()
            
        elseif ev == "player_off" then
            player_name = "---"
            status_msg = "QQ-SHOP готов. Ожидаю игрока на PIM."
            status_color = C.green
            drawInterface()
            
        elseif ev == "key_down" then
            local char, code = p3, p4
            if code == 200 then -- Up
                selected_index = math.max(1, selected_index - 1)
                drawInterface()
            elseif code == 208 then -- Down
                selected_index = math.min(#ore_list, selected_index + 1)
                drawInterface()
            elseif char == 7 then -- Ctrl+G (Админ панель)
                -- Здесь можно оставить вызов AdminUpdate.openPanel(p5) если нужно
            end
            
        elseif ev == "touch" then
            local x, y = p3, p4
            -- Клик по таблице
            if x > TABLE_X and x < TABLE_X + TABLE_W and y > TABLE_Y + 3 and y < TABLE_Y + TABLE_H - 1 then
                local clicked_row = math.floor(y - (TABLE_Y + 3)) + 1 + scroll_y
                if clicked_row <= #ore_list then
                    selected_index = clicked_row
                    drawInterface()
                end
            end
            -- Клик по кнопке "ОБНОВИТЬ"
            if x > INFO_X + 2 and x < INFO_X + 10 and y == INFO_Y + 2 then
                updIngotsSize()
                status_msg = "Данные МЭ обновлены"
                status_color = C.border
                drawInterface()
            end
        end
        
        -- Авто-обновление раз в 30 секунд
        if os.clock() % 30 < 1 then
            updIngotsSize()
            drawInterface()
        end
    end
end

local success, err = pcall(main)
if not success then
    gpu.setBackground(C.bg)
    gpu.setForeground(C.red)
    gpu.fill(1, 1, w, h, " ")
    gpu.set(2, 2, "Ошибка exchanger.lua: " .. tostring(err))
end
