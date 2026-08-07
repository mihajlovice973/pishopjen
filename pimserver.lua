local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local unicode = require("unicode")
local computer = require("computer")
local os = require("os")
local math = require("math")

-- ============================================================
-- PIM MARKET SERVER UI v2.0
-- Полностью GPU-интерфейс без ANSI escape-последовательностей.
-- Это убирает мусорные символы при стирании/перерисовке.
-- ============================================================

local gpu = component.gpu
local modem = component.modem

local PORT_MARKET = 0xffef
local PORT_SERVICE = 0xfffe
local ACCESS_PASSWORD = "secret"
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

    -- reports.log оставляем для совместимости и простого чтения вручную.
    local file = io.open(REPORTS_LOG_PATH, "w")
    if file then
        for i = #reports, 1, -1 do
            local r = reports[i]
            file:write(string.format("[%s] %s: %s\n", tostring(r.time or "?"), tostring(r.name or "?"), tostring(r.text or "")))
        end
        file:close()
    end
end

-- Импорт старого reports.log, если reports.db ещё не создавался.
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
    damage = "0",
}
local addItemFieldOrder = {"internal", "display", "price", "damage"}
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
    if screenW < 80 or screenH < 25 then
        -- Интерфейс умеет работать и ниже, но 80x25 — рекомендуемый минимум.
    end
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

local function drawHeader(title)
    fillRect(1, 1, screenW, 3, C.panel2)
    writeText(2, 1, "PIM MARKET SERVER", C.accent, C.panel2)
    writeText(2, 2, title or "Панель сервера", C.white, C.panel2)

    local status = marketConnected and "MARKET ONLINE" or "MARKET OFFLINE"
    local statusColor = marketConnected and C.green or C.red
    local right1 = status .. (shopPaused and "  [ПАУЗА]" or "")
    writeText(math.max(2, screenW - ulen(right1) - 1), 1, right1, shopPaused and C.yellow or statusColor, C.panel2)

    local right2 = getRealDateTimeString()
    writeText(math.max(2, screenW - ulen(right2) - 1), 2, right2, C.muted, C.panel2)
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
-- GUI: DASHBOARD
-- ============================================================
local function drawDashboard()
    currentScreen = "dashboard"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Главная панель")
    ensureStats()

    local margin = 2
    local gap = 1
    local cardW = math.floor((screenW - margin * 2 - gap * 3) / 4)
    local cardY = 5
    local cardH = 5
    local cards = {
        {"ПОЛЬЗОВАТЕЛИ", tostring(countPlayers()), C.purple},
        {"ПОКУПКИ", tostring(globalStats.totalBuys), C.green},
        {"ПРОДАЖИ", tostring(globalStats.totalSells), C.accent},
        {"СЕССИИ", tostring(activeSessionCount()), C.yellow},
    }

    for i = 1, 4 do
        local x = margin + (i - 1) * (cardW + gap)
        drawBox(x, cardY, cardW, cardH, cards[i][1], cards[i][3], C.panel)
        local value = cards[i][2]
        local vx = x + math.floor((cardW - ulen(value)) / 2)
        writeText(vx, cardY + 2, value, cards[i][3], C.panel)
    end

    local bodyY = cardY + cardH + 1
    local bodyH = screenH - bodyY - 5
    if bodyH < 7 then bodyH = 7 end
    local leftW = math.floor(screenW * 0.64)
    local rightX = leftW + 2
    local rightW = screenW - rightX

    drawBox(2, bodyY, leftW - 2, bodyH, "ВАЖНЫЕ СОБЫТИЯ", C.border, C.panel)
    local maxLogs = bodyH - 2
    for i = 1, math.min(maxLogs, #eventLog) do
        local e = eventLog[i]
        local tm = tostring(e.time or "")
        local shortTime = tm:match("(%d%d:%d%d:%d%d)$") or tm
        local prefix = "[" .. shortTime .. "] [" .. tostring(e.kind or "INFO") .. "] "
        local line = prefix .. tostring(e.text or "")
        writeText(3, bodyY + i, clip(line, leftW - 5), logColor(e.kind), C.panel)
    end
    if #eventLog == 0 then
        writeText(3, bodyY + 2, "Пока нет важных событий.", C.muted, C.panel)
    end

    drawBox(rightX, bodyY, rightW, bodyH, "СОСТОЯНИЕ", C.accent2, C.panel)
    local coin, ema = sumBalances()
    local info = {
        {"MARKET", marketConnected and "ONLINE" or "OFFLINE", marketConnected and C.green or C.red},
        {"Магазин", shopPaused and "ПАУЗА" or "РАБОТАЕТ", shopPaused and C.yellow or C.green},
        {"Баланс COIN", string.format("%.2f", coin), C.yellow},
        {"Баланс EMA", string.format("%.2f", ema), C.accent},
        {"Репортов", tostring(#reports), C.red},
        {"Отзывов", tostring(#feedbacks), C.accent2},
        {"До полуночи", timeToMidnight(), C.muted},
    }
    for i = 1, math.min(#info, bodyH - 2) do
        local y = bodyY + i
        writeText(rightX + 1, y, clip(info[i][1] .. ":", math.floor(rightW * 0.48)), C.muted, C.panel)
        writeText(rightX + math.floor(rightW * 0.48), y, clip(info[i][2], math.floor(rightW * 0.48)), info[i][3], C.panel)
    end

    local by = screenH - 3
    local bw = math.max(14, math.floor((screenW - 7) / 4))
    drawButton("admin_menu", 2, by, bw, "АДМИН-ПАНЕЛЬ [A]", C.buttonHot, C.white)
    drawButton("stats", 3 + bw, by, bw, "СТАТИСТИКА", C.button, C.white)
    drawButton("logs", 4 + bw * 2, by, bw, "ЖУРНАЛ", C.button, C.white)
    drawButton("refresh", 5 + bw * 3, by, math.max(10, screenW - (5 + bw * 3) - 1), "ОБНОВИТЬ [R]", C.button, C.white)
    drawFooter("A - админ-панель | R - обновить | управление также работает мышкой")
end

-- ============================================================
-- GUI: АДМИН-МЕНЮ
-- ============================================================
local function drawAdminMenu()
    currentScreen = "admin_menu"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Администрирование")

    local items = {
        {"players", "ИГРОКИ", "Балансы, блокировки, транзакции", C.purple},
        {"stats", "СТАТИСТИКА", "Покупки, продажи, оборот", C.green},
        {"reports", "РЕПОРТЫ", "Чтение и удаление жалоб", C.red},
        {"feedbacks", "ОТЗЫВЫ", "Чтение и удаление отзывов", C.accent2},
        {"admins", "АДМИНИСТРАТОРЫ", "Добавить или удалить админа", C.orange},
        {"add_item", "ДОБАВИТЬ ПРЕДМЕТ", "Отправить предмет в каталог", C.accent},
        {"logs", "ЖУРНАЛ", "Только важные события", C.yellow},
        {"pause", shopPaused and "ВОЗОБНОВИТЬ МАГАЗИН" or "ПРИОСТАНОВИТЬ МАГАЗИН", "Управление доступностью терминалов", shopPaused and C.green or C.yellow},
    }

    local cols = 3
    local gapX = 1
    local gapY = 1
    local boxW = math.floor((screenW - 4 - gapX * (cols - 1)) / cols)
    local boxH = 4
    local startY = 5

    for i = 1, #items do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = 2 + col * (boxW + gapX)
        local y = startY + row * (boxH + gapY)
        drawBox(x, y, boxW, boxH, items[i][2], items[i][4], C.panel)
        writeText(x + 2, y + 2, clip(items[i][3], boxW - 4), C.muted, C.panel)
        addHitbox(items[i][1], x, y, boxW, boxH)
    end

    drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
    drawFooter("Esc - назад | выберите раздел мышкой")
end

-- ============================================================
-- GUI: ИГРОКИ
-- ============================================================
local function drawPlayersPage()
    currentScreen = "players"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Игроки")

    local list = sortedPlayers()
    if selectedPlayerIndex < 1 then selectedPlayerIndex = 1 end
    if selectedPlayerIndex > #list then selectedPlayerIndex = math.max(1, #list) end

    local leftW = math.floor(screenW * 0.58)
    local listY = 5
    local listH = screenH - 8
    drawBox(2, listY, leftW - 2, listH, "СПИСОК ИГРОКОВ", C.border, C.panel)

    local visible = listH - 3
    if selectedPlayerIndex <= playerScroll then playerScroll = selectedPlayerIndex - 1 end
    if selectedPlayerIndex > playerScroll + visible then playerScroll = selectedPlayerIndex - visible end
    if playerScroll < 0 then playerScroll = 0 end

    writeText(3, listY + 1, padRight("НИК", math.max(8, math.floor(leftW * 0.36))) .. "COIN        EMA      ТРАНЗ.", C.muted, C.panel)

    for row = 1, visible do
        local idx = playerScroll + row
        local p = list[idx]
        if not p then break end
        local y = listY + 1 + row
        local bg = idx == selectedPlayerIndex and C.select or C.panel
        fillRect(3, y, leftW - 4, 1, bg)
        local nameW = math.max(8, math.floor(leftW * 0.36))
        local line = padRight(p.name, nameW)
            .. string.format("%10.2f  %8.2f  %5d", tonumber(p.data.balance) or 0, tonumber(p.data.emaBalance) or 0, tonumber(p.data.transactions) or 0)
        if p.data.banned then line = line .. "  BAN" end
        writeText(3, y, clip(line, leftW - 4), p.data.banned and C.red or C.text, bg)
        addHitbox("player_select", 3, y, leftW - 4, 1, idx)
    end

    local rightX = leftW + 1
    local rightW = screenW - rightX
    drawBox(rightX, listY, rightW, listH, "УПРАВЛЕНИЕ", C.accent, C.panel)

    local selected = list[selectedPlayerIndex]
    if selected then
        local p = selected.data
        local y = listY + 2
        writeText(rightX + 2, y, "Игрок: " .. selected.name, C.white, C.panel); y = y + 2
        writeText(rightX + 2, y, "COIN: " .. string.format("%.2f", tonumber(p.balance) or 0), C.yellow, C.panel); y = y + 1
        writeText(rightX + 2, y, "EMA:  " .. string.format("%.2f", tonumber(p.emaBalance) or 0), C.accent, C.panel); y = y + 1
        writeText(rightX + 2, y, "Транзакций: " .. tostring(p.transactions or 0), C.text, C.panel); y = y + 1
        writeText(rightX + 2, y, "Регистрация: " .. tostring(p.regDate or "?"), C.muted, C.panel); y = y + 1
        writeText(rightX + 2, y, "Статус: " .. (p.banned and "ЗАБЛОКИРОВАН" or "АКТИВЕН"), p.banned and C.red or C.green, C.panel)

        local bw = math.max(14, rightW - 4)
        local by = listY + listH - 6
        drawButton("edit_balance", rightX + 2, by, bw, "РЕДАКТИРОВАТЬ БАЛАНС", C.buttonHot, C.white)
        drawButton("toggle_ban", rightX + 2, by + 2, bw, p.banned and "РАЗБЛОКИРОВАТЬ" or "ЗАБЛОКИРОВАТЬ", p.banned and C.green or C.red, C.white)
        drawButton("reset_transactions", rightX + 2, by + 4, bw, "СБРОСИТЬ СЧЁТЧИК ТРАНЗАКЦИЙ", C.button, C.white)
    else
        writeText(rightX + 2, listY + 2, "Игроков пока нет.", C.muted, C.panel)
    end

    drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
    drawFooter("↑/↓ - выбор | Enter - баланс | Esc - назад")
end

-- ============================================================
-- GUI: РЕДАКТИРОВАНИЕ БАЛАНСА
-- ============================================================
local function drawBalanceEditor()
    currentScreen = "edit_balance"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Редактирование баланса")

    local p = editingPlayerName and players[editingPlayerName] or nil
    if not p then
        setToast("Игрок не найден", C.red, 3)
        currentScreen = "players"
        drawPlayersPage()
        return
    end

    local w = math.min(70, screenW - 6)
    local h = 15
    local x = math.floor((screenW - w) / 2) + 1
    local y = math.max(5, math.floor((screenH - h) / 2))
    drawBox(x, y, w, h, "БАЛАНС ИГРОКА " .. editingPlayerName, C.yellow, C.panel)

    writeText(x + 3, y + 2, "Текущий COIN: " .. string.format("%.2f", tonumber(p.balance) or 0), C.muted, C.panel)
    writeText(x + 3, y + 3, "Текущий EMA:  " .. string.format("%.2f", tonumber(p.emaBalance) or 0), C.muted, C.panel)

    local inputW = w - 6
    local fields = {
        {key = "coin", label = "Новый COIN", color = C.yellow},
        {key = "ema", label = "Новый EMA", color = C.accent},
    }

    for i = 1, 2 do
        local fy = y + 5 + (i - 1) * 3
        writeText(x + 3, fy, fields[i].label, fields[i].color, C.panel)
        local bg = balanceField == i and C.select or C.input
        fillRect(x + 3, fy + 1, inputW, 1, bg)
        local value = balanceFields[fields[i].key]
        local cursor = balanceField == i and "█" or ""
        writeText(x + 4, fy + 1, clip(value .. cursor, inputW - 2), C.white, bg)
        addHitbox("balance_field", x + 3, fy, inputW, 2, i)
    end

    local bw = math.floor((w - 8) / 2)
    drawButton("balance_save", x + 3, y + h - 2, bw, "СОХРАНИТЬ", C.green, C.bg)
    drawButton("back", x + 5 + bw, y + h - 2, bw, "НАЗАД", C.button, C.white)
    drawFooter("Tab - следующее поле | Enter - сохранить | Esc - назад | Backspace работает без мусора")
end

-- ============================================================
-- GUI: АДМИНИСТРАТОРЫ
-- ============================================================
local function drawAdminsPage()
    currentScreen = "admins"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Администраторы")

    local w = math.min(90, screenW - 6)
    local x = math.floor((screenW - w) / 2) + 1
    local y = 5
    local h = screenH - 8
    drawBox(x, y, w, h, "СПИСОК АДМИНИСТРАТОРОВ", C.orange, C.panel)

    local visible = h - 7
    if selectedAdminIndex < 1 then selectedAdminIndex = 1 end
    if selectedAdminIndex > #admins then selectedAdminIndex = math.max(1, #admins) end
    if selectedAdminIndex <= adminScroll then adminScroll = selectedAdminIndex - 1 end
    if selectedAdminIndex > adminScroll + visible then adminScroll = selectedAdminIndex - visible end
    if adminScroll < 0 then adminScroll = 0 end

    for row = 1, visible do
        local idx = adminScroll + row
        local name = admins[idx]
        if not name then break end
        local yy = y + row
        local bg = idx == selectedAdminIndex and C.select or C.panel
        fillRect(x + 2, yy, w - 4, 1, bg)
        writeText(x + 3, yy, tostring(idx) .. ". " .. name, idx == selectedAdminIndex and C.white or C.text, bg)
        addHitbox("admin_select", x + 2, yy, w - 4, 1, idx)
    end

    local bw = math.floor((w - 8) / 3)
    local by = y + h - 3
    drawButton("admin_add", x + 2, by, bw, "+ ДОБАВИТЬ", C.green, C.bg)
    drawButton("admin_delete", x + 4 + bw, by, bw, "- УДАЛИТЬ", C.red, C.white)
    drawButton("back", x + 6 + bw * 2, by, bw, "НАЗАД", C.button, C.white)
    drawFooter("↑/↓ - выбор | Insert - добавить | Delete - удалить | Esc - назад")
end

local function drawAdminAddPage()
    currentScreen = "admin_add"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Добавить администратора")

    local w = math.min(70, screenW - 6)
    local h = 10
    local x = math.floor((screenW - w) / 2) + 1
    local y = math.max(6, math.floor((screenH - h) / 2))
    drawBox(x, y, w, h, "НОВЫЙ АДМИНИСТРАТОР", C.green, C.panel)
    writeText(x + 3, y + 2, "Введите точный ник игрока:", C.text, C.panel)
    fillRect(x + 3, y + 4, w - 6, 1, C.input)
    writeText(x + 4, y + 4, clip(adminInput .. "█", w - 8), C.white, C.input)
    addHitbox("admin_input", x + 3, y + 3, w - 6, 3)

    local bw = math.floor((w - 8) / 2)
    drawButton("admin_add_confirm", x + 3, y + h - 2, bw, "ДОБАВИТЬ", C.green, C.bg)
    drawButton("back", x + 5 + bw, y + h - 2, bw, "НАЗАД", C.button, C.white)
    drawFooter("Enter - добавить | Esc - назад | Backspace - удалить символ")
end

-- ============================================================
-- GUI: РЕПОРТЫ
-- ============================================================
local function drawReportsPage()
    currentScreen = "reports"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Репорты")

    local w = screenW - 4
    local h = screenH - 8
    local x, y = 2, 5
    drawBox(x, y, w, h, "РЕПОРТЫ: " .. tostring(#reports), C.red, C.panel)

    local visible = h - 5
    if selectedReportIndex < 1 then selectedReportIndex = 1 end
    if selectedReportIndex > #reports then selectedReportIndex = math.max(1, #reports) end
    if selectedReportIndex <= reportScroll then reportScroll = selectedReportIndex - 1 end
    if selectedReportIndex > reportScroll + visible then reportScroll = selectedReportIndex - visible end
    if reportScroll < 0 then reportScroll = 0 end

    writeText(x + 2, y + 1, "#   ВРЕМЯ                ИГРОК              ТЕКСТ", C.muted, C.panel)
    for row = 1, visible do
        local idx = reportScroll + row
        local r = reports[idx]
        if not r then break end
        local yy = y + 1 + row
        local bg = idx == selectedReportIndex and C.select or C.panel
        fillRect(x + 2, yy, w - 4, 1, bg)
        local line = string.format("%-3d %-20s %-18s %s", idx, tostring(r.time or "?"), clip(r.name or "?", 16), tostring(r.text or ""))
        writeText(x + 2, yy, clip(line, w - 4), idx == selectedReportIndex and C.white or C.text, bg)
        addHitbox("report_select", x + 2, yy, w - 4, 1, idx)
    end

    local bw = math.max(14, math.floor((w - 8) / 3))
    drawButton("report_open", x + 2, y + h - 2, bw, "ОТКРЫТЬ", C.buttonHot, C.white)
    drawButton("report_delete", x + 4 + bw, y + h - 2, bw, "УДАЛИТЬ", C.red, C.white)
    drawButton("back", x + 6 + bw * 2, y + h - 2, math.min(bw, w - (6 + bw * 2)), "НАЗАД", C.button, C.white)
    drawFooter("↑/↓ - выбор | Enter - открыть | Delete - удалить | Esc - назад")
end

local function drawReportView()
    currentScreen = "report_view"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Просмотр репорта")

    local r = reports[selectedReportIndex]
    if not r then
        currentScreen = "reports"
        drawReportsPage()
        return
    end

    local x, y, w, h = 3, 5, screenW - 6, screenH - 8
    drawBox(x, y, w, h, "РЕПОРТ ОТ " .. tostring(r.name or "?"), C.red, C.panel)
    writeText(x + 2, y + 2, "Время: " .. tostring(r.time or "?"), C.muted, C.panel)
    writeText(x + 2, y + 3, "Игрок: " .. tostring(r.name or "?"), C.white, C.panel)
    writeText(x + 2, y + 5, "Сообщение:", C.red, C.panel)
    local lines = wrapText(r.text or "", w - 4)
    for i = 1, math.min(#lines, h - 8) do
        writeText(x + 2, y + 5 + i, lines[i], C.text, C.panel)
    end

    local bw = math.floor((w - 6) / 2)
    drawButton("report_delete", x + 2, y + h - 2, bw, "УДАЛИТЬ РЕПОРТ", C.red, C.white)
    drawButton("back", x + 4 + bw, y + h - 2, bw, "НАЗАД К СПИСКУ", C.button, C.white)
    drawFooter("Delete - удалить | Esc - назад")
end

-- ============================================================
-- GUI: ОТЗЫВЫ
-- ============================================================
local function drawFeedbacksPage()
    currentScreen = "feedbacks"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Отзывы")

    local w = screenW - 4
    local h = screenH - 8
    local x, y = 2, 5
    drawBox(x, y, w, h, "ОТЗЫВЫ: " .. tostring(#feedbacks), C.accent2, C.panel)

    local visible = h - 5
    if selectedFeedbackIndex < 1 then selectedFeedbackIndex = 1 end
    if selectedFeedbackIndex > #feedbacks then selectedFeedbackIndex = math.max(1, #feedbacks) end
    if selectedFeedbackIndex <= feedbackScroll then feedbackScroll = selectedFeedbackIndex - 1 end
    if selectedFeedbackIndex > feedbackScroll + visible then feedbackScroll = selectedFeedbackIndex - visible end
    if feedbackScroll < 0 then feedbackScroll = 0 end

    writeText(x + 2, y + 1, "#   ВРЕМЯ                ИГРОК              ТЕКСТ", C.muted, C.panel)
    for row = 1, visible do
        local idx = feedbackScroll + row
        local f = feedbacks[idx]
        if not f then break end
        local yy = y + 1 + row
        local bg = idx == selectedFeedbackIndex and C.select or C.panel
        fillRect(x + 2, yy, w - 4, 1, bg)
        local line = string.format("%-3d %-20s %-18s %s", idx, tostring(f.time or "?"), clip(f.name or "?", 16), tostring(f.text or ""))
        writeText(x + 2, yy, clip(line, w - 4), idx == selectedFeedbackIndex and C.white or C.text, bg)
        addHitbox("feedback_select", x + 2, yy, w - 4, 1, idx)
    end

    local bw = math.max(14, math.floor((w - 8) / 3))
    drawButton("feedback_open", x + 2, y + h - 2, bw, "ОТКРЫТЬ", C.buttonHot, C.white)
    drawButton("feedback_delete", x + 4 + bw, y + h - 2, bw, "УДАЛИТЬ", C.red, C.white)
    drawButton("back", x + 6 + bw * 2, y + h - 2, math.min(bw, w - (6 + bw * 2)), "НАЗАД", C.button, C.white)
    drawFooter("↑/↓ - выбор | Enter - открыть | Delete - удалить | Esc - назад")
end

local function drawFeedbackView()
    currentScreen = "feedback_view"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Просмотр отзыва")

    local f = feedbacks[selectedFeedbackIndex]
    if not f then
        currentScreen = "feedbacks"
        drawFeedbacksPage()
        return
    end

    local x, y, w, h = 3, 5, screenW - 6, screenH - 8
    drawBox(x, y, w, h, "ОТЗЫВ ОТ " .. tostring(f.name or "?"), C.accent2, C.panel)
    writeText(x + 2, y + 2, "Время: " .. tostring(f.time or "?"), C.muted, C.panel)
    writeText(x + 2, y + 3, "Игрок: " .. tostring(f.name or "?"), C.white, C.panel)
    writeText(x + 2, y + 5, "Текст отзыва:", C.accent2, C.panel)
    local lines = wrapText(f.text or "", w - 4)
    for i = 1, math.min(#lines, h - 8) do
        writeText(x + 2, y + 5 + i, lines[i], C.text, C.panel)
    end

    local bw = math.floor((w - 6) / 2)
    drawButton("feedback_delete", x + 2, y + h - 2, bw, "УДАЛИТЬ ОТЗЫВ", C.red, C.white)
    drawButton("back", x + 4 + bw, y + h - 2, bw, "НАЗАД К СПИСКУ", C.button, C.white)
    drawFooter("Delete - удалить | Esc - назад")
end

-- ============================================================
-- GUI: СТАТИСТИКА
-- ============================================================
local function topItems(txType, limit)
    local totals = {}
    for i = 1, #transactionHistory do
        local t = transactionHistory[i]
        if t.type == txType then
            local name = tostring(t.item or "?")
            totals[name] = (totals[name] or 0) + (tonumber(t.qty) or 0)
        end
    end
    local list = {}
    for name, qty in pairs(totals) do table.insert(list, {name = name, qty = qty}) end
    table.sort(list, function(a, b) return a.qty > b.qty end)
    while #list > (limit or 5) do table.remove(list) end
    return list
end

local function drawStatsPage()
    currentScreen = "stats"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Статистика")
    ensureStats()

    local coinBalance, emaBalance = sumBalances()
    local t = globalStats.today
    local topBuy = topItems("buy", 5)
    local topSell = topItems("sell", 5)

    local gap = 2
    local half = math.floor((screenW - 6) / 2)
    local x1 = 2
    local x2 = x1 + half + gap
    local boxY = 5
    local boxH = math.min(14, screenH - 10)

    drawBox(x1, boxY, half, boxH, "ВСЁ ВРЕМЯ", C.green, C.panel)
    local allLines = {
        {"Покупок", globalStats.totalBuys, C.green},
        {"Куплено предметов", globalStats.totalBuyItems, C.green},
        {"Потрачено COIN", string.format("%.2f", globalStats.totalBuyCoin), C.yellow},
        {"Потрачено EMA", string.format("%.2f", globalStats.totalBuyEma), C.accent},
        {"Продаж", globalStats.totalSells, C.accent},
        {"Продано предметов", globalStats.totalSellItems, C.accent},
        {"Начислено COIN", string.format("%.2f", globalStats.totalSellCoin), C.yellow},
        {"Начислено EMA", string.format("%.2f", globalStats.totalSellEma), C.accent},
        {"Пользователей", countPlayers(), C.purple},
        {"Репортов получено", globalStats.totalReports, C.red},
    }
    for i = 1, math.min(#allLines, boxH - 2) do
        writeText(x1 + 2, boxY + i, clip(allLines[i][1] .. ":", math.floor(half * 0.62)), C.muted, C.panel)
        writeText(x1 + math.floor(half * 0.62), boxY + i, tostring(allLines[i][2]), allLines[i][3], C.panel)
    end

    drawBox(x2, boxY, screenW - x2 - 1, boxH, "СЕГОДНЯ - " .. tostring(t.date), C.yellow, C.panel)
    local todayLines = {
        {"Покупок", t.buys, C.green},
        {"Куплено предметов", t.buyItems, C.green},
        {"Потрачено COIN", string.format("%.2f", t.buyCoin), C.yellow},
        {"Потрачено EMA", string.format("%.2f", t.buyEma), C.accent},
        {"Продаж", t.sells, C.accent},
        {"Продано предметов", t.sellItems, C.accent},
        {"Начислено COIN", string.format("%.2f", t.sellCoin), C.yellow},
        {"Начислено EMA", string.format("%.2f", t.sellEma), C.accent},
        {"Новых игроков", t.newUsers, C.purple},
        {"Новых репортов", t.reports, C.red},
    }
    local rightW = screenW - x2 - 1
    for i = 1, math.min(#todayLines, boxH - 2) do
        writeText(x2 + 2, boxY + i, clip(todayLines[i][1] .. ":", math.floor(rightW * 0.62)), C.muted, C.panel)
        writeText(x2 + math.floor(rightW * 0.62), boxY + i, tostring(todayLines[i][2]), todayLines[i][3], C.panel)
    end

    local lowerY = boxY + boxH + 1
    local lowerH = screenH - lowerY - 3
    if lowerH >= 5 then
        drawBox(x1, lowerY, half, lowerH, "ТОП ПОКУПАЕМЫХ ПРЕДМЕТОВ", C.green, C.panel)
        for i = 1, math.min(#topBuy, lowerH - 2) do
            writeText(x1 + 2, lowerY + i, string.format("%d. %s x%d", i, clip(topBuy[i].name, half - 12), topBuy[i].qty), C.text, C.panel)
        end
        if #topBuy == 0 then writeText(x1 + 2, lowerY + 2, "Нет новых данных.", C.muted, C.panel) end

        drawBox(x2, lowerY, rightW, lowerH, "ТОП ПРОДАВАЕМЫХ ПРЕДМЕТОВ", C.accent, C.panel)
        for i = 1, math.min(#topSell, lowerH - 2) do
            writeText(x2 + 2, lowerY + i, string.format("%d. %s x%d", i, clip(topSell[i].name, rightW - 12), topSell[i].qty), C.text, C.panel)
        end
        if #topSell == 0 then writeText(x2 + 2, lowerY + 2, "Нет новых данных.", C.muted, C.panel) end
    end

    -- Общий баланс показываем в строке над кнопкой назад.
    writeText(20, screenH - 2, string.format("Суммарные балансы: %.2f COIN | %.2f EMA", coinBalance, emaBalance), C.muted, C.bg)
    drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
    drawFooter("Статистика денежных сумм начинает накапливаться с этой версии сервера")
end

-- ============================================================
-- GUI: ЖУРНАЛ
-- ============================================================
local function drawLogsPage()
    currentScreen = "logs"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Журнал важных событий")

    local x, y, w, h = 2, 5, screenW - 4, screenH - 8
    drawBox(x, y, w, h, "ПОКУПКИ / ПРОДАЖИ / БАЛАНСЫ / ПОЛЬЗОВАТЕЛИ / АДМИН", C.yellow, C.panel)
    local visible = h - 3
    local maxScroll = math.max(0, #eventLog - visible)
    if logScroll < 0 then logScroll = 0 end
    if logScroll > maxScroll then logScroll = maxScroll end

    for row = 1, visible do
        local idx = logScroll + row
        local e = eventLog[idx]
        if not e then break end
        local line = string.format("[%s] [%-8s] %s", tostring(e.time or "?"), tostring(e.kind or "INFO"), tostring(e.text or ""))
        writeText(x + 2, y + row, clip(line, w - 4), logColor(e.kind), C.panel)
    end
    if #eventLog == 0 then writeText(x + 2, y + 2, "Журнал пока пуст.", C.muted, C.panel) end

    drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
    drawFooter("↑/↓ - прокрутка | Esc - назад | файл: /home/market_server.log")
end

-- ============================================================
-- GUI: ДОБАВЛЕНИЕ ПРЕДМЕТА
-- ============================================================
local function drawAddItemPage()
    currentScreen = "add_item"
    resetHitboxes()
    clearScreen(C.bg)
    drawHeader("Добавить предмет в каталог")

    local w = math.min(86, screenW - 6)
    local h = math.min(22, screenH - 7)
    local x = math.floor((screenW - w) / 2) + 1
    local y = 5
    drawBox(x, y, w, h, "НОВЫЙ ПРЕДМЕТ", C.accent, C.panel)

    local labels = {
        internal = "Internal Name (например minecraft:diamond)",
        display = "Название для магазина",
        price = "Цена COIN",
        damage = "Damage / Meta",
    }

    for i, key in ipairs(addItemFieldOrder) do
        local fy = y + 2 + (i - 1) * 3
        if fy + 2 < y + h - 3 then
            writeText(x + 3, fy, labels[key], i == addItemField and C.accent or C.muted, C.panel)
            local bg = i == addItemField and C.select or C.input
            fillRect(x + 3, fy + 1, w - 6, 1, bg)
            local cursor = i == addItemField and "█" or ""
            writeText(x + 4, fy + 1, clip(addItemFields[key] .. cursor, w - 8), C.white, bg)
            addHitbox("item_field", x + 3, fy, w - 6, 2, i)
        end
    end

    if addItemMessage ~= "" then
        writeText(x + 3, y + h - 4, clip(addItemMessage, w - 6), addItemMessageColor, C.panel)
    end

    local bw = math.floor((w - 8) / 2)
    drawButton("item_submit", x + 3, y + h - 2, bw, "ДОБАВИТЬ ПРЕДМЕТ", C.green, C.bg)
    drawButton("back", x + 5 + bw, y + h - 2, bw, "НАЗАД", C.button, C.white)
    drawFooter("Tab - следующее поле | Enter - отправить | Esc - назад | Backspace - удалить символ")
end

-- ============================================================
-- GUI: ПЕРЕРИСОВКА
-- ============================================================
local function redraw()
    updateScreenSize()
    if currentScreen == "dashboard" then drawDashboard()
    elseif currentScreen == "admin_menu" then drawAdminMenu()
    elseif currentScreen == "players" then drawPlayersPage()
    elseif currentScreen == "edit_balance" then drawBalanceEditor()
    elseif currentScreen == "admins" then drawAdminsPage()
    elseif currentScreen == "admin_add" then drawAdminAddPage()
    elseif currentScreen == "reports" then drawReportsPage()
    elseif currentScreen == "report_view" then drawReportView()
    elseif currentScreen == "feedbacks" then drawFeedbacksPage()
    elseif currentScreen == "feedback_view" then drawFeedbackView()
    elseif currentScreen == "stats" then drawStatsPage()
    elseif currentScreen == "logs" then drawLogsPage()
    elseif currentScreen == "add_item" then drawAddItemPage()
    else
        currentScreen = "dashboard"
        drawDashboard()
    end
end

local function goBack()
    if currentScreen == "dashboard" then return end
    if currentScreen == "report_view" then currentScreen = "reports"
    elseif currentScreen == "feedback_view" then currentScreen = "feedbacks"
    elseif currentScreen == "edit_balance" then currentScreen = "players"
    elseif currentScreen == "admin_add" then currentScreen = "admins"
    elseif currentScreen == "stats" or currentScreen == "logs" then currentScreen = "admin_menu"
    elseif currentScreen == "players" or currentScreen == "admins" or currentScreen == "reports" or currentScreen == "feedbacks" or currentScreen == "add_item" then
        currentScreen = "admin_menu"
    elseif currentScreen == "admin_menu" then currentScreen = "dashboard"
    else currentScreen = "dashboard" end
    redraw()
end

local function adminGuard(player)
    if isAdmin(player) then return true end
    setToast("Нет прав администратора", C.red, 2)
    if currentScreen ~= "dashboard" then currentScreen = "dashboard" end
    redraw()
    return false
end

-- ============================================================
-- ДЕЙСТВИЯ GUI
-- ============================================================
local function getSelectedPlayer()
    local list = sortedPlayers()
    return list[selectedPlayerIndex]
end

local function saveBalanceEdit()
    if not editingPlayerName or not players[editingPlayerName] then
        setToast("Игрок не найден", C.red, 3)
        return false
    end
    local coin = tonumber(balanceFields.coin)
    local ema = tonumber(balanceFields.ema)
    if coin == nil or ema == nil then
        setToast("COIN и EMA должны быть числами", C.red, 3)
        return false
    end
    if coin < 0 or ema < 0 then
        setToast("Баланс не может быть отрицательным", C.red, 3)
        return false
    end
    local p = players[editingPlayerName]
    local oldCoin, oldEma = tonumber(p.balance) or 0, tonumber(p.emaBalance) or 0
    p.balance = coin
    p.emaBalance = ema
    saveDB()
    addLog("BALANCE", string.format("%s: COIN %.2f -> %.2f | EMA %.2f -> %.2f", editingPlayerName, oldCoin, coin, oldEma, ema))
    setToast("Баланс сохранён", C.green, 3)
    currentScreen = "players"
    redraw()
    return true
end

local function deleteSelectedReport()
    local r = reports[selectedReportIndex]
    if not r then setToast("Репорт не выбран", C.red, 2); return end
    local name = tostring(r.name or "?")
    table.remove(reports, selectedReportIndex)
    if selectedReportIndex > #reports then selectedReportIndex = math.max(1, #reports) end
    saveReports()
    addLog("REPORT", "Удалён репорт игрока " .. name)
    setToast("Репорт удалён", C.green, 2)
    currentScreen = "reports"
    redraw()
end

local function deleteSelectedFeedback()
    local f = feedbacks[selectedFeedbackIndex]
    if not f then setToast("Отзыв не выбран", C.red, 2); return end
    local name = tostring(f.name or "?")
    table.remove(feedbacks, selectedFeedbackIndex)
    if selectedFeedbackIndex > #feedbacks then selectedFeedbackIndex = math.max(1, #feedbacks) end
    saveFeedbacks()
    if players[name] then
        players[name].hasFeedback = false
        saveDB()
    end
    addLog("FEEDBACK", "Удалён отзыв игрока " .. name)
    setToast("Отзыв удалён. Игрок сможет оставить новый.", C.green, 3)
    currentScreen = "feedbacks"
    redraw()
end

local function submitAddItem()
    local price = tonumber(addItemFields.price)
    local damage = tonumber(addItemFields.damage)
    if addItemFields.internal == "" then setToast("Введите Internal Name", C.red, 3); return end
    if addItemFields.display == "" then setToast("Введите название предмета", C.red, 3); return end
    if price == nil or price < 0 then setToast("Цена должна быть числом >= 0", C.red, 3); return end
    if damage == nil or damage < 0 then setToast("Damage должен быть числом >= 0", C.red, 3); return end
    if next(markets) == nil then setToast("Нет подключённых терминалов", C.red, 3); return end

    local data = {
        op = "add_buy_item",
        internalName = addItemFields.internal,
        displayName = addItemFields.display,
        price = price,
        damage = damage,
    }

    local sent = 0
    for addr in pairs(markets) do
        modem.send(addr, PORT_MARKET, serialization.serialize(data))
        sent = sent + 1
    end

    pendingAddItem = {
        deadline = computer.uptime() + 5,
        item = addItemFields.display,
        sent = sent,
    }
    addItemMessage = "Отправлено на " .. sent .. " терминал(ов). Ожидание ответа..."
    addItemMessageColor = C.yellow
    redraw()
end

local function processAction(id, data, player)
    -- На dashboard статистику/журнал можно смотреть, но админские действия защищены.
    if id == "refresh" then redraw(); return end
    if id == "stats" and currentScreen == "dashboard" then
        if not adminGuard(player) then return end
        currentScreen = "stats"; redraw(); return
    end
    if id == "logs" and currentScreen == "dashboard" then
        if not adminGuard(player) then return end
        currentScreen = "logs"; redraw(); return
    end

    if id == "admin_menu" then
        if not adminGuard(player) then return end
        currentScreen = "admin_menu"; redraw(); return
    end

    if id == "back" then goBack(); return end

    if currentScreen ~= "dashboard" then
        if not adminGuard(player) then return end
    end

    if id == "players" then currentScreen = "players"; redraw(); return end
    if id == "stats" then currentScreen = "stats"; redraw(); return end
    if id == "reports" then currentScreen = "reports"; redraw(); return end
    if id == "feedbacks" then currentScreen = "feedbacks"; redraw(); return end
    if id == "admins" then currentScreen = "admins"; redraw(); return end
    if id == "add_item" then currentScreen = "add_item"; redraw(); return end
    if id == "logs" then currentScreen = "logs"; redraw(); return end

    if id == "pause" then
        if not adminGuard(player) then return end
        shopPaused = not shopPaused
        addLog("ADMIN", "Магазин " .. (shopPaused and "приостановлен" or "возобновлён") .. " администратором " .. tostring(player))
        setToast(shopPaused and "Магазин поставлен на паузу" or "Магазин возобновлён", shopPaused and C.yellow or C.green, 3)
        redraw(); return
    end

    if id == "player_select" then selectedPlayerIndex = tonumber(data) or selectedPlayerIndex; redraw(); return end
    if id == "edit_balance" then
        local p = getSelectedPlayer()
        if not p then return end
        editingPlayerName = p.name
        balanceFields.coin = tostring(tonumber(p.data.balance) or 0)
        balanceFields.ema = tostring(tonumber(p.data.emaBalance) or 0)
        balanceField = 1
        currentScreen = "edit_balance"
        redraw(); return
    end
    if id == "toggle_ban" then
        local p = getSelectedPlayer()
        if not p then return end
        p.data.banned = not p.data.banned
        saveDB()
        addLog("BAN", p.name .. (p.data.banned and " заблокирован" or " разблокирован") .. " администратором " .. tostring(player))
        setToast(p.data.banned and "Игрок заблокирован" or "Игрок разблокирован", p.data.banned and C.red or C.green, 2)
        redraw(); return
    end
    if id == "reset_transactions" then
        local p = getSelectedPlayer()
        if not p then return end
        p.data.transactions = 0
        saveDB()
        addLog("ADMIN", "Сброшен счётчик транзакций игрока " .. p.name)
        setToast("Счётчик транзакций сброшен. Балансы не изменены.", C.green, 3)
        redraw(); return
    end

    if id == "balance_field" then balanceField = tonumber(data) or balanceField; redraw(); return end
    if id == "balance_save" then saveBalanceEdit(); return end

    if id == "admin_select" then selectedAdminIndex = tonumber(data) or selectedAdminIndex; redraw(); return end
    if id == "admin_add" then adminInput = ""; currentScreen = "admin_add"; redraw(); return end
    if id == "admin_add_confirm" then
        local ok, err = addAdmin(adminInput)
        if ok then
            addLog("ADMIN", "Добавлен администратор " .. adminInput .. " пользователем " .. tostring(player))
            setToast("Администратор добавлен: " .. adminInput, C.green, 3)
            adminInput = ""
            currentScreen = "admins"
        else
            setToast(err, C.red, 3)
        end
        redraw(); return
    end
    if id == "admin_delete" then
        local name = admins[selectedAdminIndex]
        local ok, value = removeAdmin(selectedAdminIndex)
        if ok then
            addLog("ADMIN", "Удалён администратор " .. tostring(value) .. " пользователем " .. tostring(player))
            setToast("Администратор удалён: " .. tostring(value), C.green, 3)
            if selectedAdminIndex > #admins then selectedAdminIndex = math.max(1, #admins) end
            if name and normalizeName(name) == normalizeName(player) then
                currentScreen = "dashboard"
            end
        else
            setToast(value, C.red, 3)
        end
        redraw(); return
    end

    if id == "report_select" then selectedReportIndex = tonumber(data) or selectedReportIndex; redraw(); return end
    if id == "report_open" then if reports[selectedReportIndex] then currentScreen = "report_view"; redraw() end; return end
    if id == "report_delete" then deleteSelectedReport(); return end

    if id == "feedback_select" then selectedFeedbackIndex = tonumber(data) or selectedFeedbackIndex; redraw(); return end
    if id == "feedback_open" then if feedbacks[selectedFeedbackIndex] then currentScreen = "feedback_view"; redraw() end; return end
    if id == "feedback_delete" then deleteSelectedFeedback(); return end

    if id == "item_field" then addItemField = tonumber(data) or addItemField; redraw(); return end
    if id == "item_submit" then submitAddItem(); return end
end

-- ============================================================
-- КЛАВИАТУРА
-- ============================================================
local function asciiKey(char)
    if type(char) ~= "number" or char < 1 or char > 255 then return nil end
    return string.lower(string.char(char))
end

local function appendInput(current, char, numeric, allowDot)
    if type(char) ~= "number" or char < 32 then return current end
    local c = unicode.char(char)
    if numeric then
        if c:match("%d") then return current .. c end
        if allowDot and (c == "." or c == ",") and not current:find("[.,]") then
            return current .. "."
        end
        return current
    end
    return current .. c
end

local function handleKey(char, code, player)
    local key = asciiKey(char)

    if currentScreen == "dashboard" then
        if key == "a" then processAction("admin_menu", nil, player); return end
        if key == "r" then redraw(); return end
        return
    end

    if char == 27 then goBack(); return end

    if not adminGuard(player) then return end

    if currentScreen == "admin_menu" then
        if key == "p" then processAction("pause", nil, player) end
        return
    end

    if currentScreen == "players" then
        local list = sortedPlayers()
        if code == 200 then selectedPlayerIndex = math.max(1, selectedPlayerIndex - 1); redraw(); return end
        if code == 208 then selectedPlayerIndex = math.min(math.max(1, #list), selectedPlayerIndex + 1); redraw(); return end
        if char == 13 then processAction("edit_balance", nil, player); return end
        if key == "b" then processAction("toggle_ban", nil, player); return end
        return
    end

    if currentScreen == "edit_balance" then
        if char == 9 then balanceField = balanceField % 2 + 1; redraw(); return end
        if char == 13 then saveBalanceEdit(); return end
        local fieldKey = balanceField == 1 and "coin" or "ema"
        if char == 8 then
            balanceFields[fieldKey] = eraseLastChar(balanceFields[fieldKey])
        else
            balanceFields[fieldKey] = appendInput(balanceFields[fieldKey], char, true, true)
        end
        redraw(); return
    end

    if currentScreen == "admins" then
        if code == 200 then selectedAdminIndex = math.max(1, selectedAdminIndex - 1); redraw(); return end
        if code == 208 then selectedAdminIndex = math.min(math.max(1, #admins), selectedAdminIndex + 1); redraw(); return end
        if code == 210 then processAction("admin_add", nil, player); return end -- Insert
        if code == 211 or char == 127 then processAction("admin_delete", nil, player); return end -- Delete
        return
    end

    if currentScreen == "admin_add" then
        if char == 13 then processAction("admin_add_confirm", nil, player); return end
        if char == 8 then adminInput = eraseLastChar(adminInput)
        else adminInput = appendInput(adminInput, char, false, false) end
        redraw(); return
    end

    if currentScreen == "reports" then
        if code == 200 then selectedReportIndex = math.max(1, selectedReportIndex - 1); redraw(); return end
        if code == 208 then selectedReportIndex = math.min(math.max(1, #reports), selectedReportIndex + 1); redraw(); return end
        if char == 13 then processAction("report_open", nil, player); return end
        if code == 211 or char == 127 then processAction("report_delete", nil, player); return end
        return
    end

    if currentScreen == "report_view" then
        if code == 211 or char == 127 then processAction("report_delete", nil, player); return end
        return
    end

    if currentScreen == "feedbacks" then
        if code == 200 then selectedFeedbackIndex = math.max(1, selectedFeedbackIndex - 1); redraw(); return end
        if code == 208 then selectedFeedbackIndex = math.min(math.max(1, #feedbacks), selectedFeedbackIndex + 1); redraw(); return end
        if char == 13 then processAction("feedback_open", nil, player); return end
        if code == 211 or char == 127 then processAction("feedback_delete", nil, player); return end
        return
    end

    if currentScreen == "feedback_view" then
        if code == 211 or char == 127 then processAction("feedback_delete", nil, player); return end
        return
    end

    if currentScreen == "logs" then
        local visible = math.max(1, screenH - 11)
        local maxScroll = math.max(0, #eventLog - visible)
        if code == 200 then logScroll = math.max(0, logScroll - 1); redraw(); return end
        if code == 208 then logScroll = math.min(maxScroll, logScroll + 1); redraw(); return end
        return
    end

    if currentScreen == "add_item" then
        if char == 9 then addItemField = addItemField % #addItemFieldOrder + 1; redraw(); return end
        if char == 13 then submitAddItem(); return end
        local fieldKey = addItemFieldOrder[addItemField]
        if char == 8 then
            addItemFields[fieldKey] = eraseLastChar(addItemFields[fieldKey])
        else
            local numeric = fieldKey == "price" or fieldKey == "damage"
            addItemFields[fieldKey] = appendInput(addItemFields[fieldKey], char, numeric, fieldKey == "price")
        end
        redraw(); return
    end
end

-- ============================================================
-- TOUCH
-- ============================================================
local function handleTouch(x, y, player)
    local b = hitTest(x, y)
    if not b then return end
    processAction(b.id, b.data, player)
end

-- ============================================================
-- MODEM
-- ============================================================
local function sendMessage(to, data)
    modem.send(to, PORT_MARKET, serialization.serialize(data))
end

local function redrawIfUseful()
    if currentScreen == "dashboard" or currentScreen == "stats" or currentScreen == "logs" or currentScreen == "players" or currentScreen == "reports" or currentScreen == "feedbacks" then
        redraw()
    end
end

local function handleModemMessage(from, raw)
    local ok, msg = pcall(serialization.unserialize, raw)
    if not ok or type(msg) ~= "table" then return end

    -- Антиспам не применяется к register/enter, чтобы не ломать авторизацию.
    if msg.op ~= "register" and msg.op ~= "enter" then
        local now = computer.uptime()
        local last = modemLastSeen[from] or 0
        if now - last < 0.05 then return end
        modemLastSeen[from] = now
    end

    if msg.op == "register" then
        if msg.password ~= ACCESS_PASSWORD then
            sendMessage(from, {op = "error", message = "Неверный пароль"})
            return
        end
        marketConnected = true
        if not owner then owner = from end
        markets[from] = true
        sendMessage(from, {op = "welcome", owner = (from == owner), shopPaused = shopPaused})
        redrawIfUseful()
        return
    end

    if msg.op == "enter" then
        if shopPaused then
            sendMessage(from, {op = "error", message = "Магазин на паузе"})
            return
        end
        local playerName = msg.name
        if not playerName or playerName == "" then return end
        local player = getOrCreatePlayer(playerName)
        if player.banned then
            sendMessage(from, {op = "error", message = "Вы забанены"})
            return
        end

        local existing = sessions[playerName]
        local token
        if existing and os.time() - (existing.lastAction or 0) < SESSION_TIMEOUT then
            token = existing.token
            existing.lastAction = os.time()
        else
            token = tostring(math.floor(math.random() * 900000000 + 100000000))
            sessions[playerName] = {token = token, lastAction = os.time()}
        end

        sendMessage(from, {
            op = "welcome",
            status = "ok",
            token = token,
            balance = player.balance or 0.0,
            emaBalance = player.emaBalance or 0.0,
            transactions = player.transactions or 0,
            regDate = player.regDate,
            agreed = player.agreed or false,
            shopPaused = shopPaused,
        })
        redrawIfUseful()
        return
    end

    if msg.op == "getAccount" then
        if not validateSession(msg.name, msg.token) then
            sendMessage(from, {op = "accountData", error = true, message = "Токен устарел"})
            return
        end
        local player = players[msg.name]
        if not player then return end
        sessions[msg.name].lastAction = os.time()
        sendMessage(from, {
            op = "accountData",
            data = {
                balance = player.balance or 0.0,
                emaBalance = player.emaBalance or 0.0,
                transactions = player.transactions or 0,
                regDate = player.regDate,
                agreed = player.agreed,
                shopPaused = shopPaused,
            }
        })
        return
    end

    if msg.op == "sell" then
        if shopPaused then
            sendMessage(from, {op = "error", message = "Магазин на паузе"})
            return
        end
        if not validateSession(msg.name, msg.token) then return end
        local player = players[msg.name]
        if not player or player.banned then return end

        local qty = tonumber(msg.qty) or 0
        local value = tonumber(msg.value) or 0
        local coinValue, emaValue = 0, 0
        if msg.internalName == "customnpcs:npcMoney" then
            player.emaBalance = (tonumber(player.emaBalance) or 0) + value
            emaValue = value
        else
            player.balance = (tonumber(player.balance) or 0) + value
            coinValue = value
        end
        player.transactions = (tonumber(player.transactions) or 0) + 1
        sessions[msg.name].lastAction = os.time()

        ensureStats()
        globalStats.totalSells = globalStats.totalSells + 1
        globalStats.totalSellItems = globalStats.totalSellItems + qty
        globalStats.totalSellCoin = globalStats.totalSellCoin + coinValue
        globalStats.totalSellEma = globalStats.totalSellEma + emaValue
        globalStats.today.sells = globalStats.today.sells + 1
        globalStats.today.sellItems = globalStats.today.sellItems + qty
        globalStats.today.sellCoin = globalStats.today.sellCoin + coinValue
        globalStats.today.sellEma = globalStats.today.sellEma + emaValue

        saveDB()
        saveStats()
        addTransaction({type = "sell", player = msg.name, item = msg.item, qty = qty, coin = coinValue, ema = emaValue})
        addLog("SELL", string.format("%s продал '%s' x%d | +%.2f COIN +%.2f EMA", msg.name, tostring(msg.item or "?"), qty, coinValue, emaValue))
        redrawIfUseful()
        return
    end

    if msg.op == "buy" then
        if shopPaused then
            sendMessage(from, {op = "error", message = "Магазин на паузе"})
            return
        end
        if not validateSession(msg.name, msg.token) then return end
        local player = players[msg.name]
        if not player or player.banned then return end

        local valueCoin = tonumber(msg.value_coin)
        if valueCoin == nil then valueCoin = tonumber(msg.value) or 0 end
        local valueEma = tonumber(msg.value_ema) or 0
        local qty = tonumber(msg.qty) or 0

        player.balance = math.max(0, (tonumber(player.balance) or 0) - valueCoin)
        player.emaBalance = math.max(0, (tonumber(player.emaBalance) or 0) - valueEma)
        player.transactions = (tonumber(player.transactions) or 0) + 1
        sessions[msg.name].lastAction = os.time()

        ensureStats()
        globalStats.totalBuys = globalStats.totalBuys + 1
        globalStats.totalBuyItems = globalStats.totalBuyItems + qty
        globalStats.totalBuyCoin = globalStats.totalBuyCoin + valueCoin
        globalStats.totalBuyEma = globalStats.totalBuyEma + valueEma
        globalStats.today.buys = globalStats.today.buys + 1
        globalStats.today.buyItems = globalStats.today.buyItems + qty
        globalStats.today.buyCoin = globalStats.today.buyCoin + valueCoin
        globalStats.today.buyEma = globalStats.today.buyEma + valueEma

        saveDB()
        saveStats()
        addTransaction({type = "buy", player = msg.name, item = msg.item, qty = qty, coin = valueCoin, ema = valueEma})
        addLog("BUY", string.format("%s купил '%s' x%d | -%.2f COIN -%.2f EMA", msg.name, tostring(msg.item or "?"), qty, valueCoin, valueEma))
        redrawIfUseful()
        return
    end

    if msg.op == "report" then
        if not validateSession(msg.name, msg.token) then return end
        ensureStats()
        globalStats.totalReports = globalStats.totalReports + 1
        globalStats.today.reports = globalStats.today.reports + 1
        saveStats()
        table.insert(reports, 1, {
            time = msg.time or getRealDateTimeString(),
            name = msg.name or "?",
            text = msg.text or "",
        })
        while #reports > 500 do table.remove(reports) end
        saveReports()
        addLog("REPORT", "Новый репорт от " .. tostring(msg.name))
        redrawIfUseful()
        return
    end

    if msg.op == "agree" then
        if not validateSession(msg.name, msg.token) then
            sendMessage(from, {op = "agree", error = true, message = "Токен устарел"})
            return
        end
        local player = players[msg.name]
        if player then
            player.agreed = true
            saveDB()
            sessions[msg.name].lastAction = os.time()
            sendMessage(from, {op = "agree", success = true, agreed = true})
        else
            sendMessage(from, {op = "agree", error = true, message = "Игрок не найден"})
        end
        return
    end

    if msg.op == "get_feedbacks" then
        if not validateSession(msg.name, msg.token) then
            sendMessage(from, {op = "feedbacks_list", error = "Токен устарел"})
            return
        end
        local player = players[msg.name]
        sendMessage(from, {
            op = "feedbacks_list",
            feedbacks = feedbacks,
            hasFeedback = player and player.hasFeedback or false,
        })
        return
    end

    if msg.op == "add_feedback" then
        if not validateSession(msg.name, msg.token) then
            sendMessage(from, {op = "add_feedback_response", success = false, error = "Токен устарел"})
            return
        end
        local player = players[msg.name]
        if not player then
            sendMessage(from, {op = "add_feedback_response", success = false, error = "Игрок не найден"})
            return
        end
        if player.hasFeedback then
            sendMessage(from, {op = "add_feedback_response", success = false, error = "Вы уже оставляли отзыв"})
            return
        end
        table.insert(feedbacks, 1, {name = msg.name, text = msg.text or "", time = msg.time or getRealDateTimeString()})
        while #feedbacks > 500 do table.remove(feedbacks) end
        saveFeedbacks()
        player.hasFeedback = true
        saveDB()
        sendMessage(from, {op = "add_feedback_response", success = true})
        addLog("FEEDBACK", "Новый отзыв от " .. tostring(msg.name))
        redrawIfUseful()
        return
    end

    if msg.op == "add_buy_item_response" then
        if pendingAddItem then
            if msg.success then
                for addr in pairs(markets) do
                    sendMessage(addr, {op = "reload_buy_items"})
                end
                addItemMessage = "Предмет добавлен. Каталог терминалов обновляется."
                addItemMessageColor = C.green
                addLog("ADMIN", "Добавлен предмет в каталог: " .. tostring(pendingAddItem.item))
            else
                addItemMessage = "Ошибка добавления предмета: " .. tostring(msg.error or "неизвестно")
                addItemMessageColor = C.red
            end
            pendingAddItem = nil
            if currentScreen == "add_item" then redraw() end
        end
        return
    end
end

-- ============================================================
-- БЕЗОПАСНЫЙ EVENT.PULL
-- Ctrl+C / interrupt не завершает сервер.
-- ============================================================
local function safeEventPull(timeout)
    local result = {pcall(event.pull, timeout)}
    if not result[1] then return nil end
    table.remove(result, 1)
    return table.unpack(result)
end

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
            local player = a6 -- touch: 6-й аргумент = имя игрока
            handleTouch(x, y, player)

        elseif etype == "modem_message" then
            local from = a3
            local raw = a6
            handleModemMessage(from, raw)

        elseif etype == "screen_resized" then
            redraw()
        end

        local clock = getRealTimeString()
        if currentScreen == "dashboard" and clock ~= lastClock then
            lastClock = clock
            drawDashboard()
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
