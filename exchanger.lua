-- ============================================================
-- PI SHOP EXCHANGER v6.0 (ANIMATED GUI)
-- Полностью новый интерфейс с анимациями
-- ============================================================
local component = require("component")
local event = require("event")
local computer = require("computer")
local unicode = require("unicode")
local fs = require("filesystem")
local serialization = require("serialization")

local gpu = component.gpu
local pim = component.isAvailable("pim") and component.pim or nil
local me = component.isAvailable("me_interface") and component.me_interface or nil

-- Настройка разрешения (160x50 для широких мониторов)
local W, H = 160, 50
local maxW, maxH = gpu.maxResolution()
if maxW < 160 then W, H = maxW, maxH end
pcall(gpu.setResolution, W, H)
W, H = gpu.getResolution()

-- ============================================================
-- ЦВЕТОВАЯ ПАЛИТРА (PI THEME)
-- ============================================================
local C = {
    bg = 0x05050A,          -- Глубокий темный фон
    panel = 0x0E101A,       -- Фон панелей
    panel_light = 0x1A1D2E, -- Светлее для карточек
    border = 0x7B2CBF,      -- Фиолетовый акцент
    accent = 0x9D4EDD,      -- Яркий фиолетовый
    accent_glow = 0xC792EA, -- Светящийся фиолетовый
    cyan = 0x00F5D4,        -- Неоновый циан (для инфо)
    text_main = 0xEAEAEA,
    text_dim = 0x6A6A8A,
    green = 0x00FF88,
    red = 0xFF3366,
    yellow = 0xFFD700,
    select = 0x2A1B4D,      -- Выделение строки
    header_bg = 0x15102A,
}

-- ============================================================
-- КОНФИГУРАЦИЯ И ДАННЫЕ
-- ============================================================
local VERSION = "v 6.0"
local AUTHOR = "KaRMa__"
local EXPORT_DIR = "UP"
local PUSH_DIR = "DOWN"

local ore_list = {
    { take = { label = "Алмазная руда", name = "minecraft:diamond_ore", amount = 1 }, give = { label = "Алмаз", name = "minecraft:diamond", amount = 2 } },
    { take = { label = "Железная руда", name = "minecraft:iron_ore", amount = 3 }, give = { label = "Железный слиток", name = "minecraft:iron_ingot", amount = 7 } },
    { take = { label = "Золотая руда", name = "minecraft:gold_ore", amount = 3 }, give = { label = "Золотой слиток", name = "minecraft:gold_ingot", amount = 7 } },
    { take = { label = "Лазуритовая руда", name = "minecraft:lapis_ore", amount = 1 }, give = { label = "Лазурит", name = "minecraft:dye", damage = 4.0, amount = 7 } },
    { take = { label = "Красная руда", name = "minecraft:redstone_ore", amount = 1 }, give = { label = "Блок красного камня", name = "minecraft:redstone_block", amount = 1 } },
    { take = { label = "Угольная руда", name = "minecraft:coal_ore", amount = 1 }, give = { label = "Уголь", name = "minecraft:coal", amount = 3 } },
    { take = { label = "Медная руда", name = "IC2:blockOreCopper", amount = 3 }, give = { label = "Медный слиток", name = "IC2:itemIngot", amount = 7 } },
    { take = { label = "Оловянная руда", name = "IC2:blockOreTin", amount = 3 }, give = { label = "Оловянный слиток", name = "IC2:itemIngot", damage = 1.0, amount = 7 } },
    { take = { label = "Серебряная руда", name = "ThermalFoundation:Ore", damage = 2.0, amount = 1 }, give = { label = "Серебрянный слиток", name = "IC2:itemIngot", damage = 6.0, amount = 2 } },
    { take = { label = "Платиновая руда", name = "ThermalFoundation:Ore", damage = 5.0, amount = 1 }, give = { label = "Измельчённая платина", name = "ThermalFoundation:material", damage = 37.0, amount = 2 } },
    { take = { label = "Никелевая руда", name = "ThermalFoundation:Ore", damage = 4.0, amount = 1 }, give = { label = "Никелевый слиток", name = "ThermalFoundation:material", damage = 68.0, amount = 2 } },
    { take = { label = "Дракониевая руда", name = "DraconicEvolution:draconiumOre", amount = 1 }, give = { label = "Дракониевая пыль", name = "DraconicEvolution:draconiumDust", amount = 2 } },
    { take = { label = "Изумрудная руда", name = "minecraft:emerald_ore", amount = 1 }, give = { label = "Изумруд", name = "minecraft:emerald", amount = 2 } }
}

-- ============================================================
-- СОСТОЯНИЕ UI И АНИМАЦИЙ
-- ============================================================
local selected_idx = 1
local scroll_offset = 0
local total_me_items = 0
local status_msg = "Добро пожаловать в PI SHOP. Ожидаю игрока..."
local status_color = C.cyan
local player_name = "---"
local tick = 0
local marquee_offset = 0
local progress_bar = 0
local is_scanning = false

-- ============================================================
-- ХЕЛПЕРЫ
-- ============================================================
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
    
    gpu.set(x, y, "╭" .. string.rep("─", w - 2) .. "╮")
    gpu.set(x, y + h - 1, "╰" .. string.rep("─", w - 2) .. "╯")
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

-- Анимация прогресс-бара
local function drawProgressBar(x, y, w, percent)
    local inner = w - 2
    local filled = math.floor(inner * math.min(1, math.max(0, percent)))
    gpu.setForeground(C.border)
    gpu.set(x, y, "[")
    gpu.set(x + w - 1, y, "]")
    if filled > 0 then
        gpu.setBackground(C.accent)
        gpu.fill(x + 1, y, filled, 1, " ")
    end
    if inner - filled > 0 then
        gpu.setBackground(C.panel_light)
        gpu.fill(x + 1 + filled, y, inner - filled, 1, " ")
    end
end

-- ============================================================
-- ЛОГИКА МЭ
-- ============================================================
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

-- ============================================================
-- ОТРИСОВКА ИНТЕРФЕЙСА (С АНИМАЦИЯМИ)
-- ============================================================
local function drawGUI()
    fillRect(1, 1, W, H, C.bg)

    -- ================= 1. ШАПКА =================
    local header_h = 5
    fillRect(1, 1, W, header_h, C.bg)
    
    -- Логотип PI SHOP с пульсацией
    local logo_color = (tick % 20 < 10) and C.accent or C.accent_glow
    writeText(3, 2, "████  ██  ██████  ██  ██  ██████  ██████", logo_color, C.bg)
    writeText(3, 3, "█  █  ██  ██      ██  ██  ██  ██  ██  ██", C.text_main, C.bg)
    writeText(3, 4, "████  ██  ██████  ██████  ██████  ██████", C.border, C.bg)
    
    -- Индикатор ONLINE с мигающей точкой
    local dot_color = (tick % 10 < 5) and C.green or C.text_dim
    writeText(W - 15, 2, "● ONLINE", dot_color, C.bg)
    
    -- Часы
    local time_str = os.date("%d.%m.%Y %H:%M:%S")
    writeText(W - ulen(time_str) - 2, 4, time_str, C.text_dim, C.bg)
    
    -- Декоративные полосы
    gpu.setForeground(C.border)
    gpu.setBackground(C.bg)
    gpu.set(1, 5, string.rep("─", W))
    gpu.setForeground(C.accent)
    gpu.set(1, 6, string.rep("═", W))

    -- ================= 2. ЛЕВАЯ ПАНЕЛЬ (СПИСОК РУД) =================
    local tbl_x, tbl_y = 2, 8
    local tbl_w = math.floor(W * 0.62)
    local tbl_h = H - 16
    drawBox(tbl_x, tbl_y, tbl_w, tbl_h, " КАТАЛОГ РЕСУРСОВ ", C.border, C.panel)

    local col_x = { tbl_x + 2, tbl_x + 5, tbl_x + 28, tbl_x + 38, tbl_x + 50, tbl_x + 62 }
    local head_y = tbl_y + 2
    
    -- Заголовки
    writeText(col_x[1], head_y, "#", C.text_dim, C.panel)
    writeText(col_x[2], head_y, "ВИД РУДЫ", C.text_dim, C.panel)
    writeText(col_x[3], head_y, "У ВАС", C.text_dim, C.panel)
    writeText(col_x[4], head_y, "В МЭ", C.text_dim, C.panel)
    writeText(col_x[5], head_y, "КУРС", C.text_dim, C.panel)
    writeText(col_x[6], head_y, "ВЫДАЕТСЯ", C.text_dim, C.panel)
    
    gpu.setForeground(C.border)
    gpu.setBackground(C.panel)
    gpu.set(tbl_x + 1, head_y + 1, string.rep("─", tbl_w - 2))

    -- Список
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
        
        -- Анимация выделения (пульсирующий фон)
        local bg_col = C.panel
        if is_sel then
            bg_col = (tick % 20 < 10) and C.select or C.panel_light
        end
        
        local txt_col = is_sel and C.text_main or C.text_dim
        fillRect(tbl_x + 1, row_y, tbl_w - 2, 1, bg_col)
        
        -- Курсор выбора (анимированный)
        local cursor = is_sel and ((tick % 10 < 5) and "►" or " ") or " "
        writeText(col_x[1] - 1, row_y, cursor, C.accent, bg_col)
        writeText(col_x[1], row_y, string.format("%02d", idx), txt_col, bg_col)
        
        writeText(col_x[2], row_y, clip(ore.take.label, 21), txt_col, bg_col)
        writeText(col_x[3], row_y, "0", C.text_dim, bg_col)
        writeText(col_x[4], row_y, formatNum(ore.size or 0), C.cyan, bg_col)
        
        local rate_str = tostring(ore.take.amount) .. " ► " .. tostring(ore.give.amount)
        writeText(col_x[5], row_y, rate_str, C.yellow, bg_col)
        
        local give_col = (ore.size or 0) >= ore.give.amount and C.green or C.red
        writeText(col_x[6], row_y, clip(ore.give.label, 15), give_col, bg_col)
    end

    -- ================= 3. ПРАВАЯ ПАНЕЛЬ (ИНФО) =================
    local info_x = tbl_w + 4
    local info_w = W - info_x - 2
    local info_h = tbl_h
    drawBox(info_x, tbl_y, info_w, info_h, " ДЕТАЛИ ", C.border, C.panel)

    local sel_ore = ore_list[selected_idx] or ore_list[1]
    
    -- Кнопки (анимированные)
    local btn_y = tbl_y + 2
    writeText(info_x + 2, btn_y, "ОБНОВИТЬ", (tick % 30 < 15) and C.cyan or C.text_dim, C.panel)
    writeText(info_x + 14, btn_y, "МЭ", C.purple, C.panel)
    writeText(info_x + 20, btn_y, "ИСТОРИЯ", C.yellow, C.panel)
    
    gpu.setForeground(C.border)
    gpu.setBackground(C.panel)
    gpu.set(info_x + 1, btn_y + 1, string.rep("─", info_w - 2))

    -- Карточка ресурса
    writeText(info_x + 2, tbl_y + 4, "ВЫБРАНА РУДА:", C.text_dim, C.panel)
    writeText(info_x + 2, tbl_y + 6, "📦 " .. clip(sel_ore.take.label, info_w - 6), C.accent_glow, C.panel)
    
    writeText(info_x + 2, tbl_y + 8, "РЕСУРС В МЭ:", C.text_dim, C.panel)
    local res_amount = formatNum(sel_ore.size or 0)
    writeText(info_x + info_w - ulen(res_amount) - 2, tbl_y + 8, res_amount, C.cyan, C.panel)
    
    gpu.setForeground(C.border)
    gpu.setBackground(C.panel)
    gpu.set(info_x + 1, tbl_y + 10, string.rep("─", info_w - 2))
    
    -- Курс
    writeText(info_x + 2, tbl_y + 12, "КУРС ОБМЕНА:", C.text_dim, C.panel)
    local rate_str = tostring(sel_ore.take.amount) .. " ► " .. tostring(sel_ore.give.amount)
    writeText(info_x + info_w - ulen(rate_str) - 2, tbl_y + 12, rate_str, C.yellow, C.panel)
    
    writeText(info_x + 2, tbl_y + 14, "В ИНВЕНТАРЕ:", C.text_dim, C.panel)
    writeText(info_x + info_w - 3, tbl_y + 14, "0", C.text_main, C.panel)
    
    writeText(info_x + 2, tbl_y + 15, "БУДЕТ ВЫДАНО:", C.text_dim, C.panel)
    writeText(info_x + info_w - 3, tbl_y + 15, "0", C.text_main, C.panel)
    
    -- Статус ресурса
    local has_res = (sel_ore.size or 0) >= sel_ore.give.amount
    local res_text = has_res and "✓ РЕСУРС ДОСТУПЕН" or "✗ НЕТ В МЭ"
    local res_col = has_res and C.green or C.red
    writeText(info_x + 2, tbl_y + 17, res_text, res_col, C.panel)

    -- Прогресс бар (анимация сканирования)
    if is_scanning then
        drawProgressBar(info_x + 2, tbl_y + 19, info_w - 4, progress_bar)
        writeText(info_x + 2, tbl_y + 20, "Сканирование МЭ...", C.cyan, C.panel)
    end

    -- ================= 4. НИЖНЯЯ ПАНЕЛЬ (СТАТИСТИКА) =================
    local bot_y = H - 8
    local bot_w = W - 4
    drawBox(2, bot_y, bot_w, 4, " ПАКЕТНЫЙ ОБМЕН ", C.border, C.panel)
    
    writeText(4, bot_y + 1, "Встаньте на PIM для автоматического обмена", C.text_dim, C.panel)
    
    writeText(45, bot_y + 1, "ВИДОВ: " .. #ore_list, C.text_main, C.panel)
    writeText(45, bot_y + 2, "ПРИНИМАЕМ: 0", C.text_main, C.panel)
    writeText(45, bot_y + 3, "К ВЫДАЧЕ: 0", C.text_main, C.panel)
    
    writeText(W - 35, bot_y + 1, "СТАТУС PIM: ОЖИДАНИЕ", C.yellow, C.panel)
    writeText(W - 35, bot_y + 2, "CFG: " .. VERSION, C.text_dim, C.panel)
    writeText(W - 35, bot_y + 3, "МЭ: ПОДКЛЮЧЕНА", C.green, C.panel)
    
    local total_str = "ОБЩАЯ СТАТИСТИКА: " .. formatNum(total_me_items) .. " РУДЫ"
    writeText(3, bot_y + 3, total_str, C.accent_glow, C.panel)

    -- ================= 5. СТАТУС И БЕГУЩАЯ СТРОКА =================
    local st_y = H - 3
    fillRect(2, st_y, W - 4, 3, C.panel)
    gpu.setForeground(C.border)
    gpu.setBackground(C.panel)
    gpu.set(2, st_y, "│")
    for i = 1, 2 do gpu.set(2, st_y + i, "│") end
    
    -- Анимированный текст статуса (Marquee)
    local full_text = "● СТАТУС: " .. status_msg .. "  •  PI SHOP • " .. VERSION .. "  •  "
    local text_len = ulen(full_text)
    local view_w = W - 8
    
    -- Смещение бегущей строки
    marquee_offset = marquee_offset + 1
    if marquee_offset > text_len then marquee_offset = 1 end
    
    local display_text = ""
    for i = 1, view_w do
        local char_idx = ((marquee_offset + i - 2) % text_len) + 1
        display_text = display_text .. unicode.sub(full_text, char_idx, char_idx)
    end
    
    writeText(4, st_y + 1, display_text, status_color, C.panel)
    
    -- Вторая строка
    writeText(4, st_y + 2, "Для обмена встаньте на PIM. Руда принимается автоматически.", C.text_dim, C.panel)

    -- ================= 6. ФУТЕР =================
    local foot_y = H
    fillRect(1, foot_y, W, 1, C.select)
    writeText(1, foot_y, string.rep("─", W), C.border, C.select)
    local footer_text = "[ " .. player_name .. " ]  [ " .. VERSION .. " ]  [ by " .. AUTHOR .. " ]"
    writeText(W - ulen(footer_text) - 2, foot_y, footer_text, C.text_main, C.select)
end

-- ============================================================
-- ЛОГИКА ОБМЕНА
-- ============================================================
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
                        status_msg = string.format("Успешно обменяно %d %s", takedOre, ore.take.label)
                        status_color = C.green
                    end
                end
            end
        end
    end
end

-- ============================================================
-- ОБРАБОТКА СОБЫТИЙ И АНИМАЦИЙ
-- ============================================================
local function handleInput(ev, p1, p2, p3, p4)
    if ev == "player_on" or ev == "pim_player_enter" then
        player_name = p1 or "Unknown"
        status_msg = "Приветствую, " .. player_name .. "! Сканирую инвентарь..."
        status_color = C.accent
        is_scanning = true
        progress_bar = 0
        
    elseif ev == "player_off" or ev == "pim_player_leave" then
        player_name = "---"
        status_msg = "PI SHOP готов. Ожидаю игрока на PIM."
        status_color = C.cyan
        is_scanning = false
        
    elseif ev == "key_down" then
        local char, code = p3, p4
        if code == 200 then -- Up
            selected_idx = math.max(1, selected_idx - 1)
        elseif code == 208 then -- Down
            selected_idx = math.min(#ore_list, selected_idx + 1)
        elseif char == 13 then -- Enter
            if pim and me then
                status_msg = "Запуск обмена для " .. (ore_list[selected_idx].take.label) .. "..."
                status_color = C.yellow
                exchangeOre(ore_list[selected_idx], selected_idx)
                updateME()
            end
        end
        
    elseif ev == "touch" then
        local x, y = p3, p4
        local tbl_x, tbl_y = 2, 8
        local tbl_w = math.floor(W * 0.62)
        local tbl_h = H - 16
        local head_y = tbl_y + 2
        
        -- Клик по списку
        if x > tbl_x and x < tbl_x + tbl_w and y > head_y + 2 and y < head_y + 2 + (tbl_h - 5) then
            local clicked_row = math.floor(y - (head_y + 2)) + 1 + scroll_offset
            if clicked_row <= #ore_list then
                selected_idx = clicked_row
            end
        end
        
        -- Клик по кнопке обновить
        local info_x = tbl_w + 4
        if x >= info_x + 2 and x <= info_x + 9 and y == tbl_y + 2 then
            status_msg = "Обновление данных МЭ..."
            status_color = C.accent
            is_scanning = true
            progress_bar = 0
        end
    end
end

-- ============================================================
-- ГЛАВНЫЙ ЦИКЛ (TICK-BASED)
-- ============================================================
local function main()
    updateME()
    
    local last_tick = computer.uptime()
    local last_update = computer.uptime()
    
    while true do
        -- Обработка событий с таймаутом 0.05 (20 FPS)
        local ev, p1, p2, p3, p4 = event.pull(0.05)
        if ev then
            handleInput(ev, p1, p2, p3, p4)
        end
        
        local now = computer.uptime()
        
        -- Обновление анимаций (каждые 0.1 сек)
        if now - last_tick >= 0.1 then
            tick = tick + 1
            last_tick = now
            
            -- Анимация сканирования
            if is_scanning then
                progress_bar = progress_bar + 0.05
                if progress_bar >= 1.0 then
                    progress_bar = 0
                    is_scanning = false
                    updateME()
                    status_msg = "Сканирование завершено."
                    status_color = C.green
                end
            end
            
            drawGUI()
        end
        
        -- Автообновление данных МЭ каждые 5 секунд
        if now - last_update >= 5 then
            last_update = now
            if not is_scanning then
                updateME()
            end
        end
    end
end

-- Запуск с защитой от ошибок
local ok, err = pcall(main)
if not ok then
    gpu.setBackground(C.bg)
    gpu.setForeground(C.red)
    gpu.fill(1, 1, W, H, " ")
    gpu.set(2, 2, "Ошибка PI SHOP: " .. tostring(err))
    os.sleep(5)
end
