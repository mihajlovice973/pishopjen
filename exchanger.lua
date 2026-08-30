local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local serialization = require("serialization")
local inspect = {}

if not fs.exists("/lib/inspect.lua") then
    shell.execute("wget -q https://raw.githubusercontent.com/kikito/inspect.lua/master/inspect.lua /lib/inspect.lua")
end
inspect = require("inspect")

local me = com.isAvailable("me_interface") and com.me_interface or error("Интерфейс не подключен")
local pim = com.isAvailable("pim") and com.pim or error("PIM не подключен")
local gpu = com.gpu

local wantW, wantH = 120, 80
local maxW, maxH = gpu.maxResolution()
local w, h = math.min(wantW, maxW), math.min(wantH, maxH)
local defBG, defFG = gpu.getBackground(), gpu.getForeground()
if not pcall(gpu.setResolution, w, h) then
    for _, res in ipairs({ {120, 50}, {80, 25}, {50, 16} }) do
        if pcall(gpu.setResolution, res[1], res[2]) then
            w, h = res[1], res[2]
            break
        end
    end
end

local EXPORT_DIR = "UP"          
local PUSH_DIR = "DOWN"          
local STATS_FILE = "exchanger_stats.txt"   
local ACCENT_COLOR = 0x0088CC
local TABLE_BG = 0x1a1a2e
local DIVIDER_COLOR = 0x444444

local STATUS_Y = h - 3
local STATUS_Y2 = h - 2
local PROMPT_Y = h - 1
local SUBPROMPT_Y = h

local LIST_TOP = 9
local LIST_BOTTOM = h - 4

local COL_NAME_X = 4
local COL_BAR_X = 30
local COL_BAR_W = 25
local COL_ME_X = 57
local COL_RATE_X = 70
local COL_RESULT_X = 80

local MAX_LIMIT = 500000

local barColors = {
    0x00FFFF, 0xFFFFFF, 0xFFFF00, 0x0000FF, 0xFF0000,
    0x888888, 0x222222, 0x00AAFF, 0xFFFFFF, 0xFF8800,
    0x88DDFF, 0xAAAAAA, 0x55FFAA, 0xCCAA66, 0xAA00FF, 0x00FF00,
}

local oreColors = {
    0x00FFFF, 0xDDDDDD, 0xFFFF00, 0x0000FF, 0xFF0000,
    0x555555, 0xFFFFFF, 0x00AAFF, 0xEEEEEE, 0xFF8800,
    0xAAAAAA, 0xC0C0C0, 0x55FFAA, 0xCCAA66, 0xAA00FF, 0x00FF00,
}

local ore_list = {
    { take = { label = "Алмазная руда", name = "minecraft:diamond_ore", amount = 1 }, give = { label = "Алмаз", name = "minecraft:diamond", amount = 2 } },
    { take = { label = "Железная руда", name = "minecraft:iron_ore", amount = 3 }, give = { label = "Железный слиток", name = "minecraft:iron_ingot", amount = 7 } },
    { take = { label = "Золотая руда", name = "minecraft:gold_ore", amount = 3 }, give = { label = "Золотой слиток", name = "minecraft:gold_ingot", amount = 7 } },
    { take = { label = "Лазуритовая руда", name = "minecraft:lapis_ore", amount = 1 }, give = { label = "Лазурит", name = "minecraft:dye", damage = 4.0, amount = 7 } },
    { take = { label = "Красная руда", name = "minecraft:redstone_ore", amount = 1 }, give = { label = "Блок красного камня", name = "minecraft:redstone_block", amount = 1 } },
    { take = { label = "Угольная руда", name = "minecraft:coal_ore", amount = 1 }, give = { label = "Уголь", name = "minecraft:coal", amount = 3 } },
    { take = { label = "Руда истинного кварца", name = "appliedenergistics2:tile.OreQuartz", amount = 1 }, give = { label = "Кристалл ист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", amount = 3 } },
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

local currDir = shell.getWorkingDirectory()
local oresPath = currDir .. "/exchanger_ores.txt"
if fs.exists(oresPath) then
    local file = io.open(oresPath, "r")
    local ore_data = file:read("*all")
    file:close()
    local success, ore_table = pcall(load("return " .. ore_data))
    if success and type(ore_table) == "table" then
        ore_list = ore_table
    end
end

local function saveOres(ores)
    local f = io.open(oresPath, "w")
    if f then f:write(inspect(ores)):close() end
end

-- ============================================================
-- АДМИН-ПАНЕЛЬ
-- ============================================================
AdminUpdate = AdminUpdate or {}
AdminUpdate.CONFIG_PATH = "/admin_config.cfg"
AdminUpdate.FLAG_PATH = "/.just_updated"
AdminUpdate.DEFAULT_PASSWORD = "yVGF7wT"
AdminUpdate.FRAME = {tl="╔", tr="╗", bl="╚", br="╝", h="═", v="║"}
AdminUpdate.FILES = {
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/exchanger.lua", path = "/home/exchanger.lua" },
}

local function trimPlayerName(name)
    return string.gsub(tostring(name or ""), "^%s*(.-)%s*$", "%1")
end

local function samePlayerName(a, b)
    return string.lower(tostring(a or "")) == string.lower(tostring(b or ""))
end

function AdminUpdate.saveConfig(cfg)
    local f = io.open(AdminUpdate.CONFIG_PATH, "w")
    if not f then return false end
    f:write(serialization.serialize(cfg))
    f:close()
    return true
end

function AdminUpdate.loadConfig()
    local cfg = nil
    if fs.exists(AdminUpdate.CONFIG_PATH) then
        local f = io.open(AdminUpdate.CONFIG_PATH, "r")
        if f then
            local raw = f:read("*a")
            f:close()
            local ok, data = pcall(serialization.unserialize, raw)
            if ok and type(data) == "table" then cfg = data end
        end
    end
    if type(cfg) ~= "table" then cfg = {} end
    if type(cfg.admins) ~= "table" then cfg.admins = {"KaRMa__"} end
    if type(cfg.password) ~= "string" or cfg.password == "" then
        cfg.password = AdminUpdate.DEFAULT_PASSWORD
    end
    AdminUpdate.saveConfig(cfg)
    return cfg
end

function AdminUpdate.isAdmin(name, cfg)
    name = trimPlayerName(name)
    if name == "" then return false end
    cfg = cfg or AdminUpdate.loadConfig()
    for _, adminName in ipairs(cfg.admins or {}) do
        if samePlayerName(name, tostring(adminName or "")) then return true end
    end
    return false
end

function AdminUpdate.ulen(s)
    s = tostring(s or "")
    local _, cont = s:gsub("[\128-\191]", "")
    return #s - cont
end

function AdminUpdate.drawFrame(x, y, fw, fh)
    local f = AdminUpdate.FRAME
    gpu.set(x, y, f.tl .. string.rep(f.h, fw - 2) .. f.tr)
    for i = 1, fh - 2 do
        gpu.set(x, y + i, f.v .. string.rep(" ", fw - 2) .. f.v)
    end
    gpu.set(x, y + fh - 1, f.bl .. string.rep(f.h, fw - 2) .. f.br)
end

function AdminUpdate.drawPasswordScreen(password, statusText, statusColor)
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, w, h, " ")
    local fw, fh = math.min(60, w - 4), math.min(15, h - 4)
    local fx = math.floor((w - fw) / 2) + 1
    local fy = math.floor((h - fh) / 2) + 1
    local title = "АДМИН-ПАНЕЛЬ ОБНОВЛЕНИЯ"
    gpu.setForeground(0xFFFFFF)
    local tLen = AdminUpdate.ulen(title)
    gpu.set(fx + math.floor((fw - tLen) / 2), fy - 1, title)
    gpu.setForeground(ACCENT_COLOR)
    AdminUpdate.drawFrame(fx, fy, fw, fh)
    local prompt = "Введите пароль администратора:"
    gpu.setForeground(0xAAAAAA)
    gpu.set(fx + math.floor((fw - AdminUpdate.ulen(prompt)) / 2), fy + 3, prompt)
    local fieldW = math.min(34, fw - 4)
    local fieldX = fx + math.floor((fw - fieldW) / 2)
    local fieldY = fy + 6
    gpu.setBackground(0x333333)
    gpu.fill(fieldX, fieldY, fieldW, 1, " ")
    gpu.setForeground(ACCENT_COLOR)
    local masked = string.rep("*", #password)
    if #masked > fieldW - 2 then
        masked = string.sub(masked, -(fieldW - 2))
    end
    gpu.set(fieldX + 1, fieldY, masked .. "_")
    gpu.setBackground(0x000000)
    if statusText and statusText ~= "" then
        gpu.setForeground(statusColor or 0xFFFFFF)
        gpu.set(fx + math.floor((fw - AdminUpdate.ulen(statusText)) / 2), fy + 9, statusText)
    else
        gpu.setForeground(0x888888)
        gpu.set(fx + math.floor((fw - 28) / 2), fy + 9, "Enter - войти   Esc - отмена")
    end
end

function AdminUpdate.downloadFile(url, path)
    -- Удаляем старый файл
    if fs.exists(path) then
        fs.remove(path)
        os.sleep(1)
    end
    
    -- Скачиваем через shell.execute с флагом -f
    local result = shell.execute("wget -f " .. url .. " " .. path)
    
    -- Проверяем что файл скачался
    if fs.exists(path) and fs.size(path) > 0 then
        return true
    end
    
    return false
end

function AdminUpdate.run()
    local fw, fh = math.min(60, w - 4), math.min(15, h - 4)
    local fx = math.floor((w - fw) / 2) + 1
    local fy = math.floor((h - fh) / 2) + 1
    local total, done = #AdminUpdate.FILES, 0
    
    for _, file in ipairs(AdminUpdate.FILES) do
        gpu.setBackground(0x000000)
        gpu.fill(1, 1, w, h, " ")
        gpu.setForeground(0xFFFFFF)
        local title = "СКАЧИВАНИЕ ОБНОВЛЕНИЯ"
        gpu.set(fx + math.floor((fw - AdminUpdate.ulen(title)) / 2), fy - 1, title)
        gpu.setForeground(ACCENT_COLOR)
        AdminUpdate.drawFrame(fx, fy, fw, fh)
        
        gpu.setForeground(0xAAAAAA)
        gpu.set(fx + 2, fy + 2, "Файл:")
        gpu.setForeground(0xFFFFFF)
        gpu.set(fx + 2, fy + 3, fs.name(file.path))
        
        gpu.setForeground(0xAAAAAA)
        gpu.set(fx + 2, fy + 5, "Прогресс:")
        local p = done / total
        local barWidth = fw - 4
        local barX = fx + 2
        local barY = fy + 6
        gpu.setForeground(0x555555)
        gpu.set(barX, barY, "[")
        gpu.set(barX + barWidth - 1, barY, "]")
        local filled = math.floor((barWidth - 2) * p)
        if filled > 0 then
            gpu.setForeground(0x00FF00)
            for i = 1, filled do
                gpu.set(barX + i, barY, "█")
            end
        end
        local empty = (barWidth - 2) - filled
        if empty > 0 then
            gpu.setForeground(0x222222)
            for i = 1, empty do
                gpu.set(barX + filled + i, barY, "░")
            end
        end
        gpu.setForeground(0xFFFFFF)
        local progressText = string.format("Скачано: %d/%d (%.0f%%)", done, total, p * 100)
        gpu.set(fx + math.floor((fw - AdminUpdate.ulen(progressText)) / 2), fy + 8, progressText)
        
        gpu.setForeground(0xFFFF00)
        gpu.set(fx + 2, fy + 10, "Статус: Скачивание...")
        
        local success = false
        for attempt = 1, 3 do
            gpu.setForeground(0x88CCFF)
            gpu.set(fx + 2, fy + 10, "Статус: Попытка " .. attempt .. " из 3...")
            if AdminUpdate.downloadFile(file.url, file.path) then 
                success = true 
                break 
            end
            os.sleep(1)
        end
        
        gpu.setBackground(0x000000)
        gpu.fill(1, 1, w, h, " ")
        gpu.setForeground(0xFFFFFF)
        gpu.set(fx + math.floor((fw - AdminUpdate.ulen(title)) / 2), fy - 1, title)
        gpu.setForeground(ACCENT_COLOR)
        AdminUpdate.drawFrame(fx, fy, fw, fh)
        
        if success then
            done = done + 1
            gpu.setForeground(0x00FF00)
            gpu.set(fx + 2, fy + 3, "✓ Скачивание завершено!")
            gpu.setForeground(0x555555)
            gpu.set(barX, barY, "[")
            gpu.set(barX + barWidth - 1, barY, "]")
            gpu.setForeground(0x00FF00)
            for i = 1, barWidth - 2 do
                gpu.set(barX + i, barY, "█")
            end
            gpu.setForeground(0xFFFFFF)
            progressText = string.format("Скачано: %d/%d (100%%)", done, total)
            gpu.set(fx + math.floor((fw - AdminUpdate.ulen(progressText)) / 2), fy + 8, progressText)
            gpu.setForeground(0x00FF00)
            gpu.set(fx + 2, fy + 10, "Статус: Готово!")
            os.sleep(0.5)
        else
            gpu.setForeground(0xFF0000)
            gpu.set(fx + 2, fy + 3, "✗ Ошибка скачивания!")
            gpu.setForeground(0x555555)
            gpu.set(barX, barY, "[")
            gpu.set(barX + barWidth - 1, barY, "]")
            gpu.setForeground(0xFF0000)
            for i = 1, barWidth - 2 do
                gpu.set(barX + i, barY, "█")
            end
            gpu.setForeground(0xFFFFFF)
            progressText = string.format("Скачано: %d/%d (0%%)", done, total)
            gpu.set(fx + math.floor((fw - AdminUpdate.ulen(progressText)) / 2), fy + 8, progressText)
            gpu.setForeground(0xFF0000)
            gpu.set(fx + 2, fy + 10, "Статус: Ошибка!")
            os.sleep(2)
        end
    end
    
    if done == total then
        gpu.setBackground(0x000000)
        gpu.fill(1, 1, w, h, " ")
        gpu.setForeground(0xFFFFFF)
        gpu.set(fx + math.floor((fw - AdminUpdate.ulen("СКАЧИВАНИЕ ОБНОВЛЕНИЯ")) / 2), fy - 1, "СКАЧИВАНИЕ ОБНОВЛЕНИЯ")
        gpu.setForeground(ACCENT_COLOR)
        AdminUpdate.drawFrame(fx, fy, fw, fh)
        gpu.setForeground(0x00FF00)
        gpu.set(fx + 2, fy + 5, "✓ Все файлы скачаны!")
        gpu.setForeground(0xFFFFFF)
        gpu.set(fx + 2, fy + 8, "Перезагрузка...")
        for i = 5, 1, -1 do
            gpu.setForeground(0xFFFF00)
            local countdown = "Осталось: " .. i .. " сек"
            gpu.set(fx + math.floor((fw - AdminUpdate.ulen(countdown)) / 2), fy + 10, countdown)
            os.sleep(1)
        end
        computer.shutdown(true)
        return true
    end
    
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, w, h, " ")
    gpu.setForeground(0xFFFFFF)
    gpu.set(fx + math.floor((fw - AdminUpdate.ulen("СКАЧИВАНИЕ ОБНОВЛЕНИЯ")) / 2), fy - 1, "СКАЧИВАНИЕ ОБНОВЛЕНИЯ")
    gpu.setForeground(ACCENT_COLOR)
    AdminUpdate.drawFrame(fx, fy, fw, fh)
    gpu.setForeground(0xFF0000)
    gpu.set(fx + 2, fy + 5, " Ошибка обновления!")
    gpu.setForeground(0xFFFFFF)
    gpu.set(fx + 2, fy + 8, "Перезагрузка отменена.")
    os.sleep(3)
    return false
end

function AdminUpdate.openPanel(triggerPlayer)
    local cfg = AdminUpdate.loadConfig()
    local adminName = trimPlayerName(triggerPlayer or "")
    if not AdminUpdate.isAdmin(adminName, cfg) then 
        center(STATUS_Y2, "ДОСТУП ЗАПРЕЩЁН", 0xFF0000)
        os.sleep(1)
        return false 
    end
    local password = ""
    local done = false
    local result = nil
    
    AdminUpdate.drawPasswordScreen(password, "", 0xFFFFFF)
    
    local function keyHandler(_, _, char, code, player)
        local keyPlayer = trimPlayerName(player or "")
        if keyPlayer ~= "" and not samePlayerName(keyPlayer, adminName) then
            return
        end
        if code == 1 then
            done = true
            result = false
            event.cancel(keyHandler)
            return
        end
        if code == 14 then
            if #password > 0 then 
                password = string.sub(password, 1, -2) 
            end
            AdminUpdate.drawPasswordScreen(password, "", 0xFFFFFF)
            return
        end
        if code == 28 then
            if password == tostring(cfg.password or "") then
                AdminUpdate.drawPasswordScreen(password, "Доступ разрешён. Запуск...", 0x00FF00)
                os.sleep(0.5)
                done = true
                result = AdminUpdate.run()
                event.cancel(keyHandler)
                return
            end
            password = ""
            AdminUpdate.drawPasswordScreen(password, "Неверный пароль!", 0xFF0000)
            return
        end
        if char and type(char) == "number" and char >= 32 and char <= 126 then
            local c = unicode.char(char)
            if #password < 32 then 
                password = password .. c 
            end
            AdminUpdate.drawPasswordScreen(password, "", 0xFFFFFF)
            return
        end
        if char and type(char) == "string" and #char == 1 then
            if #password < 32 then 
                password = password .. char 
            end
            AdminUpdate.drawPasswordScreen(password, "", 0xFFFFFF)
        end
    end
    
    event.listen("key_down", keyHandler)
    
    while not done do
        os.sleep(0.1)
    end
    
    return result
end

-- ============================================================
-- ОСНОВНЫЕ ФУНКЦИИ
-- ============================================================

local function drawListBorder()
    gpu.setForeground(ACCENT_COLOR)
    gpu.set(2, LIST_TOP, "╔" .. string.rep("═", w - 4) .. "╗")
    gpu.set(2, LIST_BOTTOM, "╚" .. string.rep("═", w - 4) .. "╝")
    for i = LIST_TOP + 1, LIST_BOTTOM - 1 do
        gpu.set(2, i, "║")
        gpu.set(w - 1, i, "║")
    end
    gpu.setBackground(TABLE_BG)
    gpu.fill(3, LIST_TOP + 1, w - 5, LIST_BOTTOM - LIST_TOP - 1, " ")
    gpu.setBackground(0x000000)
end

local function center(height, text, color)
    gpu.fill(2, height, w - 2, 1, " ")
    gpu.setForeground(color)
    local textLen = unicode.len(text)
    if textLen > w - 2 then textLen = w - 2 end
    local x = math.floor(w / 2 - textLen / 2)
    if x < 2 then x = 2 end
    if x + textLen > w - 1 then x = w - 1 - textLen end
    gpu.set(x, height, text)
end

local function drawCenteredText(y, text, color)
    gpu.setForeground(color)
    local textLen = unicode.len(text)
    local x = math.floor(w / 2 - textLen / 2)
    if x < 2 then x = 2 end
    gpu.set(x, y, text)
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

local function updIngotsSize()
    if #ore_list < 1 then return false end
    local totalOre = 0
    for _, ore in ipairs(ore_list) do
        local giveDamage = ore.give.damage or 0
        local success, item = pcall(function()
            return me.getItemDetail({ id = ore.give.name, dmg = giveDamage }).basic()
        end)
        if success and item then
            ore.size = item.qty
            totalOre = totalOre + item.qty
            ore.maxSize = item.max_size or 64
        else
            ore.size = 0
            ore.maxSize = 64
        end
    end
    return totalOre > 0
end

local function drawProgressBar(x, y, width, percent, color)
    percent = math.max(0, math.min(1, percent))
    local innerW = width - 2
    local filled = math.floor(innerW * percent)
    gpu.setForeground(0x888888)
    gpu.set(x, y, "[")
    gpu.set(x + width - 1, y, "]")
    if filled == 0 and percent >= 0 then
        filled = 1
    end
    if filled > 0 then
        gpu.setForeground(color or ACCENT_COLOR)
        for i = 1, filled do
            gpu.set(x + i, y, "█")
        end
    end
    local empty = innerW - filled
    if empty > 0 then
        gpu.setForeground(0x333333)
        for i = 1, empty do
            gpu.set(x + filled + i, y, "░")
        end
    end
end

local function drawInfo(type)
    if type == "full" then
        gpu.setBackground(TABLE_BG)
        gpu.fill(3, LIST_TOP + 1, w - 5, LIST_BOTTOM - LIST_TOP - 1, " ")
        gpu.setForeground(ACCENT_COLOR)
        gpu.set(3, LIST_TOP + 1, string.rep("═", w - 5))
        gpu.setForeground(0x88CCFF)
        gpu.set(COL_NAME_X, LIST_TOP + 2, "ИСХОДНЫЙ ПРЕДМЕТ")
        gpu.set(COL_BAR_X, LIST_TOP + 2, "ПРОГРЕСС")
        gpu.set(COL_ME_X, LIST_TOP + 2, "В МЭ")
        gpu.set(COL_RATE_X, LIST_TOP + 2, "КУРС")
        gpu.set(COL_RESULT_X, LIST_TOP + 2, "РЕЗУЛЬТАТ")
        gpu.setForeground(ACCENT_COLOR)
        gpu.set(3, LIST_TOP + 3, string.rep("═", w - 5))
    end
    
    local start_line = LIST_TOP + 4
    for i, ore in pairs(ore_list) do
        local print_row = start_line + (i - 1) * 2
        if print_row >= LIST_BOTTOM - 1 then break end
        
        gpu.setBackground(TABLE_BG)
        gpu.fill(3, print_row, w - 5, 1, " ")
        
        gpu.setForeground(oreColors[i] or 0xFFFFFF)
        gpu.set(COL_NAME_X, print_row, ore.take.label)
        
        local percent = math.min(1, (ore.size or 0) / MAX_LIMIT)
        local barColor = barColors[i] or ACCENT_COLOR
        drawProgressBar(COL_BAR_X, print_row, COL_BAR_W, percent, barColor)
        
        gpu.setForeground(0x88CCFF)
        local meText = formatNumber(ore.size or 0) .. "/500K"
        gpu.set(COL_ME_X, print_row, meText)
        
        -- КУРС рисуем ВСЕГДА (убрано условие if type == "full")
        gpu.setForeground(0x88CCFF)
        local takeAmount = formatNumber(ore.take.amount)
        local giveAmount = formatNumber(ore.give.amount)
        gpu.set(COL_RATE_X, print_row, takeAmount .. " > " .. giveAmount)
        
        gpu.setForeground(oreColors[i] or 0xFFFFFF)
        gpu.set(COL_RESULT_X, print_row, ore.give.label)
        
        if type == "full" and i < #ore_list and (print_row + 1) < LIST_BOTTOM - 1 then
            gpu.setBackground(TABLE_BG)
            gpu.setForeground(DIVIDER_COLOR)
            gpu.fill(3, print_row + 1, w - 5, 1, " ")
            gpu.set(3, print_row + 1, string.rep("─", w - 6))
        end
    end
    
    -- Вертикальные разделители ВСЕГДА
    gpu.setForeground(ACCENT_COLOR)
    local dividers = {COL_BAR_X - 1, COL_ME_X - 1, COL_RATE_X - 1, COL_RESULT_X - 1}
    for _, dx in ipairs(dividers) do
        for row = LIST_TOP + 4, LIST_BOTTOM - 1 do
            gpu.set(dx, row, "║")
        end
    end
    
    gpu.setBackground(0x000000)
end

local function updInfo(type)
    type = type or "full"
    local check = updIngotsSize()
    if not check then
        center(STATUS_Y2, "Нет соединения с МЭ или руды не настроены", 0xff0000)
    end
    drawInfo(type)
    return check
end

local stats = { ores = 0, ingots = 0 }
local function saveStats()
    local f = io.open(STATS_FILE, "a")
    if f then
        f:write(string.format("[%s] Переработано руды: %d, выдано слитков: %d\n", os.date("%Y-%m-%d %H:%M:%S"), stats.ores, stats.ingots))
        f:close()
    end
end

local function giveIngot(toGive, ore, index)
    local totalGive = 0
    local giveDamage = ore.give.damage or 0
    while totalGive < toGive do
        local giveSize = math.min(toGive - totalGive, ore.maxSize)
        local success, res = pcall(me.exportItem, { id = ore.give.name, dmg = giveDamage }, EXPORT_DIR, giveSize)
        if success and res and res.size and res.size > 0 then
            totalGive = totalGive + res.size
            ore_list[index].size = ore_list[index].size - res.size
            stats.ingots = stats.ingots + res.size
        else
            center(STATUS_Y, "Ошибка выдачи слитков! Проверьте место в инвентаре и направление.", 0xff0000)
            center(STATUS_Y2, string.format("Ожидаю выдать %d %s", toGive - totalGive, ore.give.label), 0xFFFFFF)
            os.sleep(1)
        end
    end
end

local function exchangeOre(slot, ore, index)
    local curSlot = pim.getStackInSlot(slot)
    if not curSlot then
        center(STATUS_Y2, "Вы сошли с PIM, обмен прерван.", 0xff0000)
        os.sleep(1)
        return false
    end
    local userOreSize = curSlot.qty
    local takeSize = userOreSize - (userOreSize % ore.take.amount)
    if takeSize == 0 then return true end
    local giveSize = (takeSize / ore.take.amount) * ore.give.amount
    if ore.size < giveSize then
        center(STATUS_Y2, string.format("%s недостаточно для обмена (в МЭ %d, надо %d)", ore.give.label, ore.size, giveSize), 0xff0000)
        os.sleep(2)
        return false
    end
    local takedOre = pim.pushItem(PUSH_DIR, slot, takeSize)
    if not takedOre or takedOre == 0 then
        center(STATUS_Y2, "Не удалось вытолкнуть руду. Проверьте, что снизу есть ME интерфейс.", 0xff0000)
        os.sleep(2)
        return false
    end
    local actualGive = math.floor(takedOre / ore.take.amount) * ore.give.amount
    stats.ores = stats.ores + takedOre
    center(STATUS_Y2, string.format("Меняю %d %s на %d %s", takedOre, ore.take.label, actualGive, ore.give.label), 0xffffff)
    giveIngot(actualGive, ore, index)
    gpu.fill(2, STATUS_Y2, w - 2, 1, " ")
    return true
end

local function checkInventory()
    for i = 2, 1, -1 do
        center(STATUS_Y2, string.format("Обмен через %d сек...", i), 0x505050)
        os.sleep(1)
    end
    local size = pim.getInventorySize()
    local data = pim.getAllStacks(0)
    local forceBreak = false
    for slot = 1, size do
        if forceBreak then break end
        if data[slot] then
            for index, ore in pairs(ore_list) do
                local needDamage = ore.take.damage or 0
                if data[slot].id == ore.take.name and data[slot].dmg == needDamage then
                    if not exchangeOre(slot, ore, index) then
                        forceBreak = true
                        break
                    end
                end
            end
        end
    end
    drawInfo("ingots")
    center(STATUS_Y2, string.format("Обмен окончен! Переработано: %d руды → %d слитков", stats.ores, stats.ingots), 0xffffff)
    saveStats()
    if pim.getInventoryName() ~= "pim" then
        return checkInventory()
    else
        event.push("player_off")
    end
end

local lastCtrlCUser = nil
local function isAdmin(user)
    if not user then return false end
    local users = table.pack(computer.users())
    for i = 1, users.n do
        if users[i] == user then return true end
    end
    return false
end

local function drawLogo(y, color)
    local dragonLines = {
        "            ██████╗ ██╗    ███████╗██╗  ██╗ ██████╗ ██████╗ ",
        "            ██╔══██╗██║    ██╔════╝██║  ██║██╔═══██╗██╔══██╗",
        "            ██████╔╝██║    ███████╗███████║██║   ██║██████╔╝",
        "            ██╔═══╝ ██║    ╚════██║██╔══██║██║   ██║██╔═══╝ ",
        "            ██║     ██║    ███████║██║  ██║╚██████╔╝██║     ",
        "            ╚═╝     ╚═╝    ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
    }
    local logoWidth = 74
    local startX = math.floor((w - logoWidth) / 2)
    if startX < 1 then startX = 1 end
    gpu.setForeground(0x9900FF)
    for i, line in ipairs(dragonLines) do
        gpu.set(startX, y + i - 1, line)
    end
end

local function redrawMain()
    gpu.fill(1, 1, w, h, " ")
    drawListBorder()
    updInfo()
    drawLogo(2, ACCENT_COLOR)
    drawCenteredText(8, "ОБМЕН РУДЫ НА СЛИТКИ", 0xAAAAAA)
    center(PROMPT_Y, "Для обмена встаньте на PIM и не сходите до окончания обмена", 0xffffff)
    center(SUBPROMPT_Y, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
end

local function handleEvent(eventName, ...)
    local args = { ... }
    if eventName == "key_down" then
        local address = args[1]
        local char = args[2]
        local code = args[3]
        local player = args[4]
        
        if (char == 7 or (type(char) == "string" and char == "\x07")) then
            if player and isAdmin(player) then
                local success, result = pcall(AdminUpdate.openPanel, player)
                if success then
                    redrawMain()
                else
                    gpu.setForeground(0xFF0000)
                    center(STATUS_Y2, "Ошибка: " .. tostring(result), 0xFF0000)
                    os.sleep(2)
                    redrawMain()
                end
            end
        end
        
        if char == 3 or (type(char) == "string" and char == "\x03") then
            if player and isAdmin(player) then
                lastCtrlCUser = player
            end
        end
    elseif eventName == "interrupted" then
        if lastCtrlCUser and isAdmin(lastCtrlCUser) then
            gpu.setBackground(defBG)
            gpu.setForeground(defFG)
            gpu.fill(1, 1, w, h, " ")
            os.exit()
            return true
        else
            lastCtrlCUser = nil
        end
    elseif eventName == "player_on" then
        if not updInfo("ingots") then return end
        center(STATUS_Y2, string.format("Приветствую, %s! Начинаю обмен", args[1]), 0xffffff)
        stats.ores = 0
        stats.ingots = 0
        checkInventory()
    elseif eventName == "player_off" then
        if not updInfo("ingots") then return end
        center(PROMPT_Y, "Для обмена встаньте на PIM и не сходите до окончания обмена", 0xffffff)
        center(SUBPROMPT_Y, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
    elseif eventName == "touch" and args[2] >= w - 38 and args[3] >= h - 1 and isAdmin(args[5]) then
        computer.beep(1500, 0.1)
        for i = 5, 1, -1 do
            center(STATUS_Y2, string.format("Начну сканировать инвентарь через %d сек...", i), 0x505050)
            os.sleep(1)
        end
        center(STATUS_Y2, "Сканирую...", 0xffffff)
        computer.beep(1500, 0.8)
        if pim.getInventoryName() ~= "pim" then
            ore_list = {}
            local data = pim.getAllStacks(0)
            local i = 10
            while i ~= 9 do
                if i == 18 or i == 27 then i = i + 1
                elseif i == 36 then i = 1
                end
                if data[i] and data[i+1] then
                    table.insert(ore_list, {
                        take = { label = data[i].display_name, name = data[i].id, damage = data[i].dmg, amount = math.floor(data[i].qty) },
                        give = { label = data[i+1].display_name, name = data[i+1].id, damage = data[i+1].dmg, amount = math.floor(data[i+1].qty) }
                    })
                end
                i = i + 2
            end
            saveOres(ore_list)
            center(STATUS_Y2, "Обмен записан!", 0x00ff00)
            computer.beep(500, 0.2)
            updInfo()
        else
            center(STATUS_Y2, "Не увидел инвентарь!", 0xff0000)
            computer.beep(2000, 0.2)
            computer.beep(2000, 0.2)
        end
        os.sleep(1)
        for i = 5, 1, -1 do
            center(STATUS_Y2, string.format("Заработаю через %d сек...", i), 0x505050)
            os.sleep(1)
        end
        center(SUBPROMPT_Y, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
    end
end

local function main()
    redrawMain()
    while true do
        handleEvent(event.pull(1))
    end
end

while true do
    local success, err = pcall(main)
    if not success then
        if err == "interrupted" then
            if lastCtrlCUser and isAdmin(lastCtrlCUser) then
                gpu.setBackground(defBG)
                gpu.setForeground(defFG)
                gpu.fill(1, 1, w, h, " ")
                break
            else
                lastCtrlCUser = nil
            end
        elseif type(err) == "string" and #err > 0 then
            local f = io.open(currDir .. "/exchanger_errors.txt", "ab")
            if f then f:write(err .. "\n"):close() end
            computer.beep(2000, 3)
        else
            break
        end
    end
end
