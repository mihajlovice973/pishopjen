local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local serialization = require("serialization")

-- ЖЕСТКО ЗАДАЕМ РАЗРЕШЕНИЕ 160x50
local w, h = 160, 50
local gpu = com.gpu
local defBG, defFG = gpu.getBackground(), gpu.getForeground()

if not pcall(gpu.setResolution, w, h) then
    error("Ваш GPU не поддерживает разрешение 160x50!")
end

local me = com.isAvailable("me_interface") and com.me_interface or error("ME Interface не найден")
local pim = com.isAvailable("pim") and com.pim or error("PIM не найден")

-- ЦВЕТА
local C_BG      = 0x0A0A0A
local C_PANEL   = 0x141414
local C_ACCENT  = 0x00CCFF
local C_TEXT    = 0xEEEEEE
local C_DIM     = 0x666666
local C_GREEN   = 0x00FF00
local C_RED     = 0xFF3333
local C_HIGHLIGHT = 0x005588
local C_YELLOW  = 0xFFCC00

local EXPORT_DIR = "UP"          
local PUSH_DIR = "DOWN"          
local selectedIndex = 1
local isPlayerOnPim = false
local currentPlayer = ""
local stats = { ores = 0, ingots = 0 }

-- СПИСОК РУД (Можете оставить свой полный список)
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
}

local function formatNumber(num)
    if num >= 1000000 then return string.format("%.1fM", num / 1000000) end
    if num >= 1000 then return string.format("%.1fK", num / 1000) end
    return tostring(num)
end

local function updME()
    for _, ore in ipairs(ore_list) do
        local damage = ore.give.damage or 0
        local success, item = pcall(function()
            return me.getItemDetail({ id = ore.give.name, dmg = damage }).basic()
        end)
        if success and item then
            ore.meSize = item.qty
            ore.maxSize = item.max_size or 64
        else
            ore.meSize = 0
            ore.maxSize = 64
        end
    end
end

local function updPIM()
    for _, ore in ipairs(ore_list) do
        ore.userSize = 0
        ore.userGive = 0
    end
    if not isPlayerOnPim then return end

    local data = pim.getAllStacks(0)
    for slot = 1, pim.getInventorySize() do
        if data[slot] then
            for _, ore in ipairs(ore_list) do
                local dmg = ore.take.damage or 0
                if data[slot].id == ore.take.name and data[slot].dmg == dmg then
                    ore.userSize = ore.userSize + data[slot].qty
                    local takeSize = data[slot].qty - (data[slot].qty % ore.take.amount)
                    ore.userGive = ore.userGive + math.floor(takeSize / ore.take.amount) * ore.give.amount
                end
            end
        end
    end
end

-- Отрисовка Логотипа (Ровный текстовый вариант)
local function drawLogo()
    gpu.setForeground(C_ACCENT)
    local logo = {
        "██████╗ ██╗     ███████╗██╗  ██╗ ██████╗ ██████╗ ",
        "██╔══██╗██║     ██╔════╝██║  ██║██╔═══██╗██╔══██╗",
        "██████╔╝██║     ███████╗███████║██║   ██║██████╔╝",
        "██╔═══╝ ██║     ╚════██║██╔══██║██║   ██║██╔═══╝ ",
        "██║     ███████╗███████║██║  ██║╚██████╔╝██║     ",
        "╚═╝     ╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
    }
    local startX = 4
    for i, line in ipairs(logo) do
        gpu.set(startX, 1 + i, line)
    end
end

local function drawHeader()
    gpu.setBackground(C_BG)
    gpu.fill(1, 1, w, h, " ")
    drawLogo()
    
    gpu.setForeground(C_GREEN)
    gpu.set(w - 12, 2, "● ONLINE")
    
    gpu.setForeground(C_TEXT)
    gpu.set(4, 9, "RESOURCE EXCHANGER")
    gpu.setForeground(C_DIM)
    gpu.set(4, 10, "Обмен ресурсов  •  курс  •  история")
    
    gpu.setForeground(C_ACCENT)
    gpu.set(2, 12, string.rep("═", w - 3))
end

local function drawTable()
    local pX, pY, pW, pH = 2, 13, 80, 30
    gpu.setBackground(C_PANEL)
    gpu.fill(pX, pY, pW, pH, " ")
    
    gpu.setForeground(C_ACCENT)
    gpu.set(pX + 2, pY + 1, "🔹 ОБМЕННИК РЕСУРСОВ")
    gpu.set(pX + pW - 20, pY + 1, "РУДА -> РЕСУРСЫ")
    
    gpu.setForeground(C_DIM)
    gpu.set(pX + 2, pY + 2, "#    ВИД РУДЫ              У ВАС      В МЭ     КУРС    ВЫДАЕТСЯ")
    gpu.set(pX + 2, pY + 3, string.rep("─", pW - 4))
    
    local startY = pY + 4
    for i = 1, math.min(#ore_list, pH - 5) do
        local ore = ore_list[i]
        local y = startY + i - 1
        
        if i == selectedIndex then
            gpu.setBackground(C_HIGHLIGHT)
        else
            gpu.setBackground(C_PANEL)
        end
        gpu.fill(pX + 2, y, pW - 4, 1, " ")
        
        gpu.setForeground(C_DIM)
        gpu.set(pX + 2, y, string.format("%02d", i))
        
        gpu.setForeground(C_TEXT)
        gpu.set(pX + 7, y, string.sub(ore.take.label, 1, 20))
        
        gpu.setForeground(C_DIM)
        gpu.set(pX + 29, y, tostring(ore.userSize or 0))
        
        gpu.setForeground(C_ACCENT)
        gpu.set(pX + 39, y, formatNumber(ore.meSize or 0))
        
        gpu.setForeground(C_YELLOW)
        gpu.set(pX + 48, y, ore.take.amount .. " > " .. ore.give.amount)
        
        gpu.setForeground(C_TEXT)
        gpu.set(pX + 57, y, string.sub(ore.give.label, 1, 18))
    end
    gpu.setBackground(C_BG)
end

local function drawDetails()
    local pX, pY, pW, pH = 84, 13, 74, 30
    gpu.setBackground(C_PANEL)
    gpu.fill(pX, pY, pW, pH, " ")
    
    gpu.setForeground(C_ACCENT)
    gpu.set(pX + 2, pY + 1, "ВЫБРАНА РУДА")
    gpu.set(pX + 2, pY + 2, string.rep("─", pW - 4))
    
    local ore = ore_list[selectedIndex]
    if ore then
        gpu.setForeground(C_TEXT)
        gpu.set(pX + 4, pY + 4, ore.take.label)
        
        gpu.setForeground(C_DIM)
        gpu.set(pX + 4, pY + 6, "ИСТОРИЯ ИГРОКА: 0")
        gpu.set(pX + 4, pY + 8, string.rep("─", pW - 8))
        
        gpu.setForeground(C_DIM)
        gpu.set(pX + 4, pY + 10, "КУРС ОБМЕНА:")
        gpu.setForeground(C_YELLOW)
        gpu.set(pX + pW - 10, pY + 10, ore.take.amount .. " -> " .. ore.give.amount)
        
        gpu.setForeground(C_DIM)
        gpu.set(pX + 4, pY + 12, "В ИНВЕНТАРЕ:")
        gpu.setForeground(C_TEXT)
        gpu.set(pX + pW - 10, pY + 12, tostring(ore.userSize or 0))
        
        gpu.setForeground(C_DIM)
        gpu.set(pX + 4, pY + 14, "БУДЕТ ВЫДАНО:")
        gpu.setForeground(C_TEXT)
        gpu.set(pX + pW - 10, pY + 14, tostring(ore.userGive or 0))
        
        gpu.set(pX + 4, pY + 17, string.rep("─", pW - 8))
        
        if (ore.meSize or 0) > 0 then
            gpu.setForeground(C_GREEN)
            gpu.set(pX + 4, pY + 19, "● РЕСУРС ДОСТУПЕН")
        else
            gpu.setForeground(C_RED)
            gpu.set(pX + 4, pY + 19, "● НЕТ В МЭ")
        end
    end
    gpu.setBackground(C_BG)
end

local statusMsg = "Ожидание игрока..."
local statusColor = C_GREEN

local function drawBottom()
    local pY = 44
    gpu.setForeground(C_DIM)
    gpu.set(2, pY, string.rep("─", w - 3))
    
    gpu.setForeground(C_ACCENT)
    gpu.set(2, pY + 1, "ПАКЕТНЫЙ ОБМЕН")
    gpu.setForeground(C_DIM)
    gpu.set(2, pY + 2, isPlayerOnPim and "Игрок на PIM. Идет обмен..." or "Встаньте на PIM для обмена")
    
    gpu.setForeground(C_DIM)
    gpu.set(70, pY + 1, "ВИДОВ: " .. #ore_list)
    gpu.set(70, pY + 2, "ПРИНИМАЕМ: " .. stats.ores)
    gpu.set(70, pY + 3, "К ВЫДАЧЕ: " .. stats.ingots)
    
    gpu.setForeground(C_DIM)
    gpu.set(130, pY + 1, "СТАТУС PIM: " .. (isPlayerOnPim and "АКТИВЕН" or "ОЖИДАНИЕ"))
    gpu.set(130, pY + 2, "МЭ: ПОДКЛЮЧЕНА")
    
    gpu.setForeground(C_ACCENT)
    gpu.set(2, h - 1, "╚" .. string.rep("═", w - 3) .. "╝")
    
    gpu.setForeground(C_DIM)
    gpu.set(4, h, "СТАТУС:")
    gpu.setForeground(statusColor)
    gpu.set(12, h, statusMsg)
end

local function redraw()
    drawHeader()
    drawTable()
    drawDetails()
    drawBottom()
end

-- ЛОГИКА ОБМЕНА
local function doExchange()
    if not isPlayerOnPim then return end
    updME()
    updPIM()
    redraw()
    
    local data = pim.getAllStacks(0)
    local changed = false
    
    for slot = 1, pim.getInventorySize() do
        if data[slot] then
            for index, ore in ipairs(ore_list) do
                local dmg = ore.take.damage or 0
                if data[slot].id == ore.take.name and data[slot].dmg == dmg then
                    local takeSize = data[slot].qty - (data[slot].qty % ore.take.amount)
                    if takeSize > 0 then
                        local giveSize = math.floor(takeSize / ore.take.amount) * ore.give.amount
                        
                        if (ore.meSize or 0) >= giveSize then
                            -- Выталкиваем руду
                            local pushed = pim.pushItem(PUSH_DIR, slot, takeSize)
                            if pushed and pushed > 0 then
                                local actualGive = math.floor(pushed / ore.take.amount) * ore.give.amount
                                stats.ores = stats.ores + pushed
                                
                                -- Выдаем слитки
                                local leftToGive = actualGive
                                local giveDmg = ore.give.damage or 0
                                while leftToGive > 0 do
                                    local chunk = math.min(leftToGive, ore.maxSize)
                                    local success, res = pcall(me.exportItem, {id = ore.give.name, dmg = giveDmg}, EXPORT_DIR, chunk)
                                    if success and res and res.size > 0 then
                                        leftToGive = leftToGive - res.size
                                        stats.ingots = stats.ingots + res.size
                                    else
                                        statusMsg = "Ошибка выдачи! Инвентарь полон?"
                                        statusColor = C_RED
                                        leftToGive = 0
                                        break
                                    end
                                end
                                changed = true
                            end
                        else
                            statusMsg = string.format("Недостаточно %s в МЭ!", ore.give.label)
                            statusColor = C_RED
                        end
                    end
                end
            end
        end
    end
    
    if changed then
        statusMsg = "Обмен завершен успешно!"
        statusColor = C_GREEN
    end
    updME()
    updPIM()
    redraw()
end

-- ГЛАВНЫЙ ЦИКЛ
updME()
redraw()

local timer = event.timer(1, function()
    if isPlayerOnPim then
        doExchange()
    else
        updME()
        redraw()
    end
end, math.huge)

while true do
    local e = {event.pull(0.1)}
    local evName = e[1]
    
    if evName == "key_down" then
        local code = e[4]
        if code == 200 or code == 44 then -- Вверх
            selectedIndex = selectedIndex - 1
            if selectedIndex < 1 then selectedIndex = #ore_list end
            redraw()
        elseif code == 208 or code == 45 then -- Вниз
            selectedIndex = selectedIndex + 1
            if selectedIndex > #ore_list then selectedIndex = 1 end
            redraw()
        end
        
    elseif evName == "player_on" then
        isPlayerOnPim = true
        currentPlayer = e[2] or "Игрок"
        stats.ores = 0
        stats.ingots = 0
        statusMsg = "Приветствую, " .. currentPlayer .. "! Начинаю обмен..."
        statusColor = C_TEXT
        updPIM()
        redraw()
        
    elseif evName == "player_off" then
        isPlayerOnPim = false
        currentPlayer = ""
        statusMsg = "Ожидание игрока на PIM..."
        statusColor = C_GREEN
        for _, ore in ipairs(ore_list) do
            ore.userSize = 0
            ore.userGive = 0
        end
        updME()
        redraw()
        
    elseif evName == "interrupted" then
        event.cancel(timer)
        gpu.setBackground(defBG)
        gpu.setForeground(defFG)
        gpu.fill(1, 1, w, h, " ")
        break
    end
end
