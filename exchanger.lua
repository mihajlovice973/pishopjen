--v2.4 - Оптимизированная версия с новым дизайном
local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local inspect = {}

if not fs.exists("/lib/inspect.lua") then
    shell.execute("wget -q https://raw.githubusercontent.com/kikito/inspect.lua/master/inspect.lua /lib/inspect.lua")
end
inspect = require("inspect")

local me = com.isAvailable("me_interface") and com.me_interface or error("Интерфейс не подключен")
local pim = com.isAvailable("pim") and com.pim or error("PIM не подключен")
local gpu = com.gpu

local w, h = 80, 50
local defBG, defFG = gpu.getBackground(), gpu.getForeground()
gpu.setResolution(w, h)

-- НАСТРОЙКИ
local EXPORT_DIR = "UP"          -- направление выдачи слитков (UP, DOWN, NORTH и т.д.)
local PUSH_DIR = "DOWN"          -- направление выталкивания руды
local STATS_FILE = "exchanger_stats.txt"   -- файл для статистики
local accent = 0x00E5C9          -- цвет логотипа

-- Таблица с рудами (damage не указан -> будет 0)
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
    { take = { label = "Дракониевая руда", name = "DraconicEvolution:draconiumOre", amount = 1 }, give = { label = "Дракониевая пыль", name = "DraconicEvolution:draconiumDust", amount = 2 } }
}

local currDir = shell.getWorkingDirectory()
local oresPath = currDir .. "/exchanger_ores.txt"
if fs.exists(oresPath) then
    local file = io.open(oresPath, "r")
    ore_list = file:read("*all")
    file:close()
    local success, ore_table = pcall(load("return " .. ore_list))
    if not success then
        return error("Ошибка в таблице " .. oresPath)
    end
    ore_list = ore_table
end

local function saveOres(ores)
    io.open(oresPath, "w"):write(inspect(ores)):close()
end

local function center(height, text, color)
    gpu.fill(1, height, w, 1, " ")
    gpu.setForeground(color)
    gpu.set(math.floor(w / 2 - unicode.len(text) / 2), height, text)
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

local function drawInfo(type)
    local line = 2
    if type == "full" then
        gpu.fill(1, 1, w, h - 16, " ")
    end
    for i, ore in pairs(ore_list) do
        local print_row = line + i
        if type == "full" then
            gpu.setForeground(0xFF00FF)
            local takeAmount = formatNumber(ore.take.amount)
            gpu.set(29 - #takeAmount, print_row, takeAmount)
            gpu.set(33, print_row, formatNumber(ore.give.amount))
            gpu.setForeground(0x00ff00)
            gpu.set(5, print_row, ore.take.label)
            gpu.set(42, print_row, ore.give.label)
            gpu.setForeground(0xFFFF00)
            gpu.set(30, print_row, unicode.char(0xFF1E))
            gpu.set(63, print_row, "Доступно:")
            gpu.setForeground(0x00E5C9)
            gpu.set(2, print_row + 1, string.rep("═", w - 2))
        end
        if type == "full" or type == "ingots" then
            gpu.fill(73, print_row, w - 73, 1, " ")
            gpu.setForeground(0xFF00FF)
            gpu.set(73, print_row, formatNumber(ore.size or 0))
        end
        line = line + 1
    end
end

local function updInfo(type)
    type = type or "full"
    local check = updIngotsSize()
    if not check then
        center(h - 15, "Нет соединения с МЭ или руды не настроены", 0xff0000)
    end
    drawInfo(type)
    return check
end

-- Статистика обмена
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
            center(h - 15, "Ошибка выдачи слитков! Проверьте место в инвентаре и направление.", 0xff0000)
            center(h - 14, string.format("Ожидаю выдать %d %s", toGive - totalGive, ore.give.label), 0xFFFFFF)
            os.sleep(1)
        end
    end
end

local function exchangeOre(slot, ore, index)
    local curSlot = pim.getStackInSlot(slot)
    if not curSlot then
        center(h - 14, "Вы сошли с PIM, обмен прерван.", 0xff0000)
        os.sleep(1)
        return false
    end
    local userOreSize = curSlot.qty
    local takeSize = userOreSize - (userOreSize % ore.take.amount)
    if takeSize == 0 then return true end
    local giveSize = (takeSize / ore.take.amount) * ore.give.amount

    if ore.size < giveSize then
        center(h - 14, string.format("%s недостаточно для обмена (в МЭ %d, надо %d)", ore.give.label, ore.size, giveSize), 0xff0000)
        os.sleep(2)
        return false
    end

    local takedOre = pim.pushItem(PUSH_DIR, slot, takeSize)
    if not takedOre or takedOre == 0 then
        center(h - 14, "Не удалось вытолкнуть руду. Проверьте, что снизу есть ME интерфейс.", 0xff0000)
        os.sleep(2)
        return false
    end

    local actualGive = math.floor(takedOre / ore.take.amount) * ore.give.amount
    stats.ores = stats.ores + takedOre
    center(h - 14, string.format("Меняю %d %s на %d %s", takedOre, ore.take.label, actualGive, ore.give.label), 0xffffff)
    giveIngot(actualGive, ore, index)
    gpu.fill(1, h - 14, w, 1, " ")
    return true
end

local function checkInventory()
    -- Небольшая задержка перед началом
    for i = 2, 1, -1 do
        center(h - 14, string.format("Обмен через %d сек...", i), 0x505050)
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
    -- Выводим итоговую статистику
    center(h - 15, string.format("Обмен окончен! Переработано: %d руды → %d слитков", stats.ores, stats.ingots), 0xffffff)
    saveStats()
    if pim.getInventoryName() ~= "pim" then
        return checkInventory()
    else
        event.push("player_off")
    end
end

local function isAdmin(user)
    for _, adminUser in pairs(table.pack(computer.users())) do
        if adminUser == user then return true end
    end
    return false
end

local function drawLogo(x, y, color)
    -- === НАСТРОЙКА ПОЛОЖЕНИЯ (меняйте эти числа) ===
    local dragon_x = 9      -- отступ для DRAGON (по горизонтали)
    local exchanger_x = 4   -- отступ для EXCHANGER (например, на 1 левее)
    
    local dragonLines = {
        "  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗",
        "  ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝██╔═══██╗████╗  ██║",
        "  ██║  ██║██████╔╝███████║██║  ██║█████╔╝ ██║   ██║██╔██╗ ██║",
        "  ██║  ██║██╔══██╗██╔══██║██║  ██║██╔═██╗ ██║   ██║██║╚██╗██║",
        "  ██████╔╝██║  ██║██║  ██║██████╔╝██║  ██╗╚██████╔╝██║ ╚████║",
        "  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝",
    }
    local exchangerLines = {
        "███████╗██╗  ██╗ ██████╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗ ███████╗██████╗ ",
        "██╔════╝╚██╗██╔╝██╔════╝██║  ██║██╔══██╗████╗  ██║██╔════╝ ██╔════╝██╔══██╗",
        "█████╗   ╚███╔╝ ██║     ███████║███████║██╔██╗ ██║██║  ███╗█████╗  ██████╔╝",
        "██╔══╝   ██╔██╗ ██║     ██╔══██║██╔══██║██║╚██╗██║██║   ██║██╔══╝  ██╔══██╗",
        "███████╗██╔╝ ██╗╚██████╗██║  ██║██║  ██║██║ ╚████║╚██████╔╝███████╗██║  ██║",
        "╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝",
    }
    
    gpu.setForeground(color)
    for i, line in ipairs(dragonLines) do
        gpu.set(dragon_x, y + i - 1, line)
    end
    for i, line in ipairs(exchangerLines) do
        gpu.set(exchanger_x, y + 6 + i - 1, line)
    end
end

local function handleEvent(eventName, ...)
    local args = { ... }
    if eventName == "interrupted" then
        gpu.setBackground(defBG)
        gpu.setForeground(defFG)
        gpu.fill(1, 1, w, h, " ")
        os.exit()
        return true
    elseif eventName == "player_on" then
        if not updInfo("ingots") then return end
        center(h - 15, string.format("Приветствую, %s! Начинаю обмен", args[1]), 0xffffff)
        -- Сбрасываем статистику для новой сессии
        stats.ores = 0
        stats.ingots = 0
        checkInventory()
    elseif eventName == "player_off" then
        if not updInfo("ingots") then return end
        center(h - 15, "Для обмена встаньте на PIM и не сходите до окончания обмена", 0xffffff)
        center(h - 14, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
    elseif eventName == "touch" and args[2] >= w - 38 and args[3] >= h - 1 and isAdmin(args[5]) then
        computer.beep(1500, 0.1)
        for i = 5, 1, -1 do
            center(h - 14, string.format("Начну сканировать инвентарь через %d сек...", i), 0x505050)
            os.sleep(1)
        end
        center(h - 14, "Сканирую...", 0xffffff)
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
            center(h - 14, "Обмен записан!", 0x00ff00)
            computer.beep(500, 0.2)
            updInfo()
        else
            center(h - 14, "Не увидел инвентарь!", 0xff0000)
            computer.beep(2000, 0.2)
            computer.beep(2000, 0.2)
        end
        os.sleep(1)
        for i = 5, 1, -1 do
            center(h - 14, string.format("Заработаю через %d сек...", i), 0x505050)
            os.sleep(1)
        end
        center(h - 14, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
    end
end

local function main()
    gpu.fill(1, 1, w, h, " ")
    if updInfo() then
        center(h - 15, "Для обмена встаньте на PIM и не сходите до окончания обмена", 0xffffff)
    end
    center(h - 14, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
    drawLogo(8, h - 12, accent)   -- рисуем логотип внизу (строки 5)
    while true do
        handleEvent(event.pull(1))
    end
end

while true do
    local success, err = pcall(main)
    if not success and #err > 0 then
        io.open(currDir .. "/exchanger_errors.txt", "ab"):write(err .. "\n"):close()
        computer.beep(2000, 3)
    elseif not success then
        break
    end
end