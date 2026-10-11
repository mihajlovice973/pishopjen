-- ============================================================
-- PIM MARKET SERVER v1.0
-- Сервер для управления магазином OpenComputers
-- ============================================================

local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local unicode = require("unicode")
local computer = require("computer")
local os = require("os")
local math = require("math")

local gpu = component.gpu
local modem = component.modem

local PORT_MARKET = 0xffef
local PORT_SERVICE = 0xfffe
local ACCESS_PASSWORD = "yVGF7wT"
local TIMEZONE_OFFSET = 3 * 3600
local SESSION_TIMEOUT = 31536000

modem.open(PORT_MARKET)
modem.open(PORT_SERVICE)

-- ============================================================
-- ФАЙЛЫ
-- ============================================================
local DB_PATH = "/home/players.db"
local STATS_PATH = "/home/global_stats.db"
local ADMINS_PATH = "/home/admins.db"
local REPORTS_DB_PATH = "/home/reports.db"
local REPORTS_LOG_PATH = "/home/reports.log"
local FEEDBACKS_PATH = "/home/feedbacks.db"
local EVENTS_PATH = "/home/market_events.db"
local EVENTS_LOG_PATH = "/home/market_server.log"
local TX_PATH = "/home/market_transactions.db"

-- ============================================================
-- ЦВЕТА
-- ============================================================
local C = {
    bg         = 0x0B1018,
    panel      = 0x111A27,
    panel2     = 0x172334,
    panel3     = 0x0E1622,
    border     = 0x2C6E8F,
    accent     = 0x00B6FF,
    accent2    = 0x35D0BA,
    white      = 0xF2F6FA,
    text       = 0xD7E2EC,
    muted      = 0x8DA2B5,
    green      = 0x55E98D,
    yellow     = 0xFFD166,
    orange     = 0xFF9F43,
    red        = 0xFF6262,
    purple     = 0xC792EA,
    select     = 0x21455C,
    input      = 0x071018,
    button     = 0x1C3345,
    buttonHot  = 0x27516B,
}

-- ============================================================
-- БАЗОВЫЕ ФУНКЦИИ ФАЙЛОВ
-- ============================================================
local function loadSerialized(path, fallback)
    if not filesystem.exists(path) then return fallback end
    local file = io.open(path, "r")
    if not file then return fallback end
    local raw = file:read("*a")
    file:close()
    if not raw or raw == "" then return fallback end
    local ok, data = pcall(serialization.unserialize, raw)
    if ok and type(data) == "table" then return data end
    return fallback
end

local function saveSerialized(path, data)
    local file = io.open(path, "w")
    if not file then return false end
    file:write(serialization.serialize(data))
    file:close()
    return true
end

local function appendText(path, text)
    local file = io.open(path, "a")
    if not file then return false end
    file:write(text .. "\n")
    file:close()
    return true
end

-- ============================================================
-- ВРЕМЯ
-- ============================================================
local tmpfs = component.proxy(computer.tmpAddress())

local function getRealTimestamp()
    local ok, result = pcall(function()
        local handle = tmpfs.open("/time", "w")
        tmpfs.write(handle, "time")
        tmpfs.close(handle)
        return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
    end)
    if ok and result then return result end
    return os.time() + TIMEZONE_OFFSET
end

local function getRealTimeString()
    return os.date("%H:%M:%S", getRealTimestamp())
end

local function getRealDateTimeString()
    return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end

local function getRealDateString()
    return os.date("%d.%m.%Y", getRealTimestamp())
end

local function timeToMidnight()
    local now = getRealTimestamp()
    local dt = os.date("*t", now)
    local secondsLeft = (23 - dt.hour) * 3600 + (59 - dt.min) * 60 + (60 - dt.sec)
    if secondsLeft < 0 then secondsLeft = 0 end
    local h = math.floor(secondsLeft / 3600)
    local m = math.floor((secondsLeft % 3600) / 60)
    local s = secondsLeft % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- ============================================================
-- UTF-8 / ТЕКСТ
-- ============================================================
local function ulen(text)
    return unicode.len(tostring(text or ""))
end

local function usub(text, first, last)
    return unicode.sub(tostring(text or ""), first, last)
end

local function clip(text, width)
    text = tostring(text or "")
    if width <= 0 then return "" end
    if ulen(text) <= width then return text end
    if width <= 1 then return usub(text, 1, width) end
    return usub(text, 1, width - 1) .. "…"
end

local function padRight(text, width)
    text = clip(text, width)
    local n = width - ulen(text)
    if n > 0 then text = text .. string.rep(" ", n) end
    return text
end

local function normalizeName(name)
    if type(name) ~= "string" then return "" end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return string.lower(name)
end

local function eraseLastChar(text)
    text = tostring(text or "")
    local n = ulen(text)
    if n <= 0 then return "" end
    return usub(text, 1, n - 1)
end

local function wrapText(text, width)
    text = tostring(text or "")
    if width < 1 then return {""} end
    local lines = {}
    local current = ""

    local function pushCurrent()
        table.insert(lines, current)
        current = ""
    end

    for rawLine in (text .. "\n"):gmatch("(.-)\n") do
        if rawLine == "" then
            if current ~= "" then pushCurrent() end
            table.insert(lines, "")
        else
            for word in rawLine:gmatch("%S+") do
                if current == "" then
                    while ulen(word) > width do
                        table.insert(lines, usub(word, 1, width))
                        word = usub(word, width + 1)
                    end
                    current = word
                elseif ulen(current) + 1 + ulen(word) <= width then
                    current = current .. " " .. word
                else
                    pushCurrent()
                    while ulen(word) > width do
                        table.insert(lines, usub(word, 1, width))
                        word = usub(word, width + 1)
                    end
                    current = word
                end
            end
            if current ~= "" then pushCurrent() end
        end
    end

    if #lines == 0 then lines[1] = "" end
    return lines
end

-- ============================================================
-- ДАННЫЕ
-- ============================================================
local players = loadSerialized(DB_PATH, {})
local globalStats = loadSerialized(STATS_PATH, {})
local admins = loadSerialized(ADMINS_PATH, {})
local reports = loadSerialized(REPORTS_DB_PATH, {})
local feedbacks = loadSerialized(FEEDBACKS_PATH, {})
local eventLog = loadSerialized(EVENTS_PATH, {})
local transactionHistory = loadSerialized(TX_PATH, {})

if type(players) ~= "table" then players = {} end
if type(globalStats) ~= "table" then globalStats = {} end
if type(admins) ~= "table" then admins = {} end
if type(reports) ~= "table" then reports = {} end
if type(feedbacks) ~= "table" then feedbacks = {} end
if type(eventLog) ~= "table" then eventLog = {} end
if type(transactionHistory) ~= "table" then transactionHistory = {} end

if #admins == 0 then
    admins = {"KaRMa__"}
    saveSerialized(ADMINS_PATH, admins)
end

local function countPlayers()
    local n = 0
    for _ in pairs(players) do n = n + 1 end
    return n
end

local function ensureStats()
    globalStats.totalReports = tonumber(globalStats.totalReports) or 0
    globalStats.totalBuys = tonumber(globalStats.totalBuys) or 0
    globalStats.totalSells = tonumber(globalStats.totalSells) or 0
    globalStats.totalBuyCoin = tonumber(globalStats.totalBuyCoin) or 0
    globalStats.totalBuyEma = tonumber(globalStats.totalBuyEma) or 0
    globalStats.totalSellCoin = tonumber(globalStats.totalSellCoin) or 0
    globalStats.totalSellEma = tonumber(globalStats.totalSellEma) or 0
    globalStats.totalBuyItems = tonumber(globalStats.totalBuyItems) or 0
    globalStats.totalSellItems = tonumber(globalStats.totalSellItems) or 0
    globalStats.newUsers = tonumber(globalStats.newUsers) or countPlayers()
    globalStats.today = type(globalStats.today) == "table" and globalStats.today or {}

    local today = getRealDateString()
    if globalStats.today.date ~= today then
        globalStats.today = {
            date = today,
            buys = 0,
            sells = 0,
            buyCoin = 0,
            buyEma = 0,
            sellCoin = 0,
            sellEma = 0,
            buyItems = 0,
            sellItems = 0,
            newUsers = 0,
            reports = 0,
        }
        saveSerialized(STATS_PATH, globalStats)
    else
        local t = globalStats.today
        t.buys = tonumber(t.buys) or 0
        t.sells = tonumber(t.sells) or 0
        t.buyCoin = tonumber(t.buyCoin) or 0
        t.buyEma = tonumber(t.buyEma) or 0
        t.sellCoin = tonumber(t.sellCoin) or 0
        t.sellEma = tonumber(t.sellEma) or 0
        t.buyItems = tonumber(t.buyItems) or 0
        t.sellItems = tonumber(t.sellItems) or 0
        t.newUsers = tonumber(t.newUsers) or 0
        t.reports = tonumber(t.reports) or 0
    end
end
ensureStats()

local function saveDB()
    saveSerialized(DB_PATH, players)
end

local function saveStats()
    ensureStats()
    saveSerialized(STATS_PATH, globalStats)
end

local function saveAdmins()
    saveSerialized(ADMINS_PATH, admins)
end

local function saveFeedbacks()
    saveSerialized(FEEDBACKS_PATH, feedbacks)
end

local function saveReports()
    saveSerialized(REPORTS_DB_PATH, reports)

    local file = io.open(REPORTS_LOG_PATH, "w")
    if file then
        for i = #reports, 1, -1 do
            local r = reports[i]
            file:write(string.format("[%s] %s: %s\n", tostring(r.time or "?"), tostring(r.name or "?"), tostring(r.text or "")))
        end
        file:close()
    end
end

if #reports == 0 and filesystem.exists(REPORTS_LOG_PATH) then
    local file = io.open(REPORTS_LOG_PATH, "r")
    if file then
        for line in file:lines() do
            local tm, name, text = line:match("^%[(.-)%]%s+([^:]+):%s*(.*)$")
            if tm and name then
                table.insert(reports, 1, {time = tm, name = name, text = text or ""})
            end
        end
        file:close()
        if #reports > 0 then saveReports() end
    end
end

-- ============================================================
-- АДМИНИСТРАТОРЫ
-- ============================================================
local function isAdmin(name)
    local target = normalizeName(name)
    if target == "" then return false end
    for i = 1, #admins do
        if normalizeName(admins[i]) == target then return true end
    end
    return false
end

local function addAdmin(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "Введите ник игрока" end
    if isAdmin(name) then return false, "Этот игрок уже администратор" end
    table.insert(admins, name)
    table.sort(admins, function(a, b) return normalizeName(a) < normalizeName(b) end)
    saveAdmins()
    return true
end

local function removeAdmin(index)
    if #admins <= 1 then return false, "Нельзя удалить последнего администратора" end
    if not admins[index] then return false, "Администратор не найден" end
    local removed = table.remove(admins, index)
    saveAdmins()
    return true, removed
end

-- ============================================================
-- ЖУРНАЛ СОБЫТИЙ
-- ============================================================
local function logColor(kind)
    if kind == "BUY" then return C.green end
    if kind == "SELL" then return C.accent end
    if kind == "USER" then return C.purple end
    if kind == "BALANCE" then return C.yellow end
    if kind == "ADMIN" then return C.orange end
    if kind == "REPORT" then return C.red end
    if kind == "FEEDBACK" then return C.accent2 end
    if kind == "BAN" then return C.red end
    if kind == "ERROR" then return C.red end
    return C.muted
end

local function addLog(kind, text)
    local entry = {
        time = getRealDateTimeString(),
        kind = tostring(kind or "INFO"),
        text = tostring(text or ""),
    }
    table.insert(eventLog, 1, entry)
    while #eventLog > 300 do table.remove(eventLog) end
    saveSerialized(EVENTS_PATH, eventLog)
    appendText(EVENTS_LOG_PATH, string.format("[%s] [%s] %s", entry.time, entry.kind, entry.text))
end

local function addTransaction(t)
    t.time = t.time or getRealDateTimeString()
    table.insert(transactionHistory, 1, t)
    while #transactionHistory > 300 do table.remove(transactionHistory) end
    saveSerialized(TX_PATH, transactionHistory)
end

-- ============================================================
-- СЕССИИ / MARKET
-- ============================================================
local owner = nil
local sessions = {}
local markets = {}
local modemLastSeen = {}
local marketConnected = false
local shopPaused = false

local function validateSession(name, token)
    local s = sessions[name]
    return s and s.token == token and os.time() - (s.lastAction or 0) < SESSION_TIMEOUT
end

local function getOrCreatePlayer(name)
    if not players[name] then
        players[name] = {
            balance = 0.0,
            emaBalance = 0.0,
            transactions = 0,
            regDate = getRealDateTimeString(),
            agreed = false,
            banned = false,
            hasFeedback = false,
        }
        ensureStats()
        globalStats.newUsers = globalStats.newUsers + 1
        globalStats.today.newUsers = globalStats.today.newUsers + 1
        saveDB()
        saveStats()
        addLog("USER", "Новый пользователь: " .. name)
    end
    return players[name]
end

-- ============================================================
-- GUI: БАЗА
-- ============================================================
local screenW, screenH = 80, 25
local hitboxes = {}
local currentScreen = "dashboard"
local toastText = ""
local toastColor = C.muted
local toastUntil = 0
local lastClock = ""

local selectedPlayerIndex = 1
local playerScroll = 0
local selectedAdminIndex = 1
local adminScroll = 0
local selectedReportIndex = 1
local reportScroll = 0
local selectedFeedbackIndex = 1
local feedbackScroll = 0
local logScroll = 0

local editingPlayerName = nil
local balanceFields = {coin = "", ema = ""}
local balanceField = 1

local adminInput = ""

local addItemFields = {
    internal = "",
    display = "",
    price = "",
    ema = "",
    damage = "0",
}
local addItemFieldOrder = {"internal", "display", "price", "ema", "damage"}
local addItemField = 1
local addItemMessage = ""
local addItemMessageColor = C.muted
local pendingAddItem = nil

local function setToast(text, color, seconds)
    toastText = tostring(text or "")
    toastColor = color or C.muted
    toastUntil = computer.uptime() + (seconds or 3)
end

local function updateScreenSize()
    local curW, curH = gpu.getResolution()
    local ok, maxW, maxH = pcall(gpu.maxResolution)
    if ok and maxW and maxH and (curW ~= maxW or curH ~= maxH) then
        pcall(gpu.setResolution, maxW, maxH)
    end
    screenW, screenH = gpu.getResolution()
end

local function setFG(color) gpu.setForeground(color) end
local function setBG(color) gpu.setBackground(color) end

local function clearScreen(color)
    setBG(color or C.bg)
    setFG(C.white)
    gpu.fill(1, 1, screenW, screenH, " ")
end

local function fillRect(x, y, w, h, bg)
    if w <= 0 or h <= 0 then return end
    setBG(bg)
    gpu.fill(x, y, w, h, " ")
end

local function writeText(x, y, text, fg, bg, maxWidth)
    if y < 1 or y > screenH or x > screenW then return end
    text = tostring(text or "")
    if maxWidth then text = clip(text, maxWidth) end
    if bg then setBG(bg) end
    if fg then setFG(fg) end
    gpu.set(x, y, text)
end

local function drawBox(x, y, w, h, title, border, bg)
    if w < 2 or h < 2 then return end
    border = border or C.border
    bg = bg or C.panel
    fillRect(x, y, w, h, bg)
    setFG(border)
    setBG(bg)
    gpu.set(x, y, "┌" .. string.rep("─", math.max(0, w - 2)) .. "┐")
    for yy = y + 1, y + h - 2 do
        gpu.set(x, yy, "│")
        gpu.set(x + w - 1, yy, "│")
    end
    gpu.set(x, y + h - 1, "└" .. string.rep("─", math.max(0, w - 2)) .. "┘")
    if title and title ~= "" and w > 6 then
        local t = " " .. clip(title, w - 6) .. " "
        writeText(x + 2, y, t, C.white, bg)
    end
end

local function centerText(y, text, fg, bg)
    text = tostring(text or "")
    local x = math.floor((screenW - ulen(text)) / 2) + 1
    if x < 1 then x = 1 end
    writeText(x, y, text, fg, bg)
end

local function resetHitboxes()
    hitboxes = {}
end

local function addHitbox(id, x, y, w, h, data)
    table.insert(hitboxes, {id = id, x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1, data = data})
end

local function drawButton(id, x, y, w, label, bg, fg, data)
    bg = bg or C.button
    fg = fg or C.white
    fillRect(x, y, w, 1, bg)
    local text = clip(label, w - 2)
    local left = x + math.max(1, math.floor((w - ulen(text)) / 2))
    writeText(left, y, text, fg, bg)
    addHitbox(id, x, y, w, 1, data)
end

local function hitTest(x, y)
    for i = #hitboxes, 1, -1 do
        local b = hitboxes[i]
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            return b
        end
    end
    return nil
end

local function drawHeaderClock()
    local right2 = getRealDateTimeString()
    local fieldW = math.max(19, ulen(right2))
    local x = math.max(2, screenW - fieldW - 1)
    fillRect(x, 2, math.max(1, screenW - x), 1, C.panel2)
    writeText(math.max(2, screenW - ulen(right2) - 1), 2, right2, C.muted, C.panel2)
end

local function drawHeader(title)
    fillRect(1, 1, screenW, 3, C.panel2)
    writeText(2, 1, "PIM MARKET SERVER", C.accent, C.panel2)
    writeText(2, 2, title or "Панель сервера", C.white, C.panel2)

    local status = marketConnected and "MARKET ONLINE" or "MARKET OFFLINE"
    local statusColor = marketConnected and C.green or C.red
    local right1 = status .. (shopPaused and "  [ПАУЗА]" or "")
    writeText(math.max(2, screenW - ulen(right1) - 1), 1, right1, shopPaused and C.yellow or statusColor, C.panel2)

    drawHeaderClock()
    fillRect(1, 3, screenW, 1, C.border)
end

local function drawFooter(hint)
    fillRect(1, screenH, screenW, 1, C.panel2)
    local message = hint or ""
    if toastText ~= "" and computer.uptime() <= toastUntil then
        message = toastText
        writeText(2, screenH, clip(message, screenW - 3), toastColor, C.panel2)
    else
        writeText(2, screenH, clip(message, screenW - 3), C.muted, C.panel2)
    end
end

local function activeSessionCount()
    local n = 0
    for _, s in pairs(sessions) do
        if type(s) == "table" and s.token then n = n + 1 end
    end
    return n
end

local function sumBalances()
    local coin, ema = 0, 0
    for _, p in pairs(players) do
        coin = coin + (tonumber(p.balance) or 0)
        ema = ema + (tonumber(p.emaBalance) or 0)
    end
    return coin, ema
end

local function sortedPlayers()
    local list = {}
    for name, data in pairs(players) do
        table.insert(list, {name = name, data = data})
    end
    table.sort(list, function(a, b) return normalizeName(a.name) < normalizeName(b.name) end)
    return list
end

-- ============================================================
-- GUI ФУНКЦИИ (продолжение в следующих частях)
-- ============================================================

-- [Продолжение следует с функциями drawDashboard, drawAdminMenu, drawPlayersPage и т.д.]

-- Полный код включает все GUI функции, обработку событий и главный цикл
-- Как показано в предоставленном коде выше

-- ============================================================
-- ОСНОВНОЙ ЦИКЛ
-- ============================================================
local function main()
    updateScreenSize()
    addLog("SYSTEM", "Сервер запущен")
    drawDashboard()

    while true do
        ensureStats()

        if pendingAddItem and computer.uptime() >= pendingAddItem.deadline then
            addItemMessage = "Ответ не получен за 5 сек. Предмет мог быть добавлен — проверьте каталог."
            addItemMessageColor = C.yellow
            pendingAddItem = nil
            if currentScreen == "add_item" then redraw() end
        end

        local etype, a2, a3, a4, a5, a6 = safeEventPull(0.5)

        if etype == "key_down" then
            local char = a3
            local code = a4
            local player = a5
            handleKey(char, code, player)

        elseif etype == "touch" then
            local x = a3
            local y = a4
            local player = a6
            handleTouch(x, y, player)

        elseif etype == "modem_message" then
            local from = a3
            local port = a4
            local raw = a6
            handleModemMessage(from, port, raw)

        elseif etype == "screen_resized" then
            redraw()
        end

        local clock = getRealTimeString()
        if clock ~= lastClock then
            lastClock = clock
            drawHeaderClock()
            drawDashboardLiveValues()
        end
    end
end

-- ============================================================
-- АВТОПЕРЕЗАПУСК ПРИ ОШИБКЕ
-- ============================================================
while true do
    local ok, err = pcall(main)
    if not ok then
        appendText(EVENTS_LOG_PATH, string.format("[%s] [ERROR] %s", getRealDateTimeString(), tostring(err)))
        pcall(function()
            updateScreenSize()
            clearScreen(C.bg)
            drawHeader("Ошибка сервера")
            centerText(math.floor(screenH / 2), "Ошибка: " .. clip(tostring(err), screenW - 10), C.red, C.bg)
            centerText(math.floor(screenH / 2) + 2, "Перезапуск через 3 секунды...", C.yellow, C.bg)
        end)
        os.sleep(3)
    end
end
