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

local wantW, wantH = 120, 40
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

-- Цветовая палитра
local COL_BG = 0x1A1A1A
local COL_PANEL = 0x222222
local COL_BORDER = 0x00CCFF
local COL_TEXT = 0xFFFFFF
local COL_DIM = 0xAAAAAA
local COL_GREEN = 0x00FF00
local COL_RED = 0xFF0000
local COL_HIGHLIGHT = 0x0088CC
local COL_YELLOW = 0xFFFF00

local EXPORT_DIR = "UP"          
local PUSH_DIR = "DOWN"          
local MAX_LIMIT = 500000

local selectedIndex = 1
local maxVisibleOres = 12

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

local stats = { ores = 0, ingots = 0 }
local isPlayerOnPim = false
local currentPlayerName = ""

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

-- Обновление количества в МЭ
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

-- Чтение инвентаря игрока (PIM)
local function updPlayerInventory()
    if not isPlayerOnPim then return end
    local data = pim.getAllStacks(0)
    
    for _, ore in ipairs(ore_list) do
        ore.userSize = 0
        ore.userGive = 0
    end
    
    for slot = 1, pim.getInventorySize() do
        if data[slot] then
            for _, ore in ipairs(ore_list) do
                local needDamage = ore.take.damage or 0
                if data[slot].id == ore.take.name and data[slot].dmg == needDamage then
                    ore.userSize = ore.userSize + data[slot].qty
                    -- Считаем, сколько получит игрок
                    local takeSize = data[slot].qty - (data[slot].qty % ore.take.amount)
                    ore.userGive = ore.userGive + math.floor(takeSize / ore.take.amount) * ore.give.amount
                end
            end
        end
    end
end

-- Рисование логотипа PI-SHOP
local function drawLogo()
    local logo = {
        " ██████╗ ██╗        ███████╗██╗  ██╗ ██████╗ ██████╗ ",
        "██╔══██╗██║        ██╔════╝██║  ██║██╔═══██╗██╔══██╗",
        "██████╔╝██║ █████╗ ███████╗███████║██║   ██║██████╔╝",
        "██╔═══╝ ██║ ╚════╝ ╚════██║██╔══██║██║   ██║██╔═══╝ ",
        "██║     ██║        ███████║██║  ██║╚██████╔╝██║     ",
        "╚═╝     ╚═╝        ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
    }
    local logoWidth = unicode.len(logo[1])
    local startX = math.floor((w - logoWidth) / 2)
    if startX < 1 then startX = 1 end
    gpu.setForeground(COL_BORDER)
    for i, line in ipairs(logo) do
        gpu.set(startX, 1 + i, line)
    end
end

local function drawHeader()
    gpu.setBackground(COL_BG)
    gpu.fill(1, 1, w, h, " ")
    
    drawLogo()
    
    gpu.setForeground(COL_GREEN)
    gpu.set(w - 10, 2, "● ONLINE")
    
    gpu.setForeground(COL_TEXT)
    gpu.set(3, 8, "RESOURCE EXCHANGER")
    gpu.setForeground(COL_DIM)
    gpu.set(3, 9, "Обмен ресурсов  •  курс  •  история")
    
    gpu.setForeground(COL_BORDER)
    gpu.set(1, 10, string.rep("═", w))
end

local function drawTable()
    gpu.setBackground(COL_PANEL)
    gpu.fill(2, 12, math.floor(w/2) - 2, h - 16, " ")
    gpu.setBackground(COL_BG)
    
    gpu.setForeground(COL_BORDER)
    gpu.set(3, 12, "🔹 ОБМЕННИК РЕСУРСОВ" .. string.rep(" ", 25) .. "РУДА -> РЕСУРСЫ")
    gpu.setForeground(COL_DIM)
    gpu.set(3, 13, "#    ВИД РУДЫ                 У ВАС    В МЭ    КУРС    ВЫДАЕТСЯ")
    gpu.setForeground(0x444444)
    gpu.set(3, 14, string.rep("─", math.floor(w/2) - 5))
    
    local startY = 15
    for i = 1, math.min(#ore_list, maxVisibleOres) do
        local ore = ore_list[i]
        local y = startY + i - 1
        
        if i == selectedIndex then
            gpu.setBackground(COL_HIGHLIGHT)
        else
            gpu.setBackground(COL_PANEL)
        end
        gpu.fill(3, y, math.floor(w/2) - 6, 1, " ")
        
        gpu.setForeground(COL_DIM)
        gpu.set(3, y, string.format("%02d", i))
        
        gpu.setForeground(COL_TEXT)
        gpu.set(9, y, string.sub(ore.take.label, 1, 23))
        
        gpu.setForeground(COL_DIM)
        gpu.set(32, y, tostring(ore.userSize or 0))
        
        gpu.setForeground(COL_BORDER)
        gpu.set(41, y, formatNumber(ore.size or 0))
        
        gpu.setForeground(COL_YELLOW)
        gpu.set(48, y, ore.take.amount .. " > " .. ore.give.amount)
        
        gpu.setForeground(COL_TEXT)
        gpu.set(56, y, string.sub(ore.give.label, 1, 15))
    end
    gpu.setBackground(COL_BG)
end

local function drawDetails()
    local panelX = math.floor(w/2) + 2
    local panelW = w - panelX - 2
    
    gpu.setBackground(COL_PANEL)
    gpu.fill(panelX, 12, panelW, h - 16, " ")
    
    gpu.setForeground(COL_BORDER)
    gpu.set(panelX + 2, 13, "ВЫБРАНА РУДА")
    
    local ore = ore_list[selectedIndex]
    if ore then
        gpu.setForeground(COL_TEXT)
        gpu.set(panelX + 2, 15, ore.take.label)
        
        gpu.setForeground(COL_DIM)
        gpu.set(panelX + 2, 17, "ИСТОРИЯ ИГРОКА: 0")
        
        gpu.setForeground(COL_DIM)
        gpu.set(panelX + 2, 20, "КУРС ОБМЕНА:")
        gpu.setForeground(COL_YELLOW)
        gpu.set(panelX + panelW - 10, 20, ore.take.amount .. " -> " .. ore.give.amount)
        
        gpu.setForeground(COL_DIM)
        gpu.set(panelX + 2, 22, "В ИНВЕНТАРЕ:")
        gpu.setForeground(COL_TEXT)
        gpu.set(panelX + panelW - 10, 22, tostring(ore.userSize or 0))
        
        gpu.setForeground(COL_DIM)
        gpu.set(panelX + 2, 24, "БУДЕТ ВЫДАНО:")
        gpu.setForeground(COL_TEXT)
        gpu.set(panelX + panelW - 10, 24, tostring(ore.userGive or 0))
        
        if (ore.size or 0) > 0 then
            gpu.setForeground(COL_GREEN)
            gpu.set(panelX + 2, 27, "● РЕСУРС ДОСТУПЕН")
        else
            gpu.setForeground(COL_RED)
            gpu.set(panelX + 2, 27, "● НЕТ В МЭ")
        end
    end
    gpu.setBackground(COL_BG)
end

local function drawBottom(statusText, statusColor)
    local y = h - 6
    gpu.setForeground(COL_DIM)
    gpu.set(3, y, string.rep("─", w - 4))
    
    gpu.setForeground(COL_BORDER)
    gpu.set(3, y + 1, "ПАКЕТНЫЙ ОБМЕН")
    gpu.setForeground(COL_DIM)
    gpu.set(3, y + 2, isPlayerOnPim and "Игрок на PIM. Идет обмен..." or "Встаньте на PIM для автоматического обмена")
    
    local statX = math.floor(w/2) + 2
    gpu.setForeground(COL_DIM)
    gpu.set(statX, y + 1, "ВИДОВ: " .. #ore_list)
    gpu.set(statX, y + 2, "ПРИНИМАЕМ: " .. stats.ores)
    gpu.set(statX, y + 3, "К ВЫДАЧЕ: " .. stats.ingots)
    
    gpu.setForeground(COL_DIM)
    gpu.set(w - 25, y + 1, "СТАТУС PIM: " .. (isPlayerOnPim and "АКТИВЕН" or "ОЖИДАНИЕ"))
    gpu.set(w - 25, y + 2, "CFG: v6")
    gpu.set(w - 25, y + 3, "МЭ: ПОДКЛЮЧЕНА")
    
    gpu.setForeground(COL_BORDER)
    gpu.set(1, h - 2, "╚" .. string.rep("═", w - 2) .. "╝")
    
    gpu.setForeground(COL_DIM)
    gpu.set(3, h - 1, "СТАТУС:")
    
    if statusText then
        gpu.setForeground(statusColor or COL_GREEN)
        gpu.set(11, h - 1, statusText)
    else
        gpu.setForeground(COL_GREEN)
        gpu.set(11, h - 1, "● PI-SHOP готов. Ожидаю игрока на PIM.")
    end
    
    gpu.setForeground(COL_DIM)
    gpu.set(3, h, "Для обмена встаньте на PIM. Руда принимается автоматически.")
end

local currentStatus = nil
local currentStatusColor = nil
local function setStatus(text, color)
    currentStatus = text
    currentStatusColor = color
end

local function redrawMain()
    drawHeader()
    drawTable()
    drawDetails()
    drawBottom(currentStatus, currentStatusColor)
end

-- Выдача слитков
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
            setStatus("Ошибка выдачи слитков! Проверьте место в инвентаре.", COL_RED)
            redrawMain()
            os.sleep(1)
        end
    end
end

-- Обмен руды
local function exchangeOre(slot, ore, index)
    local curSlot = pim.getStackInSlot(slot)
    if not curSlot then
        setStatus("Вы сошли с PIM, обмен прерван.", COL_RED)
        redrawMain()
        os.sleep(1)
        return false
    end
    
    local userOreSize = curSlot.qty
    local takeSize = userOreSize - (userOreSize % ore.take.amount)
    if takeSize == 0 then return true end
    
    local giveSize = (takeSize / ore.take.amount) * ore.give.amount
    if ore.size < giveSize then
        setStatus(string.format("%s недостаточно (в МЭ %d, надо %d)", ore.give.label, ore.size, giveSize), COL_RED)
        redrawMain()
        os.sleep(2)
        return false
    end
    
    local takedOre = pim.pushItem(PUSH_DIR, slot, takeSize)
    if not takedOre or takedOre == 0 then
        setStatus("Не удалось вытолкнуть руду. Проверьте интерфейс снизу.", COL_RED)
        redrawMain()
        os.sleep(2)
        return false
    end
    
    local actualGive = math.floor(takedOre / ore.take.amount) * ore.give.amount
    stats.ores = stats.ores + takedOre
    
    setStatus(string.format("Меняю %d %s на %d %s", takedOre, ore.take.label, actualGive, ore.give.label), COL_TEXT)
    redrawMain()
    
    giveIngot(actualGive, ore, index)
    return true
end

-- Главный цикл обмена
local function checkInventory()
    setStatus("Обмен через 2 сек...", COL_DIM)
    redrawMain()
    os.sleep(2)
    
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
    
    updPlayerInventory()
    setStatus(string.format("Обмен окончен! Переработано: %d руды -> %d слитков", stats.ores, stats.ingots), COL_GREEN)
    redrawMain()
    
    if pim.getInventoryName() ~= "pim" then
        isPlayerOnPim = false
    else
        event.push("player_off") -- Принудительно отключаем, если игрок всё еще стоит
    end
end

local function handleEvent(eventName, ...)
    local args = { ... }
    
    if eventName == "key_down" then
        local code = args[3]
        if code == 200 or code == 44 then
            selectedIndex = selectedIndex - 1
            if selectedIndex < 1 then selectedIndex = #ore_list end
            redrawMain()
        elseif code == 208 or code == 45 then
            selectedIndex = selectedIndex + 1
            if selectedIndex > #ore_list then selectedIndex = 1 end
            redrawMain()
        end
        
    elseif eventName == "player_on" then
        local playerName = args[1] or "Игрок"
        isPlayerOnPim = true
        stats.ores = 0
        stats.ingots = 0
        
        setStatus("Приветствую, " .. playerName .. "! Сканирую инвентарь...", COL_TEXT)
        updIngotsSize()
        updPlayerInventory()
        redrawMain()
        
        checkInventory()
        
    elseif eventName == "player_off" then
        isPlayerOnPim = false
        updIngotsSize()
        
        for _, ore in ipairs(ore_list) do
            ore.userSize = 0
            ore.userGive = 0
        end
        
        setStatus("Ожидаю игрока на PIM...", COL_GREEN)
        redrawMain()
    end
end

local function main()
    updIngotsSize()
    redrawMain()
    
    while true do
        local success, eventName, p1, p2, p3, p4, p5 = pcall(event.pull, 1)
        if success and eventName then
            handleEvent(eventName, p1, p2, p3, p4, p5)
        end
    end
end

while true do
    local success, err = pcall(main)
    if not success then
        if err == "interrupted" then
            gpu.setBackground(defBG)
            gpu.setForeground(defFG)
            gpu.fill(1, 1, w, h, " ")
            break
        else
            local f = io.open(shell.getWorkingDirectory() .. "/exchanger_errors.txt", "ab")
            if f then f:write(os.date("[%H:%M:%S] ") .. tostring(err) .. "\n"):close() end
            computer.beep(2000, 1)
            os.sleep(1)
        end
    end
end
