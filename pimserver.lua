local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local gpu = component.gpu
local math = require("math")
local os = require("os")
local unicode = require("unicode")
local computer = require("computer")
local TIMEZONE_OFFSET = 3 * 3600   -- +3 часа для Москвы (UTC+3)

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)

-- ========== РЕАЛЬНОЕ ВРЕМЯ ЧЕРЕЗ TMPFS ==========
local tmpfs = component.proxy(computer.tmpAddress())
local function getRealTimestamp()
    local handle = tmpfs.open("/time", "w")
    tmpfs.write(handle, "time")
    tmpfs.close(handle)
    return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
end

local function getRealTimeString()
    return os.date("%H:%M:%S", getRealTimestamp())
end

local function getRealDateTimeString()
    return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end

-- ========== ANSI ЦВЕТА ==========
local ansi = {
    reset   = "\27[0m",
    bold    = "\27[1m",
    red     = "\27[31m",
    green   = "\27[32m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    magenta = "\27[35m",
    cyan    = "\27[36m",
    white   = "\27[37m",
    bg_black   = "\27[40m",
    bg_blue    = "\27[44m",
    clear   = "\27[2J\27[H",
    hide_cursor = "\27[?25l",
    show_cursor = "\27[?25h"
}

local function setColor(fg, bg)
    io.write(fg or "")
    if bg then io.write(bg) end
end

local function resetColor()
    io.write(ansi.reset)
end

local function gotoxy(x, y)
    io.write("\27[", y, ";", x, "H")
end

local function fill(x, y, w, h, char)
    for i = 0, h-1 do
        gotoxy(x, y+i)
        io.write(string.rep(char, w))
    end
end

local function timeToMidnight()
    local now = getRealTimestamp()
    local dt = os.date("*t", now)
    local secondsLeft = (24 - dt.hour - 1) * 3600 + (60 - dt.min - 1) * 60 + (60 - dt.sec)
    if secondsLeft < 0 then secondsLeft = 0 end
    local h = math.floor(secondsLeft / 3600)
    local m = math.floor((secondsLeft % 3600) / 60)
    local s = secondsLeft % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local ACCESS_PASSWORD = "secret"

-- ========== БАЗА ДАННЫХ ИГРОКОВ ==========
local DB_PATH = "/home/players.db"
local players = {}
if filesystem.exists(DB_PATH) then
    local file = io.open(DB_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then players = data end
    end
end

local function saveDB()
    local file = io.open(DB_PATH, "w")
    file:write(serialization.serialize(players))
    file:close()
end

-- ========== ГЛОБАЛЬНАЯ СТАТИСТИКА ==========
local STATS_PATH = "/home/global_stats.db"
local globalStats = { totalReports = 0, totalBuys = 0, totalSells = 0 }
if filesystem.exists(STATS_PATH) then
    local file = io.open(STATS_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then
            globalStats.totalReports = data.totalReports or 0
            globalStats.totalBuys = data.totalBuys or 0
            globalStats.totalSells = data.totalSells or 0
        end
    end
end

local function saveGlobalStats()
    local file = io.open(STATS_PATH, "w")
    file:write(serialization.serialize(globalStats))
    file:close()
end

-- ========== ПЕРЕМЕННЫЕ СЕРВЕРА ==========
local owner = nil
local sessions = {}
local markets = {}
local modemLastSeen = {}
local SESSION_TIMEOUT = 31536000
local marketConnected = false
local logBuffer = {}
local shopPaused = false
local adminMode = false
local adminPlayerList = {}
local adminScroll = 0
local selectedAdminIndex = 1
local adminViewHeight = 20
local editBalanceMode = false
local editingPlayer = nil
local editInput = ""

-- ========== РЕЖИМ ДОБАВЛЕНИЯ ПРЕДМЕТА ==========
local addItemMode = false
local addItemFields = { internal = "", display = "", price = "", damage = "0" }
local addItemCurrentField = 1
local addItemFieldNames = { "internal", "display", "price", "damage" }
local addItemResponse = nil
local addItemResponseTimer = nil

-- ========== ИСТОРИЯ ПРОДАЖ И АКТИВНОСТЬ ==========
local sellHistory = {}
local MAX_SELL_HISTORY = 20
local ACTIVITY_SIZE = 60
local activityBuffer = {}
for i=1, ACTIVITY_SIZE do activityBuffer[i] = 0 end
local activityIndex = 0
local screenW, screenH = 80, 25
local colX = {5, 30, 55, 80}
local colWidth = 25
local logStartY = 20
local maxLogLines = 14
-- ========== АДМИНИСТРАТОРЫ ==========

local ADMINS = {
    "KaRMa__",
    'ZoziDo',
}

local function normalizePlayerName(name)
    if type(name) ~= "string" then return "" end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name:lower()
end

local function isAdmin(playerName)
    local checkName = normalizePlayerName(playerName)
    if checkName == "" then return false end

    for i = 1, #ADMINS do
        if normalizePlayerName(ADMINS[i]) == checkName then
            return true
        end
    end

    return false
end

local function getAdminsText()
    return table.concat(ADMINS, ", ")
end

local drawing = false

local function updateScreenSize()
    local w, h = gpu.getResolution()
    if w > 200 then w = 200 end
    if w < 80 then w = 80 end
    if h < 15 then h = 15 end
    screenW, screenH = w, h
    local usable = screenW - 8
    colWidth = math.max(12, math.floor(usable / 4))
    colX = {4, 4 + colWidth, 4 + colWidth * 2, 4 + colWidth * 3}
    logStartY = math.min(18, screenH - 5)
    maxLogLines = screenH - logStartY - 3
    if maxLogLines < 3 then maxLogLines = 3 end
    adminViewHeight = screenH - 8
    if adminViewHeight < 3 then adminViewHeight = 3 end
end

local function addActivity()
    activityIndex = activityIndex % ACTIVITY_SIZE + 1
    activityBuffer[activityIndex] = 0
end
event.timer(60, addActivity, math.huge)

local function recordTransaction()
    if activityBuffer[activityIndex] then
        activityBuffer[activityIndex] = activityBuffer[activityIndex] + 1
    end
end

function addLog(text, fg)
    table.insert(logBuffer, {text = text, color = fg or ansi.white})
    while #logBuffer > 200 do table.remove(logBuffer, 1) end
end

local function log(level, msg)
    local color = ansi.white
    if level == "INFO" then color = ansi.green
    elseif level == "WARN" then color = ansi.yellow
    elseif level == "ERROR" then color = ansi.red end
    addLog("[" .. getRealTimeString() .. "] [" .. level .. "] " .. msg, color)
end

local function updateAdminPlayerList()
    adminPlayerList = {}
    for name, data in pairs(players) do
        table.insert(adminPlayerList, {name=name, data=data})
    end
    table.sort(adminPlayerList, function(a,b) return a.name < b.name end)
end

-- ========== ОТРИСОВКА АДМИН-ПАНЕЛИ ==========
local function drawAdminPanel()
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    setColor(ansi.white)
    fill(1, 1, screenW, 1, "─")
    fill(1, screenH, screenW, 1, "─")
    for y=2, screenH-1 do
        gotoxy(1, y) io.write("│")
        gotoxy(screenW, y) io.write("│")
    end
    gotoxy(1,1) io.write("┌"..string.rep("─", screenW-2).."┐")
    gotoxy(1,screenH) io.write("└"..string.rep("─", screenW-2).."┘")
    resetColor()

    setColor(ansi.bg_blue, ansi.white)
    fill(2, 1, screenW-2, 1, " ")
    gotoxy(2,1) io.write(" АДМИН-ПАНЕЛЬ (нажмите A для выхода) ")
    resetColor()

    local startIdx = adminScroll + 1
    local endIdx = math.min(#adminPlayerList, adminScroll + adminViewHeight)
    setColor(ansi.yellow)
    gotoxy(2, 3) io.write("Игроки (↑↓ выбор, клик мышкой, D - бан/разбан, R - сброс статистики, P - пауза, E - редактировать баланс, B - добавить предмет)")
    resetColor()

    for i=startIdx, endIdx do
        local ply = adminPlayerList[i]
        local bannedStr = ply.data.banned and " [ЗАБАНЕН]" or ""
        local line = string.format("%-20s | Баланс: %8.2f ₵ | Транз: %d%s",
            ply.name, ply.data.balance or 0, ply.data.transactions or 0, bannedStr)
        if #line > screenW - 4 then line = line:sub(1, screenW-4) end
        local y = 4 + (i - startIdx)
        setColor((i == selectedAdminIndex) and ansi.bg_blue or ansi.white, (i == selectedAdminIndex) and ansi.white or nil)
        gotoxy(2, y)
        io.write(line)
        resetColor()
    end

    setColor(ansi.cyan)
    gotoxy(2, screenH-2)
    io.write("BAN/UNBAN: D | RESET STATS: R | PAUSE: P | EDIT BALANCE: E | ADD ITEM: B | SCROLL: ↑↓ | MOUSE CLICK")
    resetColor()
    io.flush()
    drawing = false
end

-- ========== ФОРМА РЕДАКТИРОВАНИЯ БАЛАНСА ==========
local function drawEditBalanceWindow()
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    local w = 50
    local h = 8
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    setColor(ansi.white)
    fill(x, y, w, h, " ")
    setColor(ansi.bg_black, ansi.white)
    for i = 0, h-1 do
        gotoxy(x, y+i) io.write("│")
        gotoxy(x+w-1, y+i) io.write("│")
    end
    fill(x+1, y, w-2, 1, "─")
    fill(x+1, y+h-1, w-2, 1, "─")
    setColor(ansi.bg_blue, ansi.white)
    fill(x+2, y, w-4, 1, " ")
    gotoxy(x+2, y) io.write(" РЕДАКТИРОВАНИЕ БАЛАНСА ")
    resetColor()

    setColor(ansi.yellow)
    gotoxy(x+2, y+2) io.write("Игрок: " .. editingPlayer.name)
    gotoxy(x+2, y+3) io.write("Текущий баланс: " .. string.format("%.2f", editingPlayer.data.balance) .. " ₵")
    resetColor()

    setColor(ansi.cyan)
    gotoxy(x+2, y+5) io.write("Введите новую сумму: " .. editInput .. "_")
    resetColor()

    setColor(ansi.white)
    gotoxy(x+2, y+6) io.write("Enter - подтвердить | Esc - отмена")
    resetColor()
    io.flush()
    drawing = false
end

-- ========== ФОРМА ДОБАВЛЕНИЯ ПРЕДМЕТА ==========
local function drawAddItemForm()
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    local w = 70
    local h = 12
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    setColor(ansi.white)
    fill(x, y, w, h, " ")
    setColor(ansi.bg_black, ansi.white)
    for i = 0, h-1 do
        gotoxy(x, y+i) io.write("│")
        gotoxy(x+w-1, y+i) io.write("│")
    end
    fill(x+1, y, w-2, 1, "─")
    fill(x+1, y+h-1, w-2, 1, "─")
    setColor(ansi.bg_blue, ansi.white)
    fill(x+2, y, w-4, 1, " ")
    gotoxy(x+2, y) io.write(" ДОБАВЛЕНИЕ ПРЕДМЕТА В МАГАЗИН (покупка) ")
    resetColor()

    local labels = { "Internal Name:", "Display Name:", "Price (число):", "Damage (0 = без damage):" }
    for i = 1, 4 do
        setColor(ansi.yellow)
        gotoxy(x+3, y+2 + (i-1)*2)
        io.write(labels[i])
        setColor(ansi.cyan)
        gotoxy(x+35, y+2 + (i-1)*2)
        local val = addItemFields[addItemFieldNames[i]]
        local cursor = (addItemCurrentField == i) and "█" or " "
        io.write(val .. cursor)
        resetColor()
    end

    setColor(ansi.white)
    gotoxy(x+3, y+10)
    io.write("Enter - далее / отправить | ] - отмена")
    io.flush()
    drawing = false
end

-- ========== ОСНОВНОЙ ИНТЕРФЕЙС СЕРВЕРА ==========
function drawInterface()
    if adminMode or editBalanceMode or addItemMode then return end
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    setColor(ansi.bg_blue, ansi.white)
    fill(1, 2, screenW, 1, " ")
    gotoxy(1, 2)
    local title = " PIM MARKET SERVER – СТАТУС: " .. (marketConnected and "АКТИВЕН" or "ОЖИДАНИЕ MARKET")
    if shopPaused then title = title .. " [ПАУЗА]" end
    io.write(title .. string.rep(" ", screenW - #title))
    resetColor()

    setColor(ansi.cyan)
    gotoxy(1, 3)
    io.write("Время: " .. getRealTimeString() .. "  До сброса репортов: " .. timeToMidnight())
    local activeCount = 0
    for _, v in pairs(sessions) do
        if type(v) == "table" and v.token then activeCount = activeCount + 1 end
    end
    gotoxy(screenW - 25, 3)
    io.write("Активных сессий: " .. activeCount)
    resetColor()

    setColor(ansi.white)
    fill(1, 4, screenW, 1, "─")
    resetColor()

    local titles = {"👥 ИГРОКИ", "📦 ПРОДАЖИ", "🔒 БЕЗОПАСНОСТЬ", "📊 СТАТИСТИКА"}
    setColor(ansi.bold, ansi.yellow)
    for i=1,4 do
        gotoxy(colX[i], 5)
        io.write(titles[i] .. string.rep(" ", colWidth - #titles[i]))
    end
    resetColor()

    setColor(ansi.green)
    local playerList = {}
    for name, s in pairs(sessions) do
        if type(s) == "table" and s.token then table.insert(playerList, name) end
    end
    local rowsAvailable = logStartY - 7
    for i=1, math.min(rowsAvailable, #playerList) do
        gotoxy(colX[1], 5+i)
        local name = playerList[i]
        if #name > colWidth then name = name:sub(1, colWidth) end
        io.write(name .. string.rep(" ", colWidth - #name))
    end
    resetColor()

    setColor(ansi.cyan)
    gotoxy(colX[2], 6)
    io.write("Последние продажи:")
    for i = 1, math.min(rowsAvailable, #sellHistory) do
        local entry = sellHistory[#sellHistory - i + 1]
        if entry then
            gotoxy(colX[2], 6 + i)
            local line = entry.name .. ": " .. entry.item .. " x" .. entry.qty
            if unicode.len(line) > colWidth then
                line = unicode.sub(line, 1, colWidth)
            end
            io.write(line)
        end
    end
    resetColor()

    setColor(ansi.magenta)
    gotoxy(colX[3], 6)
    io.write("Лимит сессии: " .. SESSION_TIMEOUT .. " сек")
    local playersCount = 0
    for _ in pairs(players) do playersCount = playersCount + 1 end
    gotoxy(colX[3], 7)
    io.write("Игроков в БД: " .. playersCount)
    gotoxy(colX[3], 9)
    io.write("Активность (последние 60 мин):")
    local graphWidth = colWidth - 2
    local maxVal = 1
    for i=1, ACTIVITY_SIZE do
        if activityBuffer[i] > maxVal then maxVal = activityBuffer[i] end
    end
    for i=1, math.min(ACTIVITY_SIZE, graphWidth) do
        local val = activityBuffer[(activityIndex - i + ACTIVITY_SIZE) % ACTIVITY_SIZE + 1] or 0
        local height = math.ceil((val / (maxVal+0.01)) * 3)
        gotoxy(colX[3]+i-1, 13 - height)
        setColor(ansi.green)
        io.write("█")
        resetColor()
    end
    resetColor()

    setColor(ansi.yellow)
    gotoxy(colX[4], 6)
    io.write("Репортов: " .. globalStats.totalReports)
    gotoxy(colX[4], 7)
    io.write("Покупок: " .. globalStats.totalBuys)
    gotoxy(colX[4], 8)
    io.write("Продаж: " .. globalStats.totalSells)
    resetColor()

    setColor(ansi.white)
    gotoxy(1, screenH-1)
    io.write("R - обновить | P - Пауза | A - Админ-панель (админы: " .. getAdminsText() .. ")")
    resetColor()

    setColor(ansi.white)
    fill(1, logStartY-1, screenW, 1, "─")
    resetColor()
    for i=1, maxLogLines do
        local entry = logBuffer[#logBuffer - maxLogLines + i]
        if entry then
            setColor(entry.color)
            gotoxy(1, logStartY + i - 1)
            local line = entry.text
            if #line > screenW - 1 then line = line:sub(1, screenW-1) end
            io.write(line .. string.rep(" ", screenW - #line))
            resetColor()
        end
    end
    io.flush()
    drawing = false
end

-- ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========
local function getOrCreatePlayer(name)
    if not players[name] then
        players[name] = {
            balance = 0.0,
            emaBalance = 0.0,
            transactions = 0,
            regDate = getRealDateTimeString(),
            agreed = false,
            banned = false,
            hasFeedback = false
        }
        saveDB()
        log("INFO", "Создан игрок " .. name)
    end
    return players[name]
end

local function validateSession(name, token)
    local s = sessions[name]
    return s and s.token == token and os.time() - (s.lastAction or 0) < SESSION_TIMEOUT
end

-- ========== ОБРАБОТЧИК КЛАВИШ ==========
local function handleKey(key, char, player)
    local hasAdminAccess = isAdmin(player)

    -- Админ-формами и админ-панелью может управлять только игрок из ADMINS.
    if (adminMode or editBalanceMode or addItemMode) and not hasAdminAccess then
        log("WARN", "Попытка управления админ-панелью не админом: " .. tostring(player))
        return
    end

    if addItemMode then
        if char == 93 then
            addItemMode = false
            addItemResponse = nil
            if adminMode then drawAdminPanel() else drawInterface() end
            return
        elseif char == 13 then
            if addItemCurrentField < 4 then
                addItemCurrentField = addItemCurrentField + 1
                drawAddItemForm()
                return
            else
                local price = tonumber(addItemFields.price)
                if not price then
                    addLog("Ошибка: цена должна быть числом", ansi.red)
                    addItemMode = false
                    drawAdminPanel()
                    return
                end
                local damage = tonumber(addItemFields.damage) or 0
                if damage < 0 then damage = 0 end
                if addItemFields.internal == "" or addItemFields.display == "" then
                    addLog("Ошибка: internalName и displayName не могут быть пустыми", ansi.red)
                    addItemMode = false
                    drawAdminPanel()
                    return
                end

                local data = {
                    op = "add_buy_item",
                    internalName = addItemFields.internal,
                    displayName = addItemFields.display,
                    price = price,
                    damage = damage
                }

                if next(markets) == nil then
                    addLog("Нет подключённых терминалов market_01", ansi.red)
                else
                    local sent = 0
                    for addr, _ in pairs(markets) do
                        modem.send(addr, 0xffef, serialization.serialize(data))
                        sent = sent + 1
                    end
                    addLog("Отправка предмета на " .. sent .. " терминал(ов)...", ansi.yellow)

                    addItemResponse = nil
                    addItemResponseTimer = os.time()
                    while os.time() - addItemResponseTimer < 5 do
                        event.pull(0.2)
                        if addItemResponse then break end
                    end
                    if addItemResponse and addItemResponse.success then
                        addLog("Предмет успешно добавлен!", ansi.green)
                        for addr, _ in pairs(markets) do
                            modem.send(addr, 0xffef, serialization.serialize({op = "reload_buy_items"}))
                        end
                        addLog("Отправлена команда перезагрузки на все терминалы", ansi.green)
                    else
                        addLog("Внимание: не получен ответ от терминалов, но предмет мог быть добавлен.", ansi.yellow)
                    end
                end
                addItemMode = false
                addItemResponse = nil
                if adminMode then drawAdminPanel() else drawInterface() end
                return
            end
        elseif char == 8 then
            local field = addItemFieldNames[addItemCurrentField]
            addItemFields[field] = addItemFields[field]:sub(1, -2)
            drawAddItemForm()
            return
        elseif char >= 32 then
            local c = unicode.char(char)
            local field = addItemFieldNames[addItemCurrentField]
            if field == "price" or field == "damage" then
                if c:match("%d") or (c == "." and field == "price" and not addItemFields.price:find("%.")) then
                    addItemFields[field] = addItemFields[field] .. c
                end
            else
                addItemFields[field] = addItemFields[field] .. c
            end
            drawAddItemForm()
            return
        end
        return
    end

    if editBalanceMode then
        if char == 27 then
            editBalanceMode = false
            editingPlayer = nil
            editInput = ""
            drawAdminPanel()
            return
        elseif char == 13 then
            if editInput ~= "" then
                local amount = tonumber(editInput)
                if amount then
                    editingPlayer.data.balance = amount
                    log("INFO", "Баланс игрока " .. editingPlayer.name .. " изменён на " .. amount .. " ₵")
                    saveDB()
                else
                    log("WARN", "Некорректная сумма: " .. editInput)
                end
            end
            editBalanceMode = false
            editingPlayer = nil
            editInput = ""
            drawAdminPanel()
            return
        else
            if char >= 48 and char <= 57 then
                editInput = editInput .. string.char(char)
            elseif char == 46 then
                if not editInput:find("%.") then
                    editInput = editInput .. "."
                end
            elseif char == 8 then
                editInput = editInput:sub(1, -2)
            end
            drawEditBalanceWindow()
            return
        end
    end

    if adminMode then
        if key == 200 then
            if selectedAdminIndex > 1 then
                selectedAdminIndex = selectedAdminIndex - 1
                if selectedAdminIndex < adminScroll + 1 then
                    adminScroll = math.max(0, selectedAdminIndex - 1)
                end
                drawAdminPanel()
            end
            return
        elseif key == 208 then
            if selectedAdminIndex < #adminPlayerList then
                selectedAdminIndex = selectedAdminIndex + 1
                if selectedAdminIndex > adminScroll + adminViewHeight then
                    adminScroll = selectedAdminIndex - adminViewHeight
                end
                drawAdminPanel()
            end
            return
        end
    end

    local pressed = nil
    if char and char >= 1 and char <= 255 then
        pressed = string.lower(string.char(char))
    end

    if not adminMode then
        if pressed == "a" then
            if hasAdminAccess then
                adminMode = true
                adminScroll = 0
                selectedAdminIndex = 1
                updateAdminPlayerList()
                drawAdminPanel()
            else
                log("WARN", "Попытка входа в админ-панель не админом: " .. tostring(player))
            end
            return
        elseif pressed == "p" then
            if hasAdminAccess then
                shopPaused = not shopPaused
                log("INFO", "Магазин " .. (shopPaused and "приостановлен" or "возобновлён"))
                drawInterface()
            else
                log("WARN", "Попытка паузы магазина не админом: " .. tostring(player))
            end
            return
        elseif pressed == "r" then
            drawInterface()
            return
        end
    else
        if pressed == "p" then
            shopPaused = not shopPaused
            log("INFO", "Магазин " .. (shopPaused and "приостановлен" or "возобновлён"))
            drawAdminPanel()
            return
        elseif pressed == "a" then
            adminMode = false
            drawInterface()
            return
        elseif pressed == "d" then
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                ply.data.banned = not ply.data.banned
                saveDB()
                log("INFO", "Игрок " .. ply.name .. (ply.data.banned and " забанен" or " разбанен"))
                drawAdminPanel()
            end
            return
        elseif pressed == "r" then
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                ply.data.transactions = 0
                ply.data.balance = 0
                saveDB()
                log("INFO", "Статистика игрока " .. ply.name .. " сброшена")
                drawAdminPanel()
            end
            return
        elseif pressed == "e" then
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                editingPlayer = ply
                editInput = ""
                editBalanceMode = true
                drawEditBalanceWindow()
            end
            return
        elseif pressed == "b" then
            if hasAdminAccess then
                addItemMode = true
                addItemFields = { internal = "", display = "", price = "", damage = "0" }
                addItemCurrentField = 1
                drawAddItemForm()
            else
                log("WARN", "Попытка добавления предмета не админом: " .. tostring(player))
            end
            return
        end
    end
end

local function handleTouch(x, y, player)
    if not adminMode or editBalanceMode or addItemMode then return end
    if not isAdmin(player) then
        log("WARN", "Попытка управления админ-панелью мышью не админом: " .. tostring(player))
        return
    end
    if y >= 4 and y <= 3 + adminViewHeight then
        local lineIndex = y - 4
        local realIndex = adminScroll + lineIndex + 1
        if realIndex >= 1 and realIndex <= #adminPlayerList then
            selectedAdminIndex = realIndex
            drawAdminPanel()
        end
    end
end

-- ========== ОСНОВНОЙ ЦИКЛ ==========
local function main()
    log("INFO", "Сервер запущен. Ожидание терминалов...")
    drawInterface()

    while true do
        local ev = {event.pull(0.5)}
        local etype = ev[1]

        if etype == "key_down" then
            local key = ev[4]
            local char = ev[3]
            local player = ev[5]
            handleKey(key, char, player)
        elseif etype == "touch" then
            local x = ev[3]
            local y = ev[4]
            local player = ev[6]
            handleTouch(x, y, player)
        elseif etype == "modem_message" then
            local from = ev[3]
            local raw = ev[6]
            local success, msg = pcall(serialization.unserialize, raw)
            if not success or not msg or type(msg) ~= "table" then
                goto continue
            end

            -- Авторизация register/enter никогда не блокируется антиспамом.
            -- Для остальных запросов используем computer.uptime() с нормальной
            -- дробной точностью, а не os.time().
            if msg.op ~= "register" and msg.op ~= "enter" then
                local now = computer.uptime()
                local last = modemLastSeen[from] or 0
                if now - last < 0.05 then
                    goto continue
                end
                modemLastSeen[from] = now
            end

            log("INFO", string.format("От %s | op=%s | name=%s | token=%s", from, tostring(msg.op), msg.name or "?", msg.token or "нет"))

            if msg.op == "register" then
                if msg.password ~= ACCESS_PASSWORD then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Неверный пароль"}))
                    log("WARN", "Попытка подключения с неверным паролем от " .. from)
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                marketConnected = true
                if not owner then
                    owner = from
                    log("INFO", "✅ АДМИН ЗАРЕГИСТРИРОВАН: " .. from)
                end
                if not markets[from] then
                    markets[from] = true
                    log("INFO", "✅ Терминал добавлен в список рассылки: " .. from)
                end
                modem.send(from, 0xffef, serialization.serialize({op="welcome", owner=(from==owner), shopPaused=shopPaused}))
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "enter" then
                if shopPaused then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local playerName = msg.name
                if not playerName or playerName == "" then
                    log("WARN", "Вход без имени от " .. from)
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = getOrCreatePlayer(playerName)
                if player.banned then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Вы забанены"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end

                local existingSession = sessions[playerName]
                local token
                if existingSession and os.time() - (existingSession.lastAction or 0) < SESSION_TIMEOUT then
                    token = existingSession.token
                    existingSession.lastAction = os.time()
                    log("INFO", "👤 " .. playerName .. " продлил сессию. Токен: " .. token)
                else
                    token = tostring(math.floor(math.random() * 900000000 + 100000000))
                    sessions[playerName] = {token = token, lastAction = os.time()}
                    log("INFO", "👤 " .. playerName .. " вошёл. Токен: " .. token)
                end

                modem.send(from, 0xffef, serialization.serialize({
                    op="welcome", status="ok", token=token,
                    balance=player.balance or 0.0,
                    emaBalance=player.emaBalance or 0.0,
                    transactions=player.transactions,
                    regDate=player.regDate,
                    agreed = player.agreed or false,
                    shopPaused = shopPaused
                }))
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "getAccount" then
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "Неверный токен для getAccount от " .. (msg.name or "?"))
                    modem.send(from, 0xffef, serialization.serialize({op="accountData", error = true, message = "Токен устарел"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = players[msg.name]
                if not player then goto continue end
                sessions[msg.name].lastAction = os.time()
                modem.send(from, 0xffef, serialization.serialize({
                    op="accountData",
                    data = {
                        balance = player.balance or 0.0,
                        emaBalance = player.emaBalance or 0.0,
                        transactions = player.transactions,
                        regDate = player.regDate,
                        agreed = player.agreed,
                        shopPaused = shopPaused
                    }
                }))
                log("INFO", "Аккаунт отправлен для " .. msg.name)
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "sell" then
                if shopPaused then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "Неверный токен для sell")
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = players[msg.name]
                if not player or player.banned then goto continue end
                local qty = tonumber(msg.qty) or 0
                local value = tonumber(msg.value) or 0

                if msg.internalName == "customnpcs:npcMoney" then
                    player.emaBalance = (player.emaBalance or 0) + value
                else
                    player.balance = (player.balance or 0) + value
                end

                player.transactions = (player.transactions or 0) + 1
                sessions[msg.name].lastAction = os.time()

                globalStats.totalSells = (globalStats.totalSells or 0) + 1
                saveGlobalStats()
                saveDB()
                recordTransaction()

                local currency = (msg.internalName == "customnpcs:npcMoney") and "ЭМЫ" or "COIN"
                log("INFO", string.format("💰 %s пополнил %s: предмет '%s' x%d на сумму %.2f", msg.name, currency, msg.item, qty, value))
                table.insert(sellHistory, {item = msg.item, qty = qty, name = msg.name})
                while #sellHistory > MAX_SELL_HISTORY do table.remove(sellHistory, 1) end
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "buy" then
                if shopPaused then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "Неверный токен для buy")
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = players[msg.name]
                if not player or player.banned then goto continue end

                -- Новый терминал отправляет отдельно COIN и ЭМЫ.
                -- Для совместимости со старым терминалом поддерживается msg.value.
                local valueCoin = tonumber(msg.value_coin)
                if valueCoin == nil then valueCoin = tonumber(msg.value) or 0 end
                local valueEma = tonumber(msg.value_ema) or 0

                player.balance = math.max(0, (player.balance or 0) - valueCoin)
                player.emaBalance = math.max(0, (player.emaBalance or 0) - valueEma)
                player.transactions = (player.transactions or 0) + 1
                sessions[msg.name].lastAction = os.time()

                globalStats.totalBuys = (globalStats.totalBuys or 0) + 1
                saveGlobalStats()
                saveDB()
                recordTransaction()
                log("INFO", string.format("🛒 %s купил %s x%d за %.2f COIN + %.2f ЭМЫ", msg.name, msg.item, msg.qty, valueCoin, valueEma))
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "report" then
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "Неверный токен для report")
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                globalStats.totalReports = (globalStats.totalReports or 0) + 1
                saveGlobalStats()
                log("INFO", "📩 Репорт от " .. msg.name .. " (" .. msg.time .. ")")
                log("INFO", "   Текст: " .. (msg.text or ""))
                local file = io.open("/home/reports.log", "a")
                if file then
                    file:write("[" .. msg.time .. "] " .. msg.name .. ": " .. msg.text .. "\n")
                    file:close()
                    log("INFO", "✅ Сохранено в reports.log")
                else
                    log("ERROR", "❌ Не удалось открыть reports.log")
                end
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "agree" then
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "Неверный токен для agree")
                    modem.send(from, 0xffef, serialization.serialize({ op="agree", error = true, message = "Токен устарел" }))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = players[msg.name]
                if player then
                    player.agreed = true
                    saveDB()
                    sessions[msg.name].lastAction = os.time()
                    log("INFO", "📝 " .. msg.name .. " принял пользовательское соглашение")
                    modem.send(from, 0xffef, serialization.serialize({ op = "agree", success = true, agreed = true }))
                else
                    modem.send(from, 0xffef, serialization.serialize({ op = "agree", error = true, message = "Игрок не найден" }))
                end
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "add_buy_item_response" then
                addItemResponse = { success = msg.success, error = msg.error }
                goto continue
            elseif msg.op == "get_feedbacks" then
            if not validateSession(msg.name, msg.token) then
                modem.send(from, 0xffef, serialization.serialize({op="feedbacks_list", error="Токен устарел"}))
                goto continue
            end
            local player = players[msg.name]
            local feedbacks = {}
            if filesystem.exists("/home/feedbacks.db") then
                local file = io.open("/home/feedbacks.db", "r")
                local data = file:read("*a")
                file:close()
                if data and #data > 0 then
                    local ok, result = pcall(serialization.unserialize, data)
                    if ok and type(result) == "table" then
                        feedbacks = result
                    end
                end
            end
            modem.send(from, 0xffef, serialization.serialize({
                op = "feedbacks_list",
                feedbacks = feedbacks,
                hasFeedback = player and player.hasFeedback or false
            }))
            goto continue
            elseif msg.op == "add_feedback" then
            if not validateSession(msg.name, msg.token) then
                modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=false, error="Токен устарел"}))
                goto continue
            end
            local player = players[msg.name]
            if not player then
                modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=false, error="Игрок не найден"}))
                goto continue
            end
            if player.hasFeedback then
                modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=false, error="Вы уже оставляли отзыв"}))
                goto continue
            end
            -- Безопасное чтение существующих отзывов
            local feedbacks = {}
            if filesystem.exists("/home/feedbacks.db") then
                local file = io.open("/home/feedbacks.db", "r")
                local data = file:read("*a")
                file:close()
                if data and #data > 0 then
                    local ok, result = pcall(serialization.unserialize, data)
                    if ok and type(result) == "table" then
                        feedbacks = result
                    end
                end
            end
            -- Добавляем новый отзыв в начало
            table.insert(feedbacks, 1, {name = msg.name, text = msg.text, time = msg.time})
            local file = io.open("/home/feedbacks.db", "w")
            file:write(serialization.serialize(feedbacks))
            file:close()
            player.hasFeedback = true
            saveDB()
            modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=true}))
            log("INFO", "📝 Новый отзыв от " .. msg.name .. ": " .. msg.text)
            goto continue
            end
        end
        ::continue::
    end
end

-- ========== БЕСКОНЕЧНЫЙ ПЕРЕЗАПУСК ==========
while true do
    local ok, err = pcall(main)
    if not ok then
        print("Ошибка сервера: " .. tostring(err))
        os.sleep(5)
    end
end
