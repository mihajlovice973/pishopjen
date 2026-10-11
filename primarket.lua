-- ============================================================
-- PRIMARKET.LUA v2.2 — С ТОП ИГРОКОВ
-- Адаптивный интерфейс 120x40, тёмно-фиолетовая тема
-- ============================================================

local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local keyboard = require("keyboard")
local computer = require("computer")
local fs = require("filesystem")

-- Временная зона МСК (UTC+3)
local TIMEZONE_OFFSET = 3 * 3600

-- Игнорируем прерывания чтобы магазин не закрывался случайно
event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)

-- Временная файловая система для получения реального времени
local tmpfs = component.proxy(computer.tmpAddress())

-- Получение реального timestamp сервера
local function getRealTimestamp()
    local handle = tmpfs.open("/time", "w")
    tmpfs.write(handle, "time")
    tmpfs.close(handle)
    return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
end

local function getRealTimeString()
    return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end

local function getRealTimeHM()
    return os.date("%H:%M:%S", getRealTimestamp())
end

-- Безопасный event.pull
local function safeEventPull(timeout)
    local result = {pcall(event.pull, timeout)}
    if not result[1] then
        return {}
    end
    table.remove(result, 1)
    return result
end

local serverAddress = "a7096c74-1bc4-43a6-8dff-2d4394d22c0e"
local ACCESS_PASSWORD = "yVGF7wT"

-- ============================================================
-- ЦВЕТОВАЯ СХЕМА
-- ============================================================
local colors = {
    bg_main = 0x0E0E14,
    bg_secondary = 0x16161F,
    bg_tertiary = 0x1E1E2A,
    bg_button = 0x2A2A3A,
    bg_button_hover = 0x3A3A4E,
    bg_button_active = 0x1A1A28,
    
    accent_main = 0x7B2CBF,
    accent_light = 0x9D4EDD,
    accent_dark = 0x5A189A,
    accent_glow = 0xC77DFF,
    
    border_main = 0x4A4A5A,
    border_accent = 0x6A0DAD,
    
    text_main = 0xB8B8C8,
    text_bright = 0xE8E8F0,
    text_dim = 0x6A6A7A,
    text_muted = 0x4A4A5A,
    
    success = 0x00D9A3,
    success_dark = 0x00A878,
    error = 0xFF4D6D,
    error_dark = 0xC9184A,
    warning = 0xFFB700,
    warning_dark = 0xE09F00,
    inactive = 0x4A4A5A,
    
    tomato = 0xFF6B6B,
    white = 0xFFFFFF,
    black = 0x000000,
    gold = 0xFFD700,
    silver = 0xC0C0C0,
    bronze = 0xCD7F32,
    
    -- Медали для топа
    medal_1 = 0xFFD700,  -- Золото
    medal_2 = 0xC0C0C0,  -- Серебро
    medal_3 = 0xCD7F32,  -- Бронза
}

-- ============================================================
-- АДАПТИВНОЕ РАЗРЕШЕНИЕ
-- ============================================================
local maxW, maxH = gpu.maxResolution()
SCREEN_W = math.min(120, maxW)
SCREEN_H = math.min(40, maxH)

-- ============================================================
-- СИСТЕМА ЛОГИРОВАНИЯ
-- ============================================================
local LOG_FILE = "/home/shop_debug.log"
local logEnabled = true

local function megaLog(message, data)
    if not logEnabled then return end
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logEntry = "[" .. timestamp .. "] " .. message
    if data then
        if type(data) == "table" then
            local ok, jsonData = pcall(serialization.serialize, data)
            if ok then
                logEntry = logEntry .. " | DATA: " .. jsonData
            else
                logEntry = logEntry .. " | DATA: " .. tostring(data)
            end
        else
            logEntry = logEntry .. " | DATA: " .. tostring(data)
        end
    end
    logEntry = logEntry .. "\n"
    
    local file, err = io.open(LOG_FILE, "a")
    if file then
        file:write(logEntry)
        file:close()
    end
end

-- Очистка лога при старте
local file = io.open(LOG_FILE, "w")
if file then
    file:write("=== LOG STARTED AT " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    file:close()
end

megaLog("🚀 СКРИПТ ЗАПУЩЕН")
megaLog("📋 ВЕРСИЯ: PRIMARKET v2.2")

-- ============================================================
-- БАЗОВЫЕ ФУНКЦИИ ОТРИСОВКИ
-- ============================================================

local function clear()
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
end

local function drawCenteredText(y, text, color)
    gpu.setForeground(color or colors.text_main)
    local x = math.floor((SCREEN_W - unicode.len(text)) / 2) + 1
    gpu.set(x, y, text)
end

local function drawButton(btn)
    gpu.setBackground(btn.bg or colors.bg_button)
    gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
    if btn.ys > 1 then
        gpu.setBackground(colors.bg_button_active)
        gpu.fill(btn.x, btn.y + btn.ys - 1, btn.xs, 1, " ")
    end
    gpu.setForeground(btn.fg or colors.text_bright)
    local textX = btn.x + math.floor((btn.xs - unicode.len(btn.text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    gpu.set(textX, textY, btn.text)
    gpu.setBackground(colors.bg_main)
end

local function drawFlexButton(btn)
    gpu.setBackground(btn.bg or colors.bg_button)
    gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
    gpu.setForeground(btn.fg or colors.text_bright)
    local textX = btn.x + math.floor((btn.xs - unicode.len(btn.text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    gpu.set(textX, textY, btn.text)
    gpu.setBackground(colors.bg_main)
end

local function safeDoFile(path)
    if not fs.exists(path) then
        print("Файл не найден, создаём: " .. path)
        return {}
    end
    local ok, result = pcall(dofile, path)
    if not ok then
        print("Ошибка загрузки файла " .. path .. ": " .. tostring(result))
        return {}
    end
    return result
end

-- ============================================================
-- УТИЛИТЫ
-- ============================================================

local CYRILLIC_LOWER = {
    ["А"]="а", ["Б"]="б", ["В"]="в", ["Г"]="г", ["Д"]="д", ["Е"]="е", ["Ё"]="ё",
    ["Ж"]="ж", ["З"]="з", ["И"]="и", ["Й"]="й", ["К"]="к", ["Л"]="л", ["М"]="м",
    ["Н"]="н", ["О"]="о", ["П"]="п", ["Р"]="р", ["С"]="с", ["Т"]="т", ["У"]="у",
    ["Ф"]="ф", ["Х"]="х", ["Ц"]="ц", ["Ч"]="ч", ["Ш"]="ш", ["Щ"]="щ", ["Ъ"]="ъ",
    ["Ы"]="ы", ["Ь"]="ь", ["Э"]="э", ["Ю"]="ю", ["Я"]="я"
}

local function normalizeSearchText(value)
    local s = tostring(value or "")
    s = string.lower(s)
    for upper, lower in pairs(CYRILLIC_LOWER) do
        s = s:gsub(upper, lower)
    end
    s = s:gsub("ё", "е")
    return s
end

local function sortableName(name)
    if not name then return "" end
    local lower = normalizeSearchText(name)
    local result = lower:gsub("(%d+)", function(d)
        return string.format("%08d", tonumber(d))
    end)
    return result
end

-- ============================================================
-- СИСТЕМА ОТЗЫВОВ С РЕЙТИНГОМ
-- ============================================================
local feedbacks = {}
local feedbacksPage = 1
local feedbacksTotalPages = 1
local feedbackInput = ""
local feedbackEditMode = false
local feedbackRating = 0
local playerHasFeedback = false

-- ============================================================
-- СИСТЕМА ТОП ИГРОКОВ
-- ============================================================
local STATS_FILE = "/home/player_stats.json"
local playerStats = {}  -- {name = {visits, totalSpent, totalEarned, purchases, sells, balance}}
local currentTopCategory = "balance"  -- balance, visits, spent, earned, purchases, sells
local topPage = 1
local topPerPage = 10

-- Загрузка статистики из файла
local function loadPlayerStats()
    if fs.exists(STATS_FILE) then
        local f = io.open(STATS_FILE, "r")
        if f then
            local content = f:read("*a")
            f:close()
            local ok, data = pcall(serialization.unserialize, content)
            if ok and type(data) == "table" then
                playerStats = data
                megaLog(" Статистика загружена: " .. #playerStats .. " игроков")
                return
            end
        end
    end
    playerStats = {}
    megaLog("📊 Статистика инициализирована")
end

-- Сохранение статистики
local function savePlayerStats()
    local f = io.open(STATS_FILE, "w")
    if f then
        f:write(serialization.serialize(playerStats))
        f:close()
    end
end

-- Обновление статистики игрока
local function updatePlayerStat(name, field, value)
    if not playerStats[name] then
        playerStats[name] = {
            visits = 0,
            totalSpent = 0,
            totalEarned = 0,
            purchases = 0,
            sells = 0,
            balance = 0,
            lastVisit = ""
        }
    end
    if field == "visits" then
        playerStats[name].visits = (playerStats[name].visits or 0) + 1
        playerStats[name].lastVisit = getRealTimeString()
    elseif field == "spent" then
        playerStats[name].totalSpent = (playerStats[name].totalSpent or 0) + value
    elseif field == "earned" then
        playerStats[name].totalEarned = (playerStats[name].totalEarned or 0) + value
    elseif field == "purchases" then
        playerStats[name].purchases = (playerStats[name].purchases or 0) + 1
    elseif field == "sells" then
        playerStats[name].sells = (playerStats[name].sells or 0) + 1
    elseif field == "balance" then
        playerStats[name].balance = value
    end
    savePlayerStats()
end

-- Получение отсортированного топа
local function getTopPlayers(category, limit)
    limit = limit or 10
    local sorted = {}
    for name, stats in pairs(playerStats) do
        table.insert(sorted, {
            name = name,
            value = stats[category] or 0
        })
    end
    table.sort(sorted, function(a, b)
        return a.value > b.value
    end)
    return sorted
end

-- Отрисовка рамки для popup
local function drawPopupBorder(x, y, w, h, color)
    gpu.setForeground(color or colors.border_accent)
    gpu.fill(x, y, w, 1, "─")
    gpu.fill(x, y + h - 1, w, 1, "─")
    for i = 1, h - 2 do
        gpu.set(x, y + i, "│")
        gpu.set(x + w - 1, y + i, "│")
    end
    gpu.set(x, y, "┌")
    gpu.set(x + w - 1, y, "┐")
    gpu.set(x, y + h - 1, "└")
    gpu.set(x + w - 1, y + h - 1, "┘")
end

-- Отрисовка рамки экрана (только тёмно-фиолетовая)
local function drawScreenBorder()
    local left = 1
    local right = SCREEN_W
    local top = 1
    local bottom = SCREEN_H - 1
    gpu.setForeground(colors.border_accent)
    gpu.fill(left, top, right - left + 1, 1, "═")
    gpu.fill(left, bottom, right - left + 1, 1, "═")
    for y = top + 1, bottom - 1 do
        gpu.set(left, y, "║")
        gpu.set(right, y, "║")
    end
    gpu.set(left, top, "╔")
    gpu.set(right, top, "╗")
    gpu.set(left, bottom, "╚")
    gpu.set(right, bottom, "╝")
end

-- ============================================================
-- ЗАГРУЗКА ДАННЫХ МАГАЗИНА
-- ============================================================
local shopData = safeDoFile("/home/shop_items.lua")
local sellItems = shopData.sellItems
local vanillaItems = shopData.vanillaItems or {}
local buyItemsData = safeDoFile("/home/buy_items.lua")
local buyItemMap = {}
for _, item in ipairs(buyItemsData) do
    local dmg = item.damage or 0
    local nbt = item.nbt_hash or item.nbtHash or item.nbt
    local key = item.internalName .. ":" .. dmg .. "|nbt=" .. tostring(nbt or "")
    buyItemMap[key] = item
end

local drawAgreementScreen = safeDoFile("/home/agreement.lua")
local modem = component.modem

-- Загрузка статистики при старте
loadPlayerStats()

-- ============================================================
-- СИСТЕМА ПРИСУТСТВИЯ ИГРОКА НА PIM
-- ============================================================

local function getPimAddr()
    for addr in component.list("pim") do
        return addr
    end
    return nil
end

local PimPresence = {
    missCount = 0,
    lastPositive = 0,
    missLimit = 10,
    graceSeconds = 4.0
}

local function isPlayerPhysicallyOnPim()
    local pimAddr = getPimAddr()
    if not pimAddr then
        return nil
    end
    local ok, size = pcall(component.invoke, pimAddr, "getInventorySize")
    if not ok then
        return nil
    end
    local numericSize = tonumber(size)
    local now = computer.uptime()
    if numericSize == nil then
        return nil
    end
    if numericSize > 0 then
        PimPresence.missCount = 0
        PimPresence.lastPositive = now
        return true
    end
    PimPresence.missCount = (tonumber(PimPresence.missCount) or 0) + 1
    local lastPositive = tonumber(PimPresence.lastPositive) or 0
    local graceSeconds = tonumber(PimPresence.graceSeconds) or 4.0
    local missLimit = tonumber(PimPresence.missLimit) or 10
    if lastPositive > 0 and now - lastPositive < graceSeconds then
        return nil
    end
    if PimPresence.missCount < missLimit then
        return nil
    end
    return false
end

local PUSH_DIRECTION = "down"
local PULL_DIRECTION = "up"

local function normalizeName(name)
    if not name then return "" end
    local lastColon = name:match(".*:([^:]+)$")
    return lastColon or name
end

local function namesMatch(name1, name2)
    if not name1 or not name2 then return false end
    if name1 == name2 then return true end
    local short1 = normalizeName(name1)
    local short2 = normalizeName(name2)
    return short1 == short2
end

-- ============================================================
-- СИСТЕМА СЕЛЕКТОРА
-- ============================================================
local selector = nil
for addr in component.list("openperipheral_selector") do
    selector = component.proxy(addr)
    break
end
if not selector then
    for addr in component.list("item_selector") do
        selector = component.proxy(addr)
        break
    end
end

local function safeSelectorSetSlot(slot, stack)
    if not selector then return false end
    local ok, result = pcall(function()
        return selector.setSlot(slot, stack)
    end)
    return ok, result
end

modem.open(0xffef)
modem.open(0xfffe)

-- ============================================================
-- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ СОСТОЯНИЯ
-- ============================================================
local currentPlayer, currentToken = nil, nil
local coinBalance = 0.0
local emaBalance = 0.0
local playerTransactions = 0
local playerRegDate = ""
local playerAgreed = false
local currentScreen = "welcome"
local closePimSession
local authStartTime = 0
local authLastSendTime = 0
local AUTH_RETRY_INTERVAL = 1.0
local AUTH_NO_RESPONSE_NOTICE = 8.0
local authTechWork = false
local accountRequestTime = 0
local ACCOUNT_TIMEOUT = 3
local alreadyAuthorized = false

local function trimPlayerName(name)
    if type(name) ~= "string" then return "" end
    return name:match("^%s*(.-)%s*$") or name
end

local function samePlayerName(a, b)
    a = trimPlayerName(a)
    b = trimPlayerName(b)
    if a == "" or b == "" then return false end
    return unicode.lower(a) == unicode.lower(b)
end

-- ============================================================
-- СИСТЕМА ОЧЕРЕДИ СОБЫТИЙ
-- ============================================================
local deferredEvents = {}

local function deferShopEvent(ev)
    if type(ev) == "table" and ev[1] then
        deferredEvents[#deferredEvents + 1] = ev
    end
end

local function nextShopEvent(timeout)
    if #deferredEvents > 0 then
        return table.remove(deferredEvents, 1)
    end
    return safeEventPull(timeout)
end

local function extractEventPlayerName(ev)
    if type(ev) ~= "table" then return nil end
    for i = 2, math.min(#ev, 7) do
        local value = ev[i]
        if type(value) == "string" and value ~= "" and value ~= "null" then
            local looksLikeAddress = value:match("^[0-9a-fA-F%-]+$") and #value >= 30
            if not looksLikeAddress and value:match("^[%w_]+$") then
                return value
            end
        end
    end
    return nil
end

local function isPimControlEvent(name)
    return name == "player_off" or name == "pim_player_leave"
    or name == "player_on" or name == "pim_player_enter" or name == "pim"
end

local function processPimControlEvent(ev, expectedPlayer)
    local name = ev and ev[1]
    if not name then return true end
    if name == "player_off" or name == "pim_player_leave" then
        if closePimSession then closePimSession() end
        return false
    end
    if name == "player_on" or name == "pim_player_enter" or name == "pim" then
        local entered = extractEventPlayerName(ev)
        if expectedPlayer and entered and not samePlayerName(entered, expectedPlayer) then
            if closePimSession then closePimSession() end
            deferShopEvent(ev)
            return false
        end
        if name == "pim" and isPlayerPhysicallyOnPim() == false then
            if closePimSession then closePimSession() end
            return false
        end
    end
    return true
end

local function checkPimSessionAlive(expectedPlayer)
    for _ = 1, 64 do
        local ev = safeEventPull(0)
        if not ev[1] then break end
        if isPimControlEvent(ev[1]) then
            if not processPimControlEvent(ev, expectedPlayer) then
                return false
            end
        else
            deferShopEvent(ev)
        end
    end
    if isPlayerPhysicallyOnPim() == false then
        if closePimSession then closePimSession() end
        return false
    end
    if expectedPlayer and currentPlayer and not samePlayerName(currentPlayer, expectedPlayer) then
        return false
    end
    return currentPlayer ~= nil
end

local function pimAwareSleep(seconds, expectedPlayer)
    local deadline = computer.uptime() + math.max(0, tonumber(seconds) or 0)
    while computer.uptime() < deadline do
        local wait = math.min(0.05, math.max(0, deadline - computer.uptime()))
        local ev = safeEventPull(wait)
        if ev[1] then
            if isPimControlEvent(ev[1]) then
                if not processPimControlEvent(ev, expectedPlayer) then
                    return false
                end
            else
                deferShopEvent(ev)
            end
        end
        if isPlayerPhysicallyOnPim() == false then
            if closePimSession then closePimSession() end
            return false
        end
    end
    return checkPimSessionAlive(expectedPlayer)
end

local function isPimOwner(playerName)
    return currentPlayer ~= nil and samePlayerName(playerName, currentPlayer)
end

local function sendEnterRequest()
    if not currentPlayer or currentPlayer == "" then return false end
    local sent = modem.send(serverAddress, 0xffef, serialization.serialize({
        op = "enter",
        name = currentPlayer
    }))
    authLastSendTime = computer.uptime()
    return sent
end

-- ============================================================
-- ПЕРЕМЕННЫЕ МАГАЗИНА
-- ============================================================
local shopItems = {}
local shopSearch = ""
local searchActive = false
local searchInput = ""
local currentShopMode = "buy"
local stockFilterMode = "available"
local stockFilterOpen = false
local drawBuyStatic
local drawBuyItemsList
local drawBuyButtons
local blacklist = {
    ["customnpcs:npcMoney"] = true,
}

local listScroll = 1
local visibleRows = math.min(25, SCREEN_H - 10)
local selectedIndex = 0
local hoveredIndex = 0
local filteredItems = {}
local selectedItem = nil
local horizontalScroll = 1
local maxItemWidth = 0
local purchaseQuantity = 1
local purchaseItem = nil
local sellConfirmItem = nil
local foundAmount = 0
local showSellPopup = false
local showPartialPopup = false
local partialExtracted = 0
local partialRequested = 0
local partialRefundCoin = 0
local partialRefundEma = 0
local partialItem = nil
local showInsufficientPopup = false
local insufficientBalanceCoin = 0
local insufficientBalanceEma = 0
local showInventoryFullPopup = false
local reportInput = ""
local lastReportTime = nil
local showShopDenied = false
local tempMessage = ""
local tempMessageTimer = nil

local function updateSelectorDisplay(item)
    if not selector then return end
    if not item then
        safeSelectorSetSlot(0, nil)
        safeSelectorSetSlot(1, nil)
        return
    end
    local raw = item.internalName or item.name or item.displayName
    if not raw then return end
    local id = raw
    if not id:find(":") then
        id = "minecraft:" .. id
    end
    local dmg = item.damage or 0
    local stack = { id = id, dmg = dmg }
    safeSelectorSetSlot(0, stack)
    safeSelectorSetSlot(1, stack)
end

gpu.setResolution(SCREEN_W, SCREEN_H)
gpu.setBackground(colors.bg_main)

-- ============================================================
-- ОТРИСОВКА ЗАГОЛОВКА
-- ============================================================
local function drawBigTitle()
    gpu.setForeground(colors.accent_light)
    local titleLines = {
        "██████╗ ██╗    ███████╗██╗  ██╗ ██████╗ ██████╗ ",
        "██╔══██╗██║    ██╔════╝██║  ██║██╔═══██╗██══██╗",
        "██████╔╝██║    ███████╗███████║██║   ██║██████╔╝",
        "██╔═══╝ ██║    ╚════██║██╔══██║██║   ██║██╔═══╝ ",
        "██║     ██║    ███████║██║  ██║╚██████╔╝██║     ",
        "╚═╝     ╚═╝    ╚══════╝═╝  ╚═╝ ╚═════╝ ╚═╝     "
    }
    local startY = math.floor(SCREEN_H * 0.2)
    for i, line in ipairs(titleLines) do
        local lineWidth = unicode.len(line)
        local x = math.floor((SCREEN_W - lineWidth) / 2) + 1
        gpu.set(x, startY + i - 1, line)
    end
    gpu.setForeground(colors.border_accent)
    local decoY = startY + #titleLines + 1
    local decoText = "═" .. string.rep("═", math.min(60, SCREEN_W - 4)) .. "═"
    local decoX = math.floor((SCREEN_W - unicode.len(decoText)) / 2) + 1
    gpu.set(decoX, decoY, decoText)
end

local function drawTempMessage()
    if tempMessage ~= "" then
        gpu.setBackground(colors.bg_main)
        gpu.fill(1, SCREEN_H, SCREEN_W, 1, " ")
        gpu.setForeground(colors.success)
        local x = math.floor((SCREEN_W - unicode.len(tempMessage)) / 2) + 1
        gpu.set(x, SCREEN_H, tempMessage)
    else
        gpu.setBackground(colors.bg_main)
        gpu.fill(1, SCREEN_H, SCREEN_W, 1, " ")
    end
end

local function showTempMessage(msg, duration)
    tempMessage = msg
    if tempMessageTimer then
        event.cancel(tempMessageTimer)
    end
    tempMessageTimer = event.timer(duration, function()
        tempMessage = ""
        tempMessageTimer = nil
        if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
            drawBuyStatic()
            drawBuyItemsList()
            drawBuyButtons()
        elseif currentScreen == "menu" then
            drawMainMenu()
        elseif currentScreen == "shop" then
            drawShopMenu()
        elseif currentScreen == "account" then
            drawAccount({balance=coinBalance, emaBalance=emaBalance, transactions=playerTransactions, regDate=playerRegDate, agreed=playerAgreed})
        elseif currentScreen == "feedbacks" then
            drawFeedbacksList()
        elseif currentScreen == "top" then
            drawTopScreen()
        else
            drawTempMessage()
        end
    end)
    drawTempMessage()
end

local function loadFeedbacksFromServer()
    if not currentToken then return end
    modem.send(serverAddress, 0xffef, serialization.serialize({
        op = "get_feedbacks",
        name = currentPlayer,
        token = currentToken
    }))
end

-- ============================================================
-- ЭКРАН ТОП ИГРОКОВ
-- ============================================================
local function drawTopScreen()
    clear()
    drawScreenBorder()
    
    -- Заголовок
    local title = " ═ ТОП ИГРОКОВ ══ "
    local titleX = math.floor((SCREEN_W - unicode.len(title)) / 2) + 1
    gpu.setForeground(colors.accent_light)
    gpu.set(titleX, 3, title)
    
    -- Категории (кнопки переключения)
    local categories = {
        {key = "balance", text = "💰 Баланс", x = 5},
        {key = "visits", text = "👁 Посещения", x = 25},
        {key = "spent", text = "💸 Траты", x = 45},
        {key = "earned", text = "💵 Заработок", x = 62},
        {key = "purchases", text = "🛒 Покупки", x = 82},
        {key = "sells", text = "💰 Продажи", x = 100},
    }
    
    -- Адаптация позиций для 120 символов
    local catY = 5
    local catSpacing = math.floor((SCREEN_W - 20) / #categories)
    for i, cat in ipairs(categories) do
        cat.x = 5 + (i - 1) * catSpacing
        local isActive = (currentTopCategory == cat.key)
        local bg = isActive and colors.accent_dark or colors.bg_button
        local fg = isActive and colors.text_bright or colors.text_main
        gpu.setBackground(bg)
        gpu.fill(cat.x, catY, catSpacing - 2, 1, " ")
        gpu.setForeground(fg)
        local textX = cat.x + math.floor((catSpacing - 2 - unicode.len(cat.text)) / 2)
        gpu.set(textX, catY, cat.text)
        gpu.setBackground(colors.bg_main)
    end
    
    -- Получение топа
    local topList = getTopPlayers(currentTopCategory, topPerPage * 3)
    local startIndex = (topPage - 1) * topPerPage + 1
    local endIndex = math.min(startIndex + topPerPage - 1, #topList)
    
    -- Заголовки таблицы
    local tableY = 8
    gpu.setBackground(colors.bg_tertiary)
    gpu.fill(5, tableY, SCREEN_W - 10, 1, " ")
    gpu.setForeground(colors.text_bright)
    gpu.set(7, tableY, "№")
    gpu.set(12, tableY, "Игрок")
    gpu.set(50, tableY, "Значение")
    gpu.setBackground(colors.bg_main)
    
    -- Строки топа
    local rowY = tableY + 1
    for i = startIndex, endIndex do
        local entry = topList[i]
        if entry then
            local rank = i
            local medal = ""
            local nameColor = colors.text_main
            
            if rank == 1 then
                medal = "🥇"
                nameColor = colors.medal_1
            elseif rank == 2 then
                medal = "🥈"
                nameColor = colors.medal_2
            elseif rank == 3 then
                medal = "🥉"
                nameColor = colors.medal_3
            else
                medal = string.format("%2d.", rank)
            end
            
            -- Подсветка текущего игрока
            local isCurrentPlayer = (entry.name == currentPlayer)
            if isCurrentPlayer then
                gpu.setBackground(colors.accent_dark)
            elseif rank % 2 == 0 then
                gpu.setBackground(colors.bg_secondary)
            else
                gpu.setBackground(colors.bg_main)
            end
            gpu.fill(5, rowY, SCREEN_W - 10, 1, " ")
            
            gpu.setForeground(colors.text_dim)
            gpu.set(7, rowY, medal)
            
            gpu.setForeground(nameColor)
            local displayName = entry.name
            if unicode.len(displayName) > 15 then
                displayName = unicode.sub(displayName, 1, 15)
            end
            gpu.set(12, rowY, displayName)
            
            -- Форматирование значения
            local valueStr = ""
            if currentTopCategory == "balance" or currentTopCategory == "spent" or currentTopCategory == "earned" then
                valueStr = string.format("%.2f", entry.value)
            else
                valueStr = tostring(entry.value)
            end
            gpu.setForeground(colors.accent_light)
            gpu.set(50, rowY, valueStr)
            
            gpu.setBackground(colors.bg_main)
            rowY = rowY + 1
        end
    end
    
    -- Пагинация
    local totalPages = math.max(1, math.ceil(#topList / topPerPage))
    local pageInfo = "Страница " .. topPage .. " из " .. totalPages .. " | Всего: " .. #topList
    drawCenteredText(SCREEN_H - 3, pageInfo, colors.text_dim)
    
    -- Кнопки навигации
    local prevBtn = {x = math.floor(SCREEN_W / 2) - 20, y = SCREEN_H - 1, xs = 8, ys = 1, text = "[ < ]", bg = colors.bg_button, fg = colors.accent_light}
    local nextBtn = {x = math.floor(SCREEN_W / 2) + 12, y = SCREEN_H - 1, xs = 8, ys = 1, text = "[ > ]", bg = colors.bg_button, fg = colors.accent_light}
    local backBtn = {x = math.floor(SCREEN_W / 2) - 6, y = SCREEN_H - 1, xs = 12, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_light}
    
    if topPage > 1 then
        drawFlexButton(prevBtn)
    end
    drawFlexButton(backBtn)
    if topPage < totalPages then
        drawFlexButton(nextBtn)
    end
    
    drawTempMessage()
end

-- Обработка клика по категориям топа
local function handleTopCategoryClick(x, y)
    local categories = {
        {key = "balance", x = 5},
        {key = "visits", x = 25},
        {key = "spent", x = 45},
        {key = "earned", x = 62},
        {key = "purchases", x = 82},
        {key = "sells", x = 100},
    }
    local catSpacing = math.floor((SCREEN_W - 20) / #categories)
    for i, cat in ipairs(categories) do
        cat.x = 5 + (i - 1) * catSpacing
        if x >= cat.x and x < cat.x + catSpacing - 2 and y == 5 then
            currentTopCategory = cat.key
            topPage = 1
            drawTopScreen()
            return true
        end
    end
    return false
end

-- ============================================================
-- ОТЗЫВЫ
-- ============================================================
local function drawFeedbacksList()
    clear()
    drawScreenBorder()
    
    local title = " ═ ОТЗЫВЫ ═══ "
    local titleX = math.floor((SCREEN_W - unicode.len(title)) / 2) + 1
    gpu.setForeground(colors.accent_light)
    gpu.set(titleX, 3, title)
    
    -- Подсчёт среднего рейтинга
    local totalRating = 0
    local ratingCount = 0
    for _, fb in ipairs(feedbacks) do
        if fb.rating and fb.rating > 0 then
            totalRating = totalRating + fb.rating
            ratingCount = ratingCount + 1
        end
    end
    local avgRating = 0
    if ratingCount > 0 then
        avgRating = totalRating / ratingCount
    end
    
    local ratingText = "⭐ Рейтинг: " .. string.format("%.1f", avgRating) .. " (" .. ratingCount .. " оценок)"
    drawCenteredText(5, ratingText, colors.accent_main)
    
    if #feedbacks == 0 then
        drawCenteredText(12, "Пока нет ни одного отзыва.", colors.text_main)
        drawCenteredText(14, "Будьте первым, кто оставит отзыв!", colors.accent_light)
        if not playerHasFeedback then
            drawCenteredText(16, "Нажмите [ДОБАВИТЬ] чтобы оставить отзыв", colors.text_dim)
        end
    else
        local startIdx = (feedbacksPage - 1) * 3 + 1
        local endIdx = math.min(startIdx + 2, #feedbacks)
        local y = 7
        for i = startIdx, endIdx do
            local fb = feedbacks[i]
            if fb then
                gpu.setForeground(colors.border_accent)
                gpu.fill(8, y, SCREEN_W - 16, 5, " ")
                gpu.setBackground(colors.bg_tertiary)
                gpu.fill(9, y + 1, SCREEN_W - 18, 3, " ")
                
                gpu.setForeground(colors.accent_light)
                gpu.set(10, y + 1, "👤 " .. fb.name)
                gpu.setForeground(colors.text_dim)
                local timeStr = fb.time or ""
                gpu.set(10 + unicode.len(fb.name) + 3, y + 1, timeStr)
                
                local rating = fb.rating or 0
                local stars = ""
                for s = 1, 5 do
                    if s <= rating then
                        stars = stars .. "★"
                    else
                        stars = stars .. "☆"
                    end
                end
                gpu.setForeground(colors.gold)
                gpu.set(10 + unicode.len(fb.name) + 3 + unicode.len(timeStr) + 2, y + 1, stars)
                
                gpu.setForeground(colors.text_bright)
                local shortText = unicode.sub(fb.text, 1, SCREEN_W - 24)
                gpu.set(10, y + 2, shortText)
                y = y + 6
            end
        end
        feedbacksTotalPages = math.max(1, math.ceil(#feedbacks / 3))
        local pageInfo = "Страница " .. feedbacksPage .. " из " .. feedbacksTotalPages
        drawCenteredText(SCREEN_H - 4, pageInfo, colors.text_dim)
    end
    
    local backBtn = {x = 5, y = SCREEN_H - 1, xs = 11, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_light}
    local addBtn = {x = math.floor(SCREEN_W / 2) - 7, y = SCREEN_H - 1, xs = 14, ys = 1, text = "[ ДОБАВИТЬ ]", bg = colors.bg_button, fg = colors.success}
    local prevBtn = {x = SCREEN_W - 30, y = SCREEN_H - 1, xs = 7, ys = 1, text = "[ < ]", bg = colors.bg_button, fg = colors.accent_light}
    local nextBtn = {x = SCREEN_W - 20, y = SCREEN_H - 1, xs = 7, ys = 1, text = "[ > ]", bg = colors.bg_button, fg = colors.accent_light}
    if not playerHasFeedback then
        drawFlexButton(addBtn)
    end
    drawFlexButton(backBtn)
    if #feedbacks > 3 then
        drawFlexButton(prevBtn)
        drawFlexButton(nextBtn)
    end
    drawTempMessage()
end

local function drawFeedbackInputScreen()
    if playerHasFeedback then
        showTempMessage("Вы уже оставляли отзыв!", 2)
        goBackToMenu()
        return
    end
    currentScreen = "feedback_input"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "ОСТАВИТЬ ОТЗЫВ", colors.accent_light)
    gpu.setForeground(colors.text_main)
    drawCenteredText(8, "Ваше имя: " .. currentPlayer, colors.accent_light)
    
    drawCenteredText(10, "Оцените магазин:", colors.text_main)
    local starY = 12
    local starX = math.floor(SCREEN_W / 2) - 10
    for i = 1, 5 do
        local isActive = (i <= feedbackRating)
        local text = isActive and "★" or "☆"
        local color = isActive and colors.gold or colors.inactive
        gpu.setBackground(colors.bg_main)
        gpu.setForeground(color)
        gpu.set(starX + (i - 1) * 3, starY, text)
    end
    
    drawCenteredText(15, "Оставьте свой отзыв о магазине:", colors.text_main)
    drawCenteredText(16, "Ваше мнение поможет нам стать лучше!", colors.text_dim)
    gpu.setBackground(colors.bg_tertiary)
    gpu.fill(15, 18, SCREEN_W - 30, 3, " ")
    gpu.setForeground(colors.text_bright)
    if feedbackEditMode then
        if feedbackInput ~= "" then
            gpu.set(16, 19, unicode.sub(feedbackInput, -(SCREEN_W - 34)) .. "_")
        else
            gpu.setForeground(colors.text_dim)
            gpu.set(16, 19, "Введите ваш отзыв..._")
        end
    else
        if feedbackInput ~= "" then
            gpu.set(16, 19, unicode.sub(feedbackInput, -(SCREEN_W - 34)))
        else
            gpu.setForeground(colors.text_dim)
            gpu.set(16, 19, "Введите ваш отзыв...")
        end
    end
    local cancelBtn = {x = math.floor(SCREEN_W / 2) - 18, y = SCREEN_H - 1, xs = 12, ys = 1, text = "[ ОТМЕНА ]", bg = colors.bg_button, fg = colors.error}
    local sendBtn = {x = math.floor(SCREEN_W / 2) + 6, y = SCREEN_H - 1, xs = 15, ys = 1, text = "[ ОТПРАВИТЬ ]", bg = colors.bg_button, fg = colors.success}
    drawFlexButton(cancelBtn)
    drawFlexButton(sendBtn)
    drawTempMessage()
end

-- Кнопки главного меню (светло-серые с тёмным текстом)
local menuButtons = {
    shop    = {x=math.floor((SCREEN_W - 24) / 2), xs=24, y=math.floor(SCREEN_H * 0.35),  ys=3, text=" Магазин",     tx=6, ty=1, bg=0x888888, fg=0x000000},
    account = {x=math.floor((SCREEN_W - 24) / 2), xs=24, y=math.floor(SCREEN_H * 0.55), ys=3, text=" Аккаунт",      tx=6, ty=1, bg=0x888888, fg=0x000000},
    top     = {x=math.floor((SCREEN_W - 24) / 2), xs=24, y=math.floor(SCREEN_H * 0.75), ys=3, text="🏆 Топ игроков",  tx=6, ty=1, bg=0x888888, fg=0x000000}
}

-- Нижняя панель (без статуса подключения)
local function drawBottomPanel()
    gpu.setForeground(colors.error)
    gpu.set(4, SCREEN_H, "[ ПОДДЕРЖКА ]")
    gpu.set(math.floor(SCREEN_W / 2) - 10, SCREEN_H, "[ СОГЛАШЕНИЕ ]")
    gpu.set(SCREEN_W - 20, SCREEN_H, "[ ОТЗЫВЫ ]")
end

local backButton = {
    text = "[ НАЗАД ]",
    x = math.floor((SCREEN_W - 12) / 2),
    y = SCREEN_H - 1,
    xs = 12,
    ys = 1,
    bg = colors.bg_button,
    fg = colors.accent_light
}

local function isButtonClicked(btn, x, y)
    return y >= btn.y and y < btn.y + btn.ys and x >= btn.x and x < btn.x + btn.xs
end

local nextButton = {text = "[ КУПИТЬ ]", x=math.floor(SCREEN_W / 2) + 5, y=SCREEN_H - 1, xs=11, ys=1, bg=colors.bg_button, fg=colors.inactive}

local stockFilterButton = {
    text = "[ В НАЛИЧИИ ▼ ]",
    x = 3, y = SCREEN_H - 1,
    xs = 22, ys = 1,
    bg = colors.bg_button,
    fg = colors.accent_light
}
local stockAvailableButton = {
    text = "✓ В НАЛИЧИИ",
    x = 3, y = SCREEN_H - 3,
    xs = 22, ys = 1,
    bg = colors.bg_button,
    fg = colors.success
}
local stockAllButton = {
    text = "  ВСЕ",
    x = 3, y = SCREEN_H - 2,
    xs = 22, ys = 1,
    bg = colors.bg_button,
    fg = colors.text_bright
}

local shopMenuButtons = {
    buy    = {x=math.floor((SCREEN_W - 24) / 2), xs=24, y=math.floor(SCREEN_H * 0.40),  ys=3, text="🛍 Покупка",     tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_light},
    sell   = {x=math.floor((SCREEN_W - 24) / 2), xs=24, y=math.floor(SCREEN_H * 0.60), ys=3, text="💰 Пополнение",  tx=5, ty=1, bg=colors.bg_button, fg=colors.accent_light}
}

local function canSendReport()
    if not lastReportTime then return true end
    local now = getRealTimestamp()
    local reportDate = os.date("*t", lastReportTime)
    local nowDate = os.date("*t", now)
    if reportDate.day ~= nowDate.day or reportDate.month ~= nowDate.month or reportDate.year ~= nowDate.year then
        return true
    end
    return false
end

-- ============================================================
-- NBT-ВЫДАЧА
-- ============================================================
local function getItemNbtHash(item)
    if type(item) ~= "table" then return nil end
    local value = item.nbt_hash or item.nbtHash or item.tag_hash or item.tagHash or item.nbt
    if value == nil or tostring(value) == "" then return nil end
    return tostring(value)
end

local function normalizeMeItemId(value)
    local id = tostring(value or "")
    id = id:gsub("\\:", ":")
    if id ~= "" and not id:find(":", 1, true) then
        id = "minecraft:" .. id
    end
    return id
end

local function parseExportCount(result, requested)
    requested = math.max(0, math.floor(tonumber(requested) or 0))
    if type(result) == "number" then
        return math.max(0, math.min(requested, math.floor(result)))
    end
    if result == true then
        return requested
    end
    if type(result) == "table" then
        return math.max(0, math.min(requested, math.floor(tonumber(
            result.size or result.count or result.amount or result.qty
        ) or 0)))
    end
    return 0
end

local NBTDelivery = {}

function NBTDelivery.getMeAddress(me)
    if type(me) == "table" and type(me.address) == "string" and me.address ~= "" then
        return me.address
    end
    for addr in component.list("me_interface") do
        return addr
    end
    return nil
end

function NBTDelivery.unwrapFingerprint(source)
    if type(source) ~= "table" then return {} end
    if type(source.fingerprint) == "table" then return source.fingerprint end
    return source
end

function NBTDelivery.getFingerprintHash(source)
    local entry = type(source) == "table" and source or {}
    local fp = NBTDelivery.unwrapFingerprint(entry)
    local value = fp.nbt_hash or fp.nbtHash or fp.tag_hash or fp.tagHash
        or entry.nbt_hash or entry.nbtHash or entry.tag_hash or entry.tagHash
    if value == nil or tostring(value) == "" then return nil end
    return tostring(value)
end

function NBTDelivery.getEntryAmount(entry, requested)
    if type(entry) ~= "table" then return tonumber(requested) or 0 end
    local fp = NBTDelivery.unwrapFingerprint(entry)
    return tonumber(
        entry.size or entry.qty or entry.count or entry.amount or entry.available
        or fp.size or fp.qty or fp.count or fp.amount or fp.available
    ) or tonumber(requested) or 0
end

function NBTDelivery.getEntryIdDamage(entry)
    local fp = NBTDelivery.unwrapFingerprint(entry)
    local id = normalizeMeItemId(
        fp.id or fp.name or fp.item_name or fp.itemName
        or fp.internal_name or fp.internalName
        or entry.id or entry.name or entry.item_name or entry.itemName
        or entry.internal_name or entry.internalName
    )
    local damage = tonumber(
        fp.dmg or fp.damage or fp.meta or fp.item_damage or fp.itemDamage
        or entry.dmg or entry.damage or entry.meta or entry.item_damage or entry.itemDamage
    ) or 0
    return id, damage
end

function NBTDelivery.readNetworkList(me, methodName, details)
    local address = NBTDelivery.getMeAddress(me)
    local useDetails = details
    if methodName == "getAvailableItems" and useDetails == nil then
        useDetails = "NONE"
    end
    if address then
        local ok, result
        if useDetails ~= nil then
            ok, result = pcall(component.invoke, address, methodName, useDetails)
        else
            ok, result = pcall(component.invoke, address, methodName)
        end
        if ok and type(result) == "table" then return result end
    end
    if not me or type(me[methodName]) ~= "function" then return nil end
    local ok, result
    if useDetails ~= nil then
        ok, result = pcall(me[methodName], useDetails)
    else
        ok, result = pcall(me[methodName])
    end
    if ok and type(result) == "table" then return result end
    if useDetails ~= nil then
        ok, result = pcall(me[methodName], me, useDetails)
    else
        ok, result = pcall(me[methodName], me)
    end
    if ok and type(result) == "table" then return result end
    return nil
end

function NBTDelivery.minimalFingerprint(item, includeNbt)
    local fp = {
        id = normalizeMeItemId(item and (item.internalName or item.id or item.name)),
        dmg = tonumber(item and item.damage) or 0,
    }
    if includeNbt then
        local hash = getItemNbtHash(item)
        if hash then fp.nbt_hash = hash end
    end
    return fp
end

function NBTDelivery.getFingerprints(me, item, requested)
    local targetId = normalizeMeItemId(item and (item.internalName or item.id or item.name))
    local targetDamage = tonumber(item and item.damage) or 0
    local wantedHash = getItemNbtHash(item)
    local found = {}
    local seen = {}
    local list = NBTDelivery.readNetworkList(me, "getAvailableItems", "NONE")
    if type(list) ~= "table" then
        list = NBTDelivery.readNetworkList(me, "getAvailableItems", nil)
    end
    if type(list) ~= "table" then
        list = NBTDelivery.readNetworkList(me, "getItemsInNetwork", nil)
    end
    if type(list) == "table" then
        for _, entry in pairs(list) do
            if type(entry) == "table" then
                local fp = type(entry.fingerprint) == "table" and entry.fingerprint or entry
                if type(fp) == "table" then
                    local id, damage = NBTDelivery.getEntryIdDamage(entry)
                    local hash = NBTDelivery.getFingerprintHash(entry)
                    local amount = math.max(0, math.floor(NBTDelivery.getEntryAmount(entry, requested)))
                    local hashMatches = (wantedHash == nil)
                        or tostring(hash or "") == tostring(wantedHash)
                    if id == targetId and damage == targetDamage and amount > 0 and hashMatches then
                        local key = id .. ":" .. tostring(damage) .. ":" .. tostring(hash or "")
                        if not seen[key] then
                            seen[key] = true
                            found[#found + 1] = {
                                fingerprint = fp,
                                amount = amount,
                                hash = hash,
                            }
                        end
                    end
                end
            end
        end
    end
    list = nil
    pcall(collectgarbage, "step", 10)
    table.sort(found, function(a, b)
        return (tonumber(a.amount) or 0) > (tonumber(b.amount) or 0)
    end)
    return found
end

function NBTDelivery.callExport(me, fingerprint, direction, amount)
    local address = NBTDelivery.getMeAddress(me)
    local ok, result
    if address then
        ok, result = pcall(
            component.invoke, address, "exportItem", fingerprint, direction, amount
        )
    end
    if not ok then
        ok, result = pcall(me.exportItem, fingerprint, direction, amount)
    end
    if not ok then
        ok, result = pcall(me.exportItem, me, fingerprint, direction, amount)
    end
    if not ok then return 0, tostring(result) end
    return parseExportCount(result, amount), result
end

function NBTDelivery.exportExact(me, item, qty, direction, maxStackSize, expectedPlayer)
    local remaining = math.max(0, math.floor(tonumber(qty) or 0))
    local movedTotal = 0
    local entries = NBTDelivery.getFingerprints(me, item, remaining)
    if not checkPimSessionAlive(expectedPlayer) then return 0 end
    for _, entry in ipairs(entries) do
        local available = math.max(0, math.floor(tonumber(entry.amount) or 0))
        while remaining > 0 and available > 0 do
            if not checkPimSessionAlive(expectedPlayer) then return movedTotal end
            local request = math.min(remaining, available, maxStackSize or 64)
            local got = NBTDelivery.callExport(me, entry.fingerprint, direction, request)
            got = math.max(0, math.min(request, available, tonumber(got) or 0))
            if got <= 0 and entry.hash then
                local compact = {
                    id = normalizeMeItemId(item.internalName),
                    dmg = tonumber(item.damage) or 0,
                    nbt_hash = tostring(entry.hash),
                }
                got = NBTDelivery.callExport(me, compact, direction, request)
                got = math.max(0, math.min(request, available, tonumber(got) or 0))
            end
            if got <= 0 then break end
            movedTotal = movedTotal + got
            remaining = remaining - got
            available = available - got
        end
        if remaining <= 0 then break end
    end
    if remaining > 0 and #entries == 0 and getItemNbtHash(item) then
        local compact = NBTDelivery.minimalFingerprint(item, true)
        while remaining > 0 do
            if not checkPimSessionAlive(expectedPlayer) then return movedTotal end
            local request = math.min(remaining, maxStackSize or 64)
            local got = NBTDelivery.callExport(me, compact, direction, request)
            got = math.max(0, math.min(request, tonumber(got) or 0))
            if got <= 0 then break end
            movedTotal = movedTotal + got
            remaining = remaining - got
        end
    end
    return movedTotal
end

function NBTDelivery.exportLegacy(me, item, qty, direction, maxStackSize, expectedPlayer)
    local remaining = math.max(0, math.floor(tonumber(qty) or 0))
    local movedTotal = 0
    local fingerprint = NBTDelivery.minimalFingerprint(item, false)
    while remaining > 0 do
        if not checkPimSessionAlive(expectedPlayer) then return movedTotal end
        local request = math.min(remaining, maxStackSize or 64)
        local got = NBTDelivery.callExport(me, fingerprint, direction, request)
        got = math.max(0, math.min(request, tonumber(got) or 0))
        if got <= 0 then break end
        movedTotal = movedTotal + got
        remaining = remaining - got
    end
    return movedTotal
end

local function exportItemToPlayer(me, item, qty, maxStackSize, expectedPlayer)
    local requested = math.max(0, math.floor(tonumber(qty) or 0))
    if requested <= 0 then return 0 end
    local exactMoved = NBTDelivery.exportExact(
        me, item, requested, PULL_DIRECTION, maxStackSize, expectedPlayer
    )
    if exactMoved >= requested then return exactMoved end
    if not checkPimSessionAlive(expectedPlayer) then return exactMoved end
    if getItemNbtHash(item) then return exactMoved end
    local legacyMoved = NBTDelivery.exportLegacy(
        me, item, requested - exactMoved, PULL_DIRECTION, maxStackSize, expectedPlayer
    )
    return exactMoved + legacyMoved
end

local function getActualItemQuantity(itemOrName, damage)
    if not component.isAvailable("me_interface") then return 0 end
    local me = component.me_interface
    local item
    if type(itemOrName) == "table" then
        item = itemOrName
    else
        item = {internalName = itemOrName, damage = tonumber(damage) or 0}
    end
    local wantedHash = getItemNbtHash(item)
    if wantedHash then
        local entries = NBTDelivery.getFingerprints(me, item, 0)
        local total = 0
        for _, entry in ipairs(entries) do
            total = total + math.max(0, tonumber(entry.amount) or 0)
        end
        return total
    end
    local ok, items = pcall(me.getItemsInNetwork)
    if not ok then
        ok, items = pcall(me.getItemsInNetwork, me)
    end
    if not ok or type(items) ~= "table" then return 0 end
    local total = 0
    for _, meItem in ipairs(items) do
        local name = meItem.name or meItem.id
        local dmg = meItem.damage or meItem.dmg or 0
        if tostring(name or "") == tostring(item.internalName or "")
            and tonumber(dmg or 0) == tonumber(item.damage or 0)
        then
            total = total + (tonumber(meItem.size or meItem.qty or meItem.count) or 0)
        end
    end
    return total
end

local function loadBuyItems()
    local qtyMap = {}
    if component.isAvailable("me_interface") then
        local me = component.me_interface
        local ok, rawItems = pcall(me.getItemsInNetwork)
        if not ok then
            ok, rawItems = pcall(me.getItemsInNetwork, me)
        end
        if ok and type(rawItems) == "table" then
            for _, meItem in ipairs(rawItems) do
                local name = meItem.name or meItem.id
                if name then
                    local damage = meItem.damage or meItem.dmg or 0
                    local key = tostring(name) .. ":" .. tostring(damage)
                    qtyMap[key] = (qtyMap[key] or 0)
                        + (tonumber(meItem.size or meItem.qty or meItem.count) or 0)
                end
            end
        end
    end
    local knownKeys = {}
    for _, item in ipairs(shopItems) do
        local key = tostring(item.internalName) .. ":" .. tostring(item.damage or 0)
        knownKeys[key] = true
    end
    local newFound = {}
    local newShopItems = {}
    for _, mapping in ipairs(buyItemsData) do
        local name = mapping.internalName
        if name and not blacklist[name] then
            local damage = mapping.damage or 0
            local key = tostring(name) .. ":" .. tostring(damage)
            local priceCoin = tonumber(mapping.price_coin or mapping.price or 0) or 0
            local priceEma = tonumber(mapping.price_ema or 0) or 0
            if priceCoin > 0 or priceEma > 0 then
                local qty = qtyMap[key] or 0
                table.insert(newShopItems, {
                    internalName = name,
                    displayName = mapping.displayName or name,
                    qty = qty,
                    priceCoin = priceCoin,
                    priceEma = priceEma,
                    damage = damage,
                    itemLabel = mapping.itemLabel or mapping.item_label,
                    nbt_hash = mapping.nbt_hash or mapping.nbtHash
                        or mapping.tag_hash or mapping.tagHash or mapping.nbt,
                    canBuy = qty > 0
                })
                if not knownKeys[key] and qty > 0 then
                    table.insert(newFound, {
                        name = mapping.displayName or name,
                        qty = qty
                    })
                end
            end
        end
    end
    if #newFound > 0 and currentToken then
        local chunkSize = 10
        for i = 1, #newFound, chunkSize do
            local chunk = {}
            for j = i, math.min(i + chunkSize - 1, #newFound) do
                table.insert(chunk, newFound[j])
            end
            local data = serialization.serialize({
                op = "new_items",
                name = currentPlayer,
                token = currentToken,
                items = chunk
            })
            if #data < 8000 then
                modem.send(serverAddress, 0xffef, data)
            end
            if currentPlayer then
                if not pimAwareSleep(0.05, currentPlayer) then
                    return
                end
            else
                os.sleep(0.05)
            end
        end
    end
    shopItems = newShopItems
    table.sort(shopItems, function(a, b)
        return sortableName(a.displayName) < sortableName(b.displayName)
    end)
end

local function loadSellItems()
    shopItems = {}
    for _, item in ipairs(sellItems) do
        local internal = item.internalName or item.name
        if internal then
            table.insert(shopItems, {
                displayName = item.displayName or item.name or internal,
                internalName = internal,
                qty = item.qty or 0,
                price = item.price or 0,
                damage = item.damage or 0
            })
        end
    end
end

local function scanPlayerInventory(targetName, targetDamage)
    local pimAddr = getPimAddr()
    if not pimAddr then return 0 end
    targetDamage = targetDamage or 0
    local total = 0
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.name or stack.label or ""
                local cleanName = rawName:gsub("§.", "")
                local damage = stack.damage or 0
                if namesMatch(cleanName, targetName) and damage == targetDamage then
                    total = total + qty
                end
            end
        end
    end
    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "scan_report",
            name = currentPlayer,
            token = currentToken,
            target = targetName,
            found = total
        }))
    end
    return total
end

local function extractToME(targetName, amount, targetDamage)
    local pimAddr = getPimAddr()
    if not pimAddr or amount <= 0 then return 0 end
    targetDamage = targetDamage or 0
    local extracted = 0
    for slot = 1, 36 do
        if extracted >= amount then break end
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.name or stack.label or ""
                local cleanName = rawName:gsub("§.", "")
                local damage = stack.damage or 0
                if namesMatch(cleanName, targetName) and damage == targetDamage then
                    local toTake = math.min(qty, amount - extracted)
                    if toTake > 0 then
                        local moved = component.invoke(pimAddr, "pushItem", PUSH_DIRECTION, slot, toTake)
                        if type(moved) == "number" and moved > 0 then
                            extracted = extracted + moved
                        end
                    end
                end
            end
        end
    end
    return extracted
end

local function getFilteredItems()
    local filtered = {}
    local searchLower = normalizeSearchText(shopSearch)
    local searchWords = {}
    if searchLower ~= "" then
        for word in searchLower:gmatch("%S+") do
            table.insert(searchWords, word)
        end
    end
    for _, item in ipairs(shopItems) do
        local displayLower = normalizeSearchText(item.displayName or "")
        local internalLower = normalizeSearchText(item.internalName or "")
        local haystack = displayLower .. " " .. internalLower
        local matchesSearch = (#searchWords == 0)
        if not matchesSearch then
            for _, word in ipairs(searchWords) do
                if string.find(haystack, word, 1, true) then
                    matchesSearch = true
                    break
                end
            end
        end
        local matchesStock = true
        if currentShopMode == "buy" and stockFilterMode == "available" then
            matchesStock = (tonumber(item.qty) or 0) > 0
        end
        if matchesSearch and matchesStock then
            table.insert(filtered, item)
        end
    end
    table.sort(filtered, function(a, b)
        return sortableName(a.displayName or a.internalName) < sortableName(b.displayName or b.internalName)
    end)
    maxItemWidth = 0
    for _, item in ipairs(filtered) do
        local len = unicode.len(item.displayName or item.internalName or "")
        if len > maxItemWidth then maxItemWidth = len end
    end
    return filtered
end

local function drawBalanceLine(x, y)
    gpu.setForeground(colors.text_bright)
    gpu.set(x, y, "💰 Баланс: ")
    local coinStr = string.format("%.2f", coinBalance) .. " ₵"
    gpu.setForeground(colors.gold)
    gpu.set(x + unicode.len("💰 Баланс: "), y, coinStr)
    gpu.setForeground(colors.text_dim)
    gpu.set(x + unicode.len("💰 Баланс: ") + unicode.len(coinStr), y, " | ")
    local emaStr = "ЭМЫ: " .. string.format("%.2f", emaBalance) .. " ۞"
    gpu.setForeground(colors.tomato)
    gpu.set(x + unicode.len("💰 Баланс: ") + unicode.len(coinStr) + unicode.len(" | "), y, emaStr)
end

local function drawSearchBar()
    local searchX = math.floor(SCREEN_W / 2) - 12
    local searchText = ""
    if searchActive then
        searchText = searchInput .. "_"
    else
        searchText = (shopSearch == "" and " Поиск..." or shopSearch)
    end
    gpu.setBackground(colors.bg_tertiary)
    gpu.fill(searchX, 3, 25, 1, " ")
    gpu.setForeground(colors.accent_light)
    gpu.set(searchX + 1, 3, unicode.sub(searchText, 1, 23))
    local clearText = "[  ]"
    local clearWidth = unicode.len(clearText) + 2
    local clearX = searchX + 25 + 1
    gpu.setBackground(colors.error_dark)
    gpu.fill(clearX, 3, clearWidth, 1, " ")
    gpu.setForeground(colors.text_bright)
    local textX = clearX + math.floor((clearWidth - unicode.len(clearText)) / 2)
    gpu.set(textX, 3, clearText)
    gpu.setBackground(colors.bg_main)
end

drawBuyStatic = function()
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)
    if currentShopMode == "buy" then
        gpu.setForeground(colors.accent_light)
        gpu.set(3, 3, "🏪 Магазин продаёт")
    else
        gpu.setForeground(colors.accent_light)
        gpu.set(3, 3, "💰 Магазин покупает")
    end
    drawSearchBar()
    gpu.setBackground(colors.bg_tertiary)
    gpu.fill(2, 5, SCREEN_W - 4, 1, " ")
    gpu.setForeground(colors.text_bright)
    gpu.set(3, 5, "Название")
    gpu.set(math.floor(SCREEN_W / 2) - 5, 5, "Кол-во")
    if currentShopMode == "buy" then
        gpu.set(math.floor(SCREEN_W / 2) + 8, 5, "₵ Coina")
        gpu.set(math.floor(SCREEN_W / 2) + 20, 5, "۞ ЭМЫ")
    else
        gpu.set(math.floor(SCREEN_W / 2) + 18, 5, "Цена")
    end
    gpu.setBackground(colors.bg_main)
    drawTempMessage()
end

local function drawSingleRow(y, item, isHovered, isSelected, itemIndex)
    if not item then return end
    local bg, fg
    if currentShopMode == "buy" and item.qty == 0 then
        bg = colors.bg_secondary
        fg = colors.inactive
    elseif isSelected then
        bg = colors.accent_dark
        fg = colors.text_bright
    elseif isHovered then
        bg = colors.bg_button_hover
        fg = colors.text_bright
    elseif itemIndex % 2 == 1 then
        bg = colors.bg_secondary
        fg = colors.text_main
    else
        bg = colors.bg_main
        fg = colors.text_main
    end
    gpu.setBackground(bg)
    gpu.fill(2, y, SCREEN_W - 4, 1, " ")
    gpu.setForeground(fg)
    local name = item.displayName or item.internalName
    local maxNameLen = math.floor(SCREEN_W / 2) - 8
    if unicode.len(name) > maxNameLen then
        name = unicode.sub(name, horizontalScroll, horizontalScroll + maxNameLen - 1)
    end
    gpu.set(3, y, name)
    if currentShopMode == "buy" then
        if item.qty > 0 then
            gpu.setForeground(colors.text_bright)
        else
            gpu.setForeground(colors.inactive)
        end
    else
        gpu.setForeground(colors.text_bright)
    end
    gpu.set(math.floor(SCREEN_W / 2) - 5, y, tostring(item.qty))
    if currentShopMode == "sell" then
        if item.internalName == "customnpcs:npcMoney" then
            gpu.setForeground(colors.tomato)
            local priceStr = string.format("%.2f", item.price) .. " ۞"
            gpu.set(math.floor(SCREEN_W / 2) + 18, y, priceStr)
        else
            gpu.setForeground(colors.gold)
            local priceStr = string.format("%.2f", item.price) .. " ₵"
            gpu.set(math.floor(SCREEN_W / 2) + 18, y, priceStr)
        end
    else
        if item.priceCoin and item.priceCoin > 0 then
            gpu.setForeground(colors.gold)
            local coinStr = string.format("%.2f", item.priceCoin)
            gpu.set(math.floor(SCREEN_W / 2) + 8, y, coinStr)
        else
            gpu.setForeground(colors.inactive)
            gpu.set(math.floor(SCREEN_W / 2) + 8, y, "0")
        end
        if item.priceEma and item.priceEma > 0 then
            gpu.setForeground(colors.tomato)
            local emaStr = string.format("%.2f", item.priceEma)
            gpu.set(math.floor(SCREEN_W / 2) + 20, y, emaStr)
        else
            gpu.setForeground(colors.inactive)
            gpu.set(math.floor(SCREEN_W / 2) + 20, y, "0")
        end
    end
    gpu.setBackground(colors.bg_main)
end

local function drawScrollBar()
    local total = #filteredItems
    local barX = SCREEN_W - 2
    local barY = 7
    local barHeight = visibleRows
    gpu.setBackground(colors.bg_main)
    gpu.fill(barX, barY, 2, barHeight, " ")
    if total <= visibleRows then return end
    gpu.setBackground(colors.bg_secondary)
    gpu.fill(barX, barY, 2, barHeight, " ")
    local thumbHeight = math.max(2, math.floor(barHeight * visibleRows / total))
    local maxPos = barHeight - thumbHeight
    local thumbPos = math.floor((listScroll - 1) * maxPos / (total - visibleRows)) + 1
    thumbPos = math.min(thumbPos, maxPos + 1)
    gpu.setBackground(colors.accent_main)
    gpu.fill(barX, barY + thumbPos - 1, 2, thumbHeight, " ")
    gpu.setBackground(colors.bg_main)
end

drawBuyItemsList = function()
    filteredItems = getFilteredItems()
    local maxScroll = math.max(1, #filteredItems - visibleRows + 1)
    listScroll = math.max(1, math.min(listScroll, maxScroll))
    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 7, SCREEN_W - 4, visibleRows, " ")
    if #filteredItems == 0 then
        local msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
        local msgX = math.floor((SCREEN_W - unicode.len(msg)) / 2) + 1
        local msgY = math.floor(SCREEN_H / 2)
        gpu.setForeground(colors.error)
        gpu.set(msgX, msgY, msg)
    else
        for i = 1, visibleRows do
            local itemIndex = listScroll + i - 1
            local item = filteredItems[itemIndex]
            if not item then break end
            local y = 6 + i
            local isSelected = (itemIndex == selectedIndex)
            local isHovered = (itemIndex == hoveredIndex)
            drawSingleRow(y, item, isHovered, isSelected, itemIndex)
        end
    end
    drawScrollBar()
    if selectedItem then
        updateSelectorDisplay(selectedItem)
    end
end

local function smoothScroll(steps)
    local filtered = filteredItems
    local total = #filtered
    local maxScroll = math.max(1, total - visibleRows + 1)
    local newScroll = listScroll + steps
    newScroll = math.max(1, math.min(newScroll, maxScroll))
    if newScroll == listScroll then return end
    if math.abs(steps) == 1 and total > visibleRows then
        if steps > 0 then
            gpu.copy(2, 8, SCREEN_W - 4, visibleRows - 1, 0, -1)
            gpu.setBackground(colors.bg_main)
            gpu.fill(2, 6 + visibleRows, SCREEN_W - 4, 1, " ")
            local newIdx = newScroll + visibleRows - 1
            if newIdx <= total then
                drawSingleRow(6 + visibleRows, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
            end
        else
            gpu.copy(2, 7, SCREEN_W - 4, visibleRows - 1, 0, 1)
            gpu.setBackground(colors.bg_main)
            gpu.fill(2, 7, SCREEN_W - 4, 1, " ")
            local newIdx = newScroll
            if newIdx >= 1 then
                drawSingleRow(7, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
            end
        end
    else
        drawBuyItemsList()
        return
    end
    listScroll = newScroll
    drawScrollBar()
end

local function drawStockFilter()
    if currentShopMode ~= "buy" then
        return
    end
    if stockFilterMode == "available" then
        stockFilterButton.text = "[ В НАЛИЧИИ ▼ ]"
    else
        stockFilterButton.text = "[ ВСЕ ▼ ]"
    end
    gpu.setBackground(colors.bg_main)
    gpu.fill(stockFilterButton.x, SCREEN_H - 3, stockFilterButton.xs, 2, " ")
    if stockFilterOpen then
        stockAvailableButton.text = (stockFilterMode == "available" and "✓ " or "  ") .. "В НАЛИЧИИ"
        stockAllButton.text = (stockFilterMode == "all" and "✓ " or "  ") .. "ВСЕ"
        stockAvailableButton.fg = (stockFilterMode == "available") and colors.success or colors.text_bright
        stockAllButton.fg = (stockFilterMode == "all") and colors.success or colors.text_bright
        drawFlexButton(stockAvailableButton)
        drawFlexButton(stockAllButton)
    end
    drawFlexButton(stockFilterButton)
end

local function applyStockFilter(mode)
    if mode ~= "available" and mode ~= "all" then return end
    stockFilterMode = mode
    stockFilterOpen = false
    listScroll = 1
    selectedIndex = 0
    hoveredIndex = 0
    selectedItem = nil
    updateSelectorDisplay(nil)
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

drawBuyButtons = function()
    if currentShopMode == "buy" then
        nextButton.text = "[ КУПИТЬ ]"
        nextButton.xs = unicode.len(nextButton.text) + 2
    else
        nextButton.text = "[ ПРОДАТЬ ]"
        nextButton.xs = unicode.len(nextButton.text) + 2
    end
    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
        nextButton.fg = colors.accent_light
    else
        nextButton.fg = colors.inactive
    end
    drawFlexButton(backButton)
    drawFlexButton(nextButton)
    drawStockFilter()
    drawTempMessage()
end

local function drawPurchaseScreen()
    currentScreen = "purchase"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)
    gpu.setForeground(colors.success)
    gpu.set(3, 3, "📦 Имя предмета: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(20, 3, purchaseItem.displayName)
    gpu.setForeground(colors.success)
    gpu.set(math.floor(SCREEN_W / 2) + 5, 3, " Доступно: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(math.floor(SCREEN_W / 2) + 18, 3, tostring(purchaseItem.qty))
    local totalCoin = (purchaseItem.priceCoin or 0) * purchaseQuantity
    local totalEma = (purchaseItem.priceEma or 0) * purchaseQuantity
    gpu.setForeground(colors.success)
    gpu.set(3, 5, "💵 На сумму: ")
    local sumY = 5
    if totalCoin > 0 then
        gpu.setForeground(colors.gold)
        gpu.set(16, sumY, string.format("%.2f", totalCoin) .. " ₵")
        sumY = sumY + 1
    end
    if totalEma > 0 then
        gpu.setForeground(colors.tomato)
        gpu.set(16, sumY, string.format("%.2f", totalEma) .. " ۞")
    end
    gpu.setForeground(colors.success)
    gpu.set(math.floor(SCREEN_W / 2) + 5, 5, "💰 Цена: ")
    local priceY = 5
    if purchaseItem.priceCoin and purchaseItem.priceCoin > 0 then
        gpu.setForeground(colors.gold)
        gpu.set(math.floor(SCREEN_W / 2) + 14, priceY, string.format("%.2f", purchaseItem.priceCoin) .. " ")
        priceY = priceY + 1
    end
    if purchaseItem.priceEma and purchaseItem.priceEma > 0 then
        gpu.setForeground(colors.tomato)
        gpu.set(math.floor(SCREEN_W / 2) + 14, priceY, string.format("%.2f", purchaseItem.priceEma) .. " ")
    end
    gpu.setForeground(colors.success)
    gpu.set(3, 7, "🔢 Кол-во: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(14, 7, tostring(purchaseQuantity))
    local keys = {
        {"1","2","3"},
        {"4","5","6"},
        {"7","8","9"},
        {"<","0","C"}
    }
    local startX = math.floor((SCREEN_W - 15) / 2)
    local startY = math.floor(SCREEN_H * 0.35)
    local btnW = 3
    local btnH = 1
    local spacing = 2
    for row = 1, 4 do
        for col = 1, 3 do
            local x = startX + (col-1)*(btnW + spacing)
            local y = startY + (row-1)*(btnH + 1)
            local text = keys[row][col]
            gpu.setBackground(colors.bg_button)
            gpu.fill(x, y, btnW, btnH, " ")
            gpu.setForeground(colors.accent_light)
            local tx = x + math.floor((btnW - unicode.len(text)) / 2)
            local ty = y
            gpu.set(tx, ty, text)
        end
    end
    local backBtn = {x = math.floor(SCREEN_W / 2) - 18, y = SCREEN_H - 1, xs = unicode.len("[ НАЗАД ]") + 2, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_light}
    local buyBtn  = {x = math.floor(SCREEN_W / 2) + 6, y = SCREEN_H - 1, xs = unicode.len("[ КУПИТЬ ]") + 2, ys = 1, text = "[ КУПИТЬ ]", bg = colors.bg_button, fg = colors.success}
    drawFlexButton(backBtn)
    drawFlexButton(buyBtn)
    drawTempMessage()
end

local function handleQuantityButtonClick(btnText)
    if btnText == "C" then
        purchaseQuantity = 0
    elseif btnText == "<" then
        purchaseQuantity = math.floor(purchaseQuantity / 10)
    elseif tonumber(btnText) then
        local digit = tonumber(btnText)
        if purchaseQuantity == 0 then
            purchaseQuantity = digit
        else
            purchaseQuantity = purchaseQuantity * 10 + digit
        end
        if purchaseItem and purchaseQuantity > purchaseItem.qty then
            purchaseQuantity = purchaseItem.qty
        end
    end
    drawPurchaseScreen()
end

local function goToPurchase(item)
    if not item then return end
    purchaseItem = item
    purchaseQuantity = 1
    drawPurchaseScreen()
end

local function drawSellPopup()
    local popupWidth = 45
    local popupHeight = 11
    local popupX = math.floor((SCREEN_W - popupWidth) / 2)
    local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(popupX, popupY+2, popupWidth, popupHeight-4, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.border_accent)
    local name = sellConfirmItem.displayName
    local totalFound = foundAmount
    local value = totalFound * sellConfirmItem.price
    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+16, popupY, "Подтверждение")
    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+3, "Магазин заберёт: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+3 + unicode.len("Магазин заберёт: "), popupY+3, tostring(totalFound))
    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+4, name .. " x")
    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+3 + unicode.len(name .. " x"), popupY+4, tostring(totalFound))
    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+5, "Вы получите: ")
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato)
        gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ")
    else
        gpu.setForeground(colors.gold)
        gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ₵")
    end
    local yesBtn = {x=popupX+5, y=popupY+8, xs=15, ys=1, text="[ Принять ]", bg=colors.bg_button, fg=colors.success}
    local noBtn  = {x=popupX+popupWidth-18, y=popupY+8, xs=14, ys=1, text="[ Отмена ]", bg=colors.bg_button, fg=colors.error}
    drawFlexButton(yesBtn)
    drawFlexButton(noBtn)
    drawTempMessage()
end

local function drawInsufficientPopup()
    local popupWidth = 55
    local popupHeight = 12
    local popupX = math.floor((SCREEN_W - popupWidth) / 2)
    local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)
    gpu.setForeground(colors.error)
    local title = "НЕДОСТАТОЧНО СРЕДСТВ"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)
    gpu.setForeground(colors.text_main)
    local line1a = "Пополни баланс, не можешь купить"
    local line1aX = popupX + math.floor((popupWidth - unicode.len(line1a)) / 2)
    gpu.set(line1aX, popupY+2, line1a)
    local line1b = "хотя бы 1 штуку предмета."
    local line1bX = popupX + math.floor((popupWidth - unicode.len(line1b)) / 2)
    gpu.set(line1bX, popupY+3, line1b)
    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+5, "Твой баланс Coin: ")
    gpu.setForeground(colors.gold)
    gpu.set(popupX+3 + unicode.len("Твой баланс Coin: "), popupY+5, string.format("%.2f", insufficientBalanceCoin) .. " ₵")
    if insufficientBalanceEma > 0 then
        gpu.setForeground(colors.success)
        gpu.set(popupX+3, popupY+6, "Твой баланс ЭМЫ: ")
        gpu.setForeground(colors.tomato)
        gpu.set(popupX+3 + unicode.len("Твой баланс ЭМЫ: "), popupY+6, string.format("%.2f", insufficientBalanceEma) .. " ۞")
    end
    local okBtnText = "[ ПОНЯТНО ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+9,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

local function drawPartialPopup()
    local popupWidth = 55
    local popupHeight = 10
    local popupX = math.floor((SCREEN_W - popupWidth) / 2)
    local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.warning)
    gpu.setForeground(colors.warning)
    local title = "НЕ ПОЛНАЯ ВЫДАЧА"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)
    gpu.setForeground(colors.text_main)
    local line1 = "Не хватило места в инвентаре!"
    local line1X = popupX + math.floor((popupWidth - unicode.len(line1)) / 2)
    gpu.set(line1X, popupY+2, line1)
    local line2 = "Выдано " .. partialExtracted .. " из " .. partialRequested
    local line2X = popupX + math.floor((popupWidth - unicode.len(line2)) / 2)
    gpu.set(line2X, popupY+3, line2)
    local spentLabelCoin = "Списано Coin: "
    local spentValueCoin = string.format("%.2f", partialRefundCoin) .. " ₵"
    local fullSpentTextCoin = spentLabelCoin .. spentValueCoin
    local spentStartXCoin = popupX + math.floor((popupWidth - unicode.len(fullSpentTextCoin)) / 2)
    gpu.setForeground(colors.success)
    gpu.set(spentStartXCoin, popupY+4, spentLabelCoin)
    gpu.setForeground(colors.gold)
    gpu.set(spentStartXCoin + unicode.len(spentLabelCoin), popupY+4, spentValueCoin)
    if partialRefundEma > 0 then
        local spentLabelEma = "Списано ЭМЫ: "
        local spentValueEma = string.format("%.2f", partialRefundEma) .. " ۞"
        local fullSpentTextEma = spentLabelEma .. spentValueEma
        local spentStartXEma = popupX + math.floor((popupWidth - unicode.len(fullSpentTextEma)) / 2)
        gpu.setForeground(colors.success)
        gpu.set(spentStartXEma, popupY+5, spentLabelEma)
        gpu.setForeground(colors.tomato)
        gpu.set(spentStartXEma + unicode.len(spentLabelEma), popupY+5, spentValueEma)
    end
    local okBtnText = "[ ПРИНЯТЬ ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+7,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

local function drawInventoryFullPopup()
    local popupWidth = 55
    local popupHeight = 10
    local popupX = math.floor((SCREEN_W - popupWidth) / 2)
    local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.warning)
    gpu.setForeground(colors.warning)
    local title = "ПРЕДУПРЕЖДЕНИЕ"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)
    gpu.setForeground(colors.text_main)
    local line1 = "Ваш инвентарь полон!"
    local line1X = popupX + math.floor((popupWidth - unicode.len(line1)) / 2)
    gpu.set(line1X, popupY+2, line1)
    local line2 = "Освободите его и повторите попытку."
    local line2X = popupX + math.floor((popupWidth - unicode.len(line2)) / 2)
    gpu.set(line2X, popupY+3, line2)
    local okBtnText = "[ ПОНЯТНО ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+7,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

local function drawSellScanScreen()
    currentScreen = "sell_scan"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)
    gpu.setForeground(colors.success)
    gpu.set(3, 3, "📦 Имя предмета: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(20, 3, sellConfirmItem.displayName)
    gpu.setForeground(colors.success)
    gpu.set(math.floor(SCREEN_W / 2) + 5, 3, "💰 Цена: ")
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato)
        gpu.set(math.floor(SCREEN_W / 2) + 14, 3, string.format("%.2f", sellConfirmItem.price) .. " ۞")
    else
        gpu.setForeground(colors.gold)
        gpu.set(math.floor(SCREEN_W / 2) + 14, 3, string.format("%.2f", sellConfirmItem.price) .. " ₵")
    end
    gpu.setForeground(colors.success)
    gpu.set(3, 5, "📊 Можно продать: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(20, 5, tostring(sellConfirmItem.qty))
    gpu.setForeground(colors.accent_light)
    local scanText = "Сканировать на наличие предмета:"
    local scanX = math.floor((SCREEN_W - unicode.len(scanText)) / 2)
    gpu.set(scanX, math.floor(SCREEN_H * 0.35), scanText)
    local allBtn  = {x=math.floor(SCREEN_W / 2) - 12, y=math.floor(SCREEN_H * 0.35) + 2, xs=24, ys=1, text="Весь инвентарь", bg=colors.bg_button, fg=colors.success}
    drawFlexButton(allBtn)
    drawFlexButton(backButton)
    if showSellPopup and sellConfirmItem then
        drawSellPopup()
    end
    drawTempMessage()
end

local function goToSellConfirm(item)
    if not item then return end
    sellConfirmItem = item
    foundAmount = 0
    showSellPopup = false
    drawSellScanScreen()
end

local function performSell()
    local sellOwner = currentPlayer
    if not sellOwner or not checkPimSessionAlive(sellOwner) then return end
    if isPlayerPhysicallyOnPim() == false then return end
    if not playerAgreed then
        drawCenteredText(17, "Сначала примите пользовательское соглашение", colors.error)
        if not pimAwareSleep(2, sellOwner) then return end
        if isPlayerPhysicallyOnPim() == false then return end
        currentScreen = "menu"
        drawMainMenu()
        return
    end
    showSellPopup = false
    drawSellScanScreen()
    drawCenteredText(17, "Выполняется пополнение...", colors.accent_light)
    if not pimAwareSleep(0.2, sellOwner) then return end
    local realExtracted = extractToME(sellConfirmItem.internalName, foundAmount, sellConfirmItem.damage or 0)
    if realExtracted == 0 then
        drawCenteredText(17, "Не удалось изъять предметы! Проверьте инвентарь.", colors.error)
        os.sleep(2)
        currentScreen = "shop_sell"
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        return
    end
    local value = realExtracted * sellConfirmItem.price
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        emaBalance = emaBalance + value
    else
        coinBalance = coinBalance + value
    end
    playerTransactions = playerTransactions + 1
    
    -- Обновление статистики
    updatePlayerStat(currentPlayer, "earned", value)
    updatePlayerStat(currentPlayer, "sells")
    updatePlayerStat(currentPlayer, "balance", coinBalance + emaBalance)
    
    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "sell",
            name = currentPlayer,
            token = currentToken,
            item = sellConfirmItem.displayName,
            internalName = sellConfirmItem.internalName,
            qty = realExtracted,
            value = value
        }))
    end
    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 17, SCREEN_W - 4, 1, " ")
    local currencySymbol = (sellConfirmItem.internalName == "customnpcs:npcMoney") and "" or "₵"
    drawCenteredText(17, "Успешно! +" .. string.format("%.2f", value) .. " " .. currencySymbol, colors.success)
    if not pimAwareSleep(0.8, sellOwner) then return end
    currentScreen = "shop_sell"
    showSellPopup = false
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

local function performBuy()
    local purchaseOwner = currentPlayer
    if not purchaseOwner or not checkPimSessionAlive(purchaseOwner) then return end
    if not playerAgreed then
        drawCenteredText(20, "Сначала примите пользовательское соглашение", colors.error)
        if not pimAwareSleep(2, purchaseOwner) then return end
        currentScreen = "menu"
        drawMainMenu()
        return
    end
    local me = component.me_interface
    local item = purchaseItem
    local actualQty = getActualItemQuantity(item)
    if actualQty <= 0 then
        drawCenteredText(20, "Товар закончился! Обновление списка...", colors.error)
        if not pimAwareSleep(0.8, purchaseOwner) then return end
        loadBuyItems()
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        currentScreen = "shop_buy"
        return
    end
    local qty = purchaseQuantity
    if qty > actualQty then
        qty = actualQty
        purchaseQuantity = qty
        drawPurchaseScreen()
    end
    if qty <= 0 then
        drawCenteredText(20, "Выберите количество!", colors.error)
        if not pimAwareSleep(0.8, purchaseOwner) then return end
        currentScreen = "shop_buy"
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        return
    end
    local totalCoin = (item.priceCoin or 0) * qty
    local totalEma = (item.priceEma or 0) * qty
    if coinBalance < totalCoin or emaBalance < totalEma then
        showInsufficientPopup = true
        insufficientBalanceCoin = coinBalance
        insufficientBalanceEma = emaBalance
        drawPurchaseScreen()
        drawInsufficientPopup()
        return
    end
    drawCenteredText(20, "Выполняется покупка...", colors.accent_light)
    if not pimAwareSleep(0.4, purchaseOwner) then return end
    local maxStackSize = 64
    local ok, detail = pcall(me.getItemDetail, me, item.internalName, item.damage)
    if ok and detail and detail.maxSize then
        maxStackSize = detail.maxSize
    end
    local extracted = exportItemToPlayer(me, item, qty, maxStackSize, purchaseOwner)
    if not checkPimSessionAlive(purchaseOwner) then return end
    if extracted == 0 then
        drawPurchaseScreen()
        drawCenteredText(20, "МЭ не смогла выдать этот вариант предмета", colors.error)
        return
    end
    if extracted < qty then
        local actuallySpentCoin = extracted * (item.priceCoin or 0)
        local actuallySpentEma = extracted * (item.priceEma or 0)
        coinBalance = coinBalance - actuallySpentCoin
        emaBalance = emaBalance - actuallySpentEma
        playerTransactions = playerTransactions + 1
        
        -- Обновление статистики
        updatePlayerStat(currentPlayer, "spent", actuallySpentCoin + actuallySpentEma)
        updatePlayerStat(currentPlayer, "purchases")
        updatePlayerStat(currentPlayer, "balance", coinBalance + emaBalance)
        
        if currentToken then
            modem.send(serverAddress, 0xffef, serialization.serialize({
                op = "buy",
                name = currentPlayer,
                token = currentToken,
                item = item.displayName,
                internalName = item.internalName,
                qty = extracted,
                value_coin = actuallySpentCoin,
                value_ema = actuallySpentEma
            }))
        end
        partialExtracted = extracted
        partialRequested = qty
        partialRefundCoin = actuallySpentCoin
        partialRefundEma = actuallySpentEma
        partialItem = item
        showPartialPopup = true
        drawPurchaseScreen()
        drawPartialPopup()
        return
    end
    coinBalance = coinBalance - totalCoin
    emaBalance = emaBalance - totalEma
    playerTransactions = playerTransactions + 1
    
    -- Обновление статистики
    updatePlayerStat(currentPlayer, "spent", totalCoin + totalEma)
    updatePlayerStat(currentPlayer, "purchases")
    updatePlayerStat(currentPlayer, "balance", coinBalance + emaBalance)
    
    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "buy",
            name = currentPlayer,
            token = currentToken,
            item = item.displayName,
            internalName = item.internalName,
            qty = extracted,
            value_coin = totalCoin,
            value_ema = totalEma
        }))
    end
    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 20, SCREEN_W - 4, 1, " ")
    local priceStr = ""
    if totalCoin > 0 then priceStr = priceStr .. string.format("%.2f", totalCoin) .. "₵" end
    if totalEma > 0 then
        if priceStr ~= "" then priceStr = priceStr .. " + " end
        priceStr = priceStr .. string.format("%.2f", totalEma) .. "۞"
    end
    drawCenteredText(20, "Куплено " .. extracted .. " шт. за " .. priceStr, colors.success)
    loadBuyItems()
    for _, newItem in ipairs(shopItems) do
        if newItem.internalName == item.internalName
            and newItem.damage == item.damage
            and tostring(getItemNbtHash(newItem) or "") == tostring(getItemNbtHash(item) or "")
        then
            purchaseItem = newItem
            break
        end
    end
    if not pimAwareSleep(0.8, purchaseOwner) then return end
    currentScreen = "shop_buy"
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

local function drawReportScreen()
    currentScreen = "report"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "РЕПОРТ", colors.accent_light)
    gpu.setForeground(colors.text_main)
    local help1 = "Опишите проблему: баг, предложение, жалоба."
    local helpX = math.floor((SCREEN_W - unicode.len(help1)) / 2) + 1
    gpu.set(helpX, 7, help1)
    if not canSendReport() then
        drawCenteredText(9, "Вы уже отправляли репорт сегодня.", colors.error)
        drawCenteredText(10, "Лимит: 1 сообщение в сутки (сброс в 00:00 МСК).", colors.error)
        drawFlexButton(backButton)
        drawTempMessage()
        return
    end
    gpu.setBackground(colors.bg_tertiary)
    gpu.fill(15, 9, SCREEN_W - 30, 3, " ")
    gpu.setForeground(colors.text_bright)
    if reportInput ~= "" then
        gpu.set(16, 10, unicode.sub(reportInput, -(SCREEN_W - 34)))
    else
        gpu.setForeground(colors.text_dim)
        gpu.set(16, 10, "Введите текст сообщения...")
    end
    gpu.setBackground(colors.bg_main)
    local sendBtn = {x=math.floor(SCREEN_W / 2) - 8, y=14, xs=17, ys=1, text="[ ОТПРАВИТЬ ]", bg=colors.bg_button, fg=colors.success}
    drawFlexButton(sendBtn)
    drawFlexButton(backButton)
    gpu.setForeground(colors.text_main)
    drawCenteredText(16, "Ограничение: 1 репорт в сутки (сброс в 00:00 МСК)", colors.text_dim)
    drawTempMessage()
end

local function goToBuy()
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", colors.text_main)
        os.sleep(3)
        drawMainMenu()
        return
    end
    currentScreen = "shop_buy"
    currentShopMode = "buy"
    listScroll = 1
    horizontalScroll = 1
    selectedIndex = 0
    hoveredIndex = 0
    selectedItem = nil
    shopSearch = ""
    searchActive = false
    searchInput = ""
    stockFilterMode = "available"
    stockFilterOpen = false
    loadBuyItems()
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

local function goToSell()
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", colors.text_main)
        os.sleep(3)
        drawMainMenu()
        return
    end
    currentScreen = "shop_sell"
    currentShopMode = "sell"
    listScroll = 1
    horizontalScroll = 1
    selectedIndex = 0
    hoveredIndex = 0
    selectedItem = nil
    shopSearch = ""
    searchActive = false
    searchInput = ""
    stockFilterOpen = false
    loadSellItems()
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

local function drawShopMenu()
    clear()
    drawScreenBorder()
    drawCenteredText(6, "МАГАЗИН", colors.accent_light)
    if not playerAgreed then
        drawCenteredText(9, "Доступ запрещён.", colors.error)
        drawCenteredText(10, "Примите соглашение, нажав [Соглашение] в главном меню.", colors.accent_light)
        drawFlexButton(backButton)
        drawTempMessage()
        return
    end
    for _, btn in pairs(shopMenuButtons) do
        drawButton(btn)
    end
    drawFlexButton(backButton)
    drawTempMessage()
end

local function drawWelcomeScreen()
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    drawBigTitle()
    gpu.setForeground(colors.accent_light)
    drawCenteredText(math.floor(SCREEN_H * 0.75), "↓   Встаньте на PIM   ↓", colors.accent_light)
    drawCenteredText(math.floor(SCREEN_H * 0.75) + 1, "━━━━━━━━━━━━━━━━━━━", colors.border_accent)
    gpu.setForeground(colors.text_main)
    gpu.setBackground(colors.bg_main)
    drawTempMessage()
end

closePimSession = function()
    currentPlayer = nil
    currentToken = nil
    alreadyAuthorized = false
    currentScreen = "welcome"
    coinBalance = 0.0
    emaBalance = 0.0
    playerTransactions = 0
    playerRegDate = ""
    playerAgreed = false
    authStartTime = 0
    authLastSendTime = 0
    authTechWork = false
    accountRequestTime = 0
    selectedItem = nil
    purchaseItem = nil
    sellConfirmItem = nil
    partialItem = nil
    selectedIndex = 0
    hoveredIndex = 0
    listScroll = 1
    purchaseQuantity = 1
    foundAmount = 0
    showSellPopup = false
    showPartialPopup = false
    showInsufficientPopup = false
    showInventoryFullPopup = false
    stockFilterOpen = false
    searchActive = false
    searchInput = ""
    shopSearch = ""
    if tempMessageTimer then
        pcall(event.cancel, tempMessageTimer)
        tempMessageTimer = nil
    end
    tempMessage = ""
    pcall(updateSelectorDisplay, nil)
    safeSelectorSetSlot(0, nil)
    safeSelectorSetSlot(1, nil)
    drawWelcomeScreen()
end

local function drawAuthScreen()
    authTechWork = false
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    drawBigTitle()
    gpu.setForeground(colors.text_bright)
    drawCenteredText(math.floor(SCREEN_H * 0.75), "Авторизация....", colors.text_bright)
    gpu.setForeground(colors.text_main)
    gpu.setBackground(colors.bg_main)
    drawTempMessage()
end

local function drawTechWorkScreen()
    if authTechWork then return end
    authTechWork = true
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    drawBigTitle()
    drawCenteredText(math.floor(SCREEN_H * 0.75), "Тех.Работа", colors.error)
    gpu.setForeground(colors.text_main)
    gpu.setBackground(colors.bg_main)
end

local function drawMainMenu()
    clear()
    drawScreenBorder()
    if currentPlayer then
        local hello1 = "Добро пожаловать, "
        local hello2 = currentPlayer .. "!"
        local full1 = hello1 .. hello2
        local x1 = math.floor((SCREEN_W - unicode.len(full1))/2) + 2
        gpu.setForeground(colors.success)
        gpu.set(x1, 4, hello1)
        gpu.setForeground(colors.text_bright)
        gpu.set(x1 + unicode.len(hello1), 4, hello2)
        local balanceText = "Баланс: " .. string.format("%.2f", coinBalance) .. " ₵"
        gpu.setForeground(colors.text_bright)
        local balanceX = math.floor((SCREEN_W - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", emaBalance) .. " ۞")) / 2) + 1
        gpu.set(balanceX, 5, "Баланс: ")
        gpu.setForeground(colors.gold)
        gpu.set(balanceX + unicode.len("Баланс: "), 5, string.format("%.2f", coinBalance) .. " ₵")
        gpu.setForeground(colors.text_dim)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coinBalance) .. " ₵"), 5, " | ")
        gpu.setForeground(colors.tomato)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coinBalance) .. " ₵") + unicode.len(" | "), 5, "ЭМЫ: " .. string.format("%.2f", emaBalance) .. " ")
        if not playerAgreed then
            gpu.setForeground(colors.accent_light)
            if showShopDenied then
                drawCenteredText(7, "Доступ запрещён. Примите соглашение [Соглашение]", colors.error)
            else
                drawCenteredText(7, "Вы не приняли пользовательское соглашение! Нажмите [Соглашение]", colors.accent_light)
            end
        end
        for _, btn in pairs(menuButtons) do
            drawButton(btn)
        end
        drawBottomPanel()
    else
        drawWelcomeScreen()
    end
    drawTempMessage()
end

local function drawAccount(data)
    clear()
    drawScreenBorder()
    drawCenteredText(10, currentPlayer .. ":", colors.text_bright)
    local coin = data.balance or coinBalance
    local ema = data.emaBalance or emaBalance
    local balanceText = "Баланс: " .. string.format("%.2f", coin) .. " ₵"
    gpu.setForeground(colors.text_bright)
    local balanceX = math.floor((SCREEN_W - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")) / 2) + 1
    gpu.set(balanceX, 12, "Баланс: ")
    gpu.setForeground(colors.gold)
    gpu.set(balanceX + unicode.len("Баланс: "), 12, string.format("%.2f", coin) .. " ₵")
    gpu.setForeground(colors.text_dim)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " "), 12, " | ")
    gpu.setForeground(colors.tomato)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " ₵") + unicode.len(" | "), 12, "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")
    local transLabel = "Совершенно транзакций: "
    local transCount = tostring(data.transactions or 0)
    local fullTrans = transLabel .. transCount
    local transX = math.floor((SCREEN_W - unicode.len(fullTrans)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(transX, 13, transLabel)
    gpu.setForeground(colors.text_bright)
    gpu.set(transX + unicode.len(transLabel), 13, transCount)
    local regLabel = "Регистрация: "
    local regDate = data.regDate or "Неизвестно"
    local fullReg = regLabel .. regDate
    local regX = math.floor((SCREEN_W - unicode.len(fullReg)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(regX, 14, regLabel)
    gpu.setForeground(colors.text_bright)
    gpu.set(regX + unicode.len(regLabel), 14, regDate)
    local agreeLabel = "Соглашение: "
    local agreeStatus = (data.agreed or playerAgreed) and "ознакомлен" or "не ознакомлен"
    local agreeColor = (data.agreed or playerAgreed) and colors.text_bright or colors.error
    local fullAgree = agreeLabel .. agreeStatus
    local agreeX = math.floor((SCREEN_W - unicode.len(fullAgree)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(agreeX, 15, agreeLabel)
    gpu.setForeground(agreeColor)
    gpu.set(agreeX + unicode.len(agreeLabel), 15, agreeStatus)
    drawFlexButton(backButton)
    drawTempMessage()
end

local function drawAccountLoading()
    clear()
    drawScreenBorder()
    drawCenteredText(12, "Загрузка...", colors.text_main)
    drawFlexButton(backButton)
    drawTempMessage()
end

local function retryAccountAfterTokenRefresh()
    if not currentPlayer then return end
    modem.send(serverAddress, 0xffef, serialization.serialize({op="enter", name=currentPlayer}))
    local start = computer.uptime()
    while computer.uptime() - start < 3 do
        local ev = safeEventPull(0.3)
        if ev[1] == "modem_message" then
            local sender = ev[3]
            local data = ev[6]
            if sender == serverAddress then
                local success, msg = pcall(serialization.unserialize, data)
                if success and msg and msg.op == "welcome" and msg.token then
                    currentToken = msg.token
                    coinBalance = msg.balance or 0.0
                    emaBalance = msg.emaBalance or 0.0
                    playerAgreed = msg.agreed or false
                    alreadyAuthorized = true
                    currentScreen = "account_loading"
                    accountRequestTime = computer.uptime()
                    drawAccountLoading()
                    modem.send(serverAddress, 0xffef, serialization.serialize({
                        op = "getAccount", name = currentPlayer, token = currentToken
                    }))
                    return
                end
            end
        elseif ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            currentPlayer = nil
            currentToken = nil
            alreadyAuthorized = false
            currentScreen = "welcome"
            drawWelcomeScreen()
            return
        end
    end
    currentScreen = "menu"
    drawMainMenu()
end

local function goToAccount()
    if not currentToken then
        drawCenteredText(12, "Ошибка: нет авторизации", colors.error)
        return
    end
    currentScreen = "account_loading"
    accountRequestTime = computer.uptime()
    drawAccountLoading()
    modem.send(serverAddress, 0xffef, serialization.serialize({
        op = "getAccount", name = currentPlayer, token = currentToken
    }))
end

local function goToReport()
    currentScreen = "report"
    reportInput = ""
    drawReportScreen()
end

local function goToShop()
    currentScreen = "shop"
    drawShopMenu()
end

local function goToTop()
    currentScreen = "top"
    currentTopCategory = "balance"
    topPage = 1
    drawTopScreen()
end

local function goBackToMenu()
    showShopDenied = false
    currentScreen = "menu"
    drawMainMenu()
    updateSelectorDisplay(nil)
    safeSelectorSetSlot(0, nil)
    safeSelectorSetSlot(1, nil)
end

local function clearSelectorState()
    selectedItem = nil
    hoveredIndex = 0
    selectedIndex = 0
    updateSelectorDisplay(nil)
    safeSelectorSetSlot(0, nil)
    safeSelectorSetSlot(1, nil)
end

local function goToHelp()
    currentScreen = "agreement"
    drawAgreementScreen()
end

local function refreshAndAgree()
    if playerAgreed then
        goBackToMenu()
        return
    end
    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "agree",
            name = currentPlayer,
            token = currentToken
        }))
        drawCenteredText(20, "Отправка подтверждения...", colors.success)
    else
        goBackToMenu()
    end
end

-- ============================================================
-- ГЛАВНЫЙ ЦИКЛ МАГАЗИНА
-- ============================================================
local function main()
    drawWelcomeScreen()
    modem.send(serverAddress, 0xffef, serialization.serialize({op="register", password=ACCESS_PASSWORD}))
    while true do
        local ev = nextShopEvent(0.5)
        local e = ev[1]
        if currentPlayer then
            local pimPresent = isPlayerPhysicallyOnPim()
            if pimPresent == false then
                closePimSession()
                goto continue
            end
        end
        if currentScreen == "auth" and currentPlayer and not currentToken then
            local now = computer.uptime()
            if now - authLastSendTime >= AUTH_RETRY_INTERVAL then
                sendEnterRequest()
            end
            if now - authStartTime >= AUTH_NO_RESPONSE_NOTICE then
                drawTechWorkScreen()
            end
        end
        if currentScreen == "account_loading" then
            if computer.uptime() - accountRequestTime >= ACCOUNT_TIMEOUT then
                retryAccountAfterTokenRefresh()
            end
        end
        if currentPlayer and (e == "touch" or e == "scroll" or e == "key_down") then
            local inputPlayer
            if e == "touch" or e == "scroll" then
                inputPlayer = ev[6]
            elseif e == "key_down" then
                inputPlayer = ev[5]
            end
            if not isPimOwner(inputPlayer) then
                goto continue
            end
        end
        if e == "key_down" and tonumber(ev[3]) == 7 then
            AdminUpdate.openPanel(ev[5])
            goto continue
        end
        if e == "touch" then
            local x, y = ev[3], ev[4]
            if showSellPopup and currentScreen == "sell_scan" then
                local popupWidth = 45
                local popupHeight = 11
                local popupX = math.floor((SCREEN_W - popupWidth) / 2)
                local popupY = math.floor((SCREEN_H - popupHeight) / 2)
                local yesBtn = {x=popupX+5, y=popupY+8, xs=15, ys=1}
                local noBtn  = {x=popupX+popupWidth-18, y=popupY+8, xs=14, ys=1}
                if isButtonClicked(yesBtn, x, y) then
                    performSell()
                elseif isButtonClicked(noBtn, x, y) then
                    showSellPopup = false
                    drawSellScanScreen()
                elseif not (x >= popupX and x < popupX + popupWidth and y >= popupY and y < popupY + popupHeight) then
                    showSellPopup = false
                    drawSellScanScreen()
                end
                goto continue
            elseif showInsufficientPopup then
                local popupWidth = 55
                local popupHeight = 12
                local popupX = math.floor((SCREEN_W - popupWidth) / 2)
                local popupY = math.floor((SCREEN_H - popupHeight) / 2)
                local okBtnText = "[ ПОНЯТНО ]"
                local okBtnWidth = unicode.len(okBtnText) + 2
                local okBtn = {
                    x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                    y = popupY+9,
                    xs = okBtnWidth,
                    ys = 1
                }
                if isButtonClicked(okBtn, x, y) then
                    showInsufficientPopup = false
                    currentScreen = "shop_buy"
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                end
                goto continue
            elseif showPartialPopup then
                local popupWidth = 55
                local popupHeight = 10
                local popupX = math.floor((SCREEN_W - popupWidth) / 2)
                local popupY = math.floor((SCREEN_H - popupHeight) / 2)
                local okBtnText = "[ ПРИНЯТЬ ]"
                local okBtnWidth = unicode.len(okBtnText) + 2
                local okBtn = {
                    x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                    y = popupY+7,
                    xs = okBtnWidth,
                    ys = 1
                }
                if isButtonClicked(okBtn, x, y) then
                    showPartialPopup = false
                    currentScreen = "shop_buy"
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                end
                goto continue
            elseif showInventoryFullPopup then
                local popupWidth = 55
                local popupHeight = 10
                local popupX = math.floor((SCREEN_W - popupWidth) / 2)
                local popupY = math.floor((SCREEN_H - popupHeight) / 2)
                local okBtnText = "[ ПОНЯТНО ]"
                local okBtnWidth = unicode.len(okBtnText) + 2
                local okBtn = {
                    x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                    y = popupY+7,
                    xs = okBtnWidth,
                    ys = 1
                }
                if isButtonClicked(okBtn, x, y) then
                    showInventoryFullPopup = false
                    currentScreen = "shop_buy"
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                end
                goto continue
            elseif currentScreen == "shop_buy" or currentScreen == "shop_sell" then
                if currentShopMode == "buy" then
                    if stockFilterOpen then
                        if isButtonClicked(stockAvailableButton, x, y) then
                            applyStockFilter("available")
                            goto continue
                        elseif isButtonClicked(stockAllButton, x, y) then
                            applyStockFilter("all")
                            goto continue
                        elseif isButtonClicked(stockFilterButton, x, y) then
                            stockFilterOpen = false
                            drawBuyButtons()
                            goto continue
                        else
                            stockFilterOpen = false
                            drawBuyButtons()
                        end
                    elseif isButtonClicked(stockFilterButton, x, y) then
                        stockFilterOpen = true
                        drawBuyButtons()
                        goto continue
                    end
                end
                if y >= 7 and y <= 6 + visibleRows and x >= 2 and x <= SCREEN_W - 3 then
                    local relativeRow = y - 6
                    local clickedIndex = listScroll + relativeRow - 1
                    local item = filteredItems[clickedIndex]
                    if item and (currentShopMode ~= "buy" or item.qty > 0) then
                        selectedIndex = clickedIndex
                        selectedItem = item
                        hoveredIndex = 0
                        updateSelectorDisplay(selectedItem)
                        drawBuyItemsList()
                        drawBuyButtons()
                    end
                    goto continue
                end
                if x >= SCREEN_W - 2 and y >= 7 and y <= 6 + visibleRows then
                    local total = #filteredItems
                    if total > visibleRows then
                        local clickPos = y - 6
                        listScroll = math.floor((clickPos - 1) * (total - visibleRows) / visibleRows) + 1
                        drawBuyItemsList()
                    end
                    goto continue
                end
                if y == 3 and x >= math.floor(SCREEN_W / 2) - 12 and x <= math.floor(SCREEN_W / 2) + 13 then
                    searchActive = true
                    searchInput = shopSearch
                    drawSearchBar()
                    goto continue
                end
                if y == 3 and x >= math.floor(SCREEN_W / 2) + 14 and x <= math.floor(SCREEN_W / 2) + 26 then
                    shopSearch = ""
                    searchInput = ""
                    searchActive = false
                    listScroll = 1
                    drawSearchBar()
                    drawBuyItemsList()
                    goto continue
                end
                if isButtonClicked(backButton, x, y) then
                    currentScreen = "shop"
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    updateSelectorDisplay(nil)
                    drawShopMenu()
                    goto continue
                end
                if isButtonClicked(nextButton, x, y) then
                    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
                        if currentShopMode == "buy" then
                            local needCoin = selectedItem.priceCoin or 0
                            local needEma = selectedItem.priceEma or 0
                            if (needCoin > 0 and coinBalance < needCoin) or (needEma > 0 and emaBalance < needEma) then
                                showInsufficientPopup = true
                                insufficientBalanceCoin = coinBalance
                                insufficientBalanceEma = emaBalance
                                drawBuyStatic()
                                drawBuyItemsList()
                                drawBuyButtons()
                                drawInsufficientPopup()
                                goto continue
                            end
                            goToPurchase(selectedItem)
                        else
                            goToSellConfirm(selectedItem)
                        end
                    end
                    goto continue
                end
                if searchActive then
                    shopSearch = searchInput
                    searchActive = false
                    listScroll = 1
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    drawSearchBar()
                    drawBuyItemsList()
                    drawBuyButtons()
                    goto continue
                end
            elseif currentScreen == "purchase" then
                if (y >= SCREEN_H - 1 and y <= SCREEN_H - 1) and (x >= math.floor(SCREEN_W / 2) - 18 and x <= math.floor(SCREEN_W / 2) - 8) then
                    if currentShopMode == "buy" then
                        currentScreen = "shop_buy"
                        drawBuyStatic()
                        drawBuyItemsList()
                        drawBuyButtons()
                    else
                        currentScreen = "shop_sell"
                        drawBuyStatic()
                        drawBuyItemsList()
                        drawBuyButtons()
                    end
                elseif (y >= SCREEN_H - 1 and y <= SCREEN_H - 1) and (x >= math.floor(SCREEN_W / 2) + 6 and x <= math.floor(SCREEN_W / 2) + 16) then
                    performBuy()
                end
                local startX = math.floor((SCREEN_W - 15) / 2)
                local startY = math.floor(SCREEN_H * 0.35)
                local btnW = 3
                local btnH = 1
                local spacing = 2
                local keys = {
                    {"1","2","3"},
                    {"4","5","6"},
                    {"7","8","9"},
                    {"<","0","C"}
                }
                for row = 1, 4 do
                    for col = 1, 3 do
                        local bx = startX + (col-1)*(btnW + spacing)
                        local by = startY + (row-1)*(btnH + 1)
                        if x >= bx and x < bx+btnW and y >= by and y < by+btnH then
                            handleQuantityButtonClick(keys[row][col])
                            break
                        end
                    end
                end
            elseif currentScreen == "sell_scan" then
                if isButtonClicked(backButton, x, y) then
                    currentScreen = "shop_sell"
                    showSellPopup = false
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                elseif y == math.floor(SCREEN_H * 0.35) + 2 and x >= math.floor(SCREEN_W / 2) - 12 and x <= math.floor(SCREEN_W / 2) + 12 then
                    drawCenteredText(17, "Сканирование...", colors.accent_light)
                    os.sleep(0.6)
                    foundAmount = scanPlayerInventory(sellConfirmItem.internalName, sellConfirmItem.damage or 0)
                    if foundAmount > 0 then
                        showSellPopup = true
                        drawSellScanScreen()
                    else
                        drawCenteredText(17, "Предмет не найден!", colors.error)
                        os.sleep(0.8)
                        drawSellScanScreen()
                    end
                end
            elseif currentScreen == "menu" then
                for name, btn in pairs(menuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "shop" then
                            if playerAgreed then
                                goToShop()
                            else
                                showShopDenied = true
                                drawMainMenu()
                            end
                        elseif name == "account" then
                            showShopDenied = false
                            goToAccount()
                        elseif name == "top" then
                            goToTop()
                        end
                        break
                    end
                end
                if y == SCREEN_H then
                    if x >= 4 and x <= 25 then
                        showShopDenied = false
                        goToReport()
                    elseif x >= math.floor(SCREEN_W / 2) - 10 and x <= math.floor(SCREEN_W / 2) + 10 then
                        showShopDenied = false
                        goToHelp()
                    elseif x >= SCREEN_W - 20 and x <= SCREEN_W - 4 then
                        currentScreen = "feedbacks"
                        loadFeedbacksFromServer()
                        drawFeedbacksList()
                    end
                end
            elseif currentScreen == "top" then
                -- Обработка клика по категориям
                if handleTopCategoryClick(x, y) then
                    goto continue
                end
                -- Пагинация
                local topList = getTopPlayers(currentTopCategory, topPerPage * 3)
                local totalPages = math.max(1, math.ceil(#topList / topPerPage))
                if isButtonClicked({x = math.floor(SCREEN_W / 2) - 20, y = SCREEN_H - 1, xs = 8, ys = 1}, x, y) and topPage > 1 then
                    topPage = topPage - 1
                    drawTopScreen()
                    goto continue
                end
                if isButtonClicked({x = math.floor(SCREEN_W / 2) + 12, y = SCREEN_H - 1, xs = 8, ys = 1}, x, y) and topPage < totalPages then
                    topPage = topPage + 1
                    drawTopScreen()
                    goto continue
                end
                if isButtonClicked({x = math.floor(SCREEN_W / 2) - 6, y = SCREEN_H - 1, xs = 12, ys = 1}, x, y) then
                    goBackToMenu()
                    goto continue
                end
            elseif currentScreen == "agreement" then
                local btnText = "[ ПОНЯТНО ]"
                local btnW = unicode.len(btnText) + 4
                local btnX = math.floor((SCREEN_W - btnW)/2) + 2
                if y == SCREEN_H - 3 and x >= btnX and x <= btnX + btnW then
                    refreshAndAgree()
                end
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                end
            elseif currentScreen == "account" or currentScreen == "account_loading" then
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                end
            elseif currentScreen == "shop" then
                for name, btn in pairs(shopMenuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "buy" then
                            goToBuy()
                        elseif name == "sell" then
                            goToSell()
                        end
                        break
                    end
                end
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                end
            elseif currentScreen == "report" then
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                elseif canSendReport() then
                    local sendBtn = {x=math.floor(SCREEN_W / 2) - 8, y=14, xs=17, ys=1}
                    if isButtonClicked(sendBtn, x, y) and reportInput ~= "" then
                        if currentToken then
                            modem.send(serverAddress, 0xffef, serialization.serialize({
                                op = "report",
                                name = currentPlayer,
                                token = currentToken,
                                text = reportInput,
                                time = getRealTimeString()
                            }))
                        end
                        lastReportTime = getRealTimestamp()
                        drawCenteredText(18, "Сообщение успешно отправлено! Ожидайте ответа.", colors.success)
                        os.sleep(0.8)
                        goBackToMenu()
                    end
                end
            elseif currentScreen == "feedbacks" then
                if isButtonClicked({x=5, y=SCREEN_H - 1, xs=11, ys=1}, x, y) then
                    currentScreen = "menu"
                    drawMainMenu()
                    goto continue
                end
                if isButtonClicked({x=math.floor(SCREEN_W / 2) - 7, y=SCREEN_H - 1, xs=14, ys=1}, x, y) then
                    if playerHasFeedback then
                        showTempMessage("Вы уже оставляли отзыв!", 2)
                    else
                        feedbackInput = ""
                        feedbackRating = 0
                        feedbackEditMode = true
                        drawFeedbackInputScreen()
                    end
                    goto continue
                end
                if isButtonClicked({x=SCREEN_W - 30, y=SCREEN_H - 1, xs=7, ys=1}, x, y) and feedbacksPage > 1 then
                    feedbacksPage = feedbacksPage - 1
                    drawFeedbacksList()
                    goto continue
                end
                if isButtonClicked({x=SCREEN_W - 20, y=SCREEN_H - 1, xs=7, ys=1}, x, y) and feedbacksPage < feedbacksTotalPages then
                    feedbacksPage = feedbacksPage + 1
                    drawFeedbacksList()
                    goto continue
                end
            elseif currentScreen == "feedback_input" then
                local starY = 12
                local starX = math.floor(SCREEN_W / 2) - 10
                for i = 1, 5 do
                    local sx = starX + (i - 1) * 3
                    if x >= sx and x <= sx + 2 and y >= starY and y <= starY + 1 then
                        if feedbackRating == i then
                            feedbackRating = 0
                        else
                            feedbackRating = i
                        end
                        drawFeedbackInputScreen()
                        goto continue
                    end
                end
                if isButtonClicked({x=math.floor(SCREEN_W / 2) - 18, y=SCREEN_H - 1, xs=12, ys=1}, x, y) then
                    feedbackEditMode = false
                    feedbackInput = ""
                    feedbackRating = 0
                    currentScreen = "feedbacks"
                    drawFeedbacksList()
                    goto continue
                end
                if isButtonClicked({x=math.floor(SCREEN_W / 2) + 6, y=SCREEN_H - 1, xs=15, ys=1}, x, y) and feedbackInput ~= "" then
                    if currentToken then
                        modem.send(serverAddress, 0xffef, serialization.serialize({
                            op = "add_feedback",
                            name = currentPlayer,
                            token = currentToken,
                            text = feedbackInput,
                            rating = feedbackRating,
                            time = getRealTimeString()
                        }))
                        showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                    end
                    feedbackEditMode = false
                    feedbackInput = ""
                    feedbackRating = 0
                    currentScreen = "feedbacks"
                    drawFeedbacksList()
                    goto continue
                end
            end
        elseif e == "scroll" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
            local direction = ev[5]
            local x = ev[3]
            local y = ev[4]
            if x >= 2 and x <= SCREEN_W - 3 and y >= 7 and y <= 6 + visibleRows then
                if direction == -1 then
                    smoothScroll(1)
                elseif direction == 1 then
                    smoothScroll(-1)
                end
            end
        elseif e == "mouse_move" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
            local x, y = ev[3], ev[4]
            if y >= 7 and y <= 6 + visibleRows and x >= 2 and x <= SCREEN_W - 3 then
                local rel = y - 6
                local newHover = listScroll + rel - 1
                if newHover <= #filteredItems and newHover ~= hoveredIndex then
                    hoveredIndex = newHover
                    drawBuyItemsList()
                end
            else
                if hoveredIndex ~= 0 then
                    hoveredIndex = 0
                    drawBuyItemsList()
                end
            end
        elseif e == "key_down" and currentScreen == "report" and canSendReport() then
            local ch = ev[3]
            if ch == 13 then
                drawReportScreen()
            elseif ch == 8 then
                reportInput = unicode.sub(reportInput, 1, -2)
                drawReportScreen()
            elseif ch >= 32 then
                reportInput = reportInput .. unicode.char(ch)
                drawReportScreen()
            end
        elseif e == "key_down" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") and stockFilterOpen then
            local ch = ev[3]
            if ch == 27 then
                stockFilterOpen = false
                drawBuyButtons()
            end
            goto continue
        elseif e == "key_down" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") and searchActive then
            local ch = ev[3]
            if ch == 13 then
                shopSearch = searchInput
                searchActive = false
                listScroll = 1
                selectedIndex = 0
                selectedItem = nil
                hoveredIndex = 0
                drawSearchBar()
                drawBuyItemsList()
                drawBuyButtons()
            elseif ch == 8 then
                searchInput = unicode.sub(searchInput, 1, -2)
                shopSearch = searchInput
                listScroll = 1
                drawSearchBar()
                drawBuyItemsList()
            elseif ch >= 32 then
                searchInput = searchInput .. unicode.char(ch)
                shopSearch = searchInput
                listScroll = 1
                drawSearchBar()
                drawBuyItemsList()
            end
            goto continue
        elseif e == "key_down" and currentScreen == "feedback_input" and feedbackEditMode then
            local ch = ev[3]
            if ch == 13 then
                if feedbackInput ~= "" and currentToken then
                    modem.send(serverAddress, 0xffef, serialization.serialize({
                        op = "add_feedback",
                        name = currentPlayer,
                        token = currentToken,
                        text = feedbackInput,
                        rating = feedbackRating,
                        time = getRealTimeString()
                    }))
                    showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                end
                feedbackEditMode = false
                feedbackInput = ""
                feedbackRating = 0
                currentScreen = "feedbacks"
                drawFeedbacksList()
            elseif ch == 8 then
                feedbackInput = unicode.sub(feedbackInput, 1, -2)
                drawFeedbackInputScreen()
            elseif ch >= 32 then
                if unicode.len(feedbackInput) < 200 then
                    feedbackInput = feedbackInput .. unicode.char(ch)
                    drawFeedbackInputScreen()
                end
            end
            goto continue
        elseif e == "player_on" or e == "pim" or e == "pim_player_enter" then
            local playerName = trimPlayerName(ev[2] or "")
            if playerName == "" then
                goto continue
            end
            if currentPlayer and samePlayerName(playerName, currentPlayer) then
                if currentToken then
                    alreadyAuthorized = true
                    -- Обновление статистики посещений
                    updatePlayerStat(currentPlayer, "visits")
                    if currentScreen == "auth" or currentScreen == "account_loading" then
                        currentScreen = "menu"
                        drawMainMenu()
                    end
                elseif currentScreen ~= "auth" then
                    currentScreen = "auth"
                    authStartTime = computer.uptime()
                    authLastSendTime = 0
                    drawAuthScreen()
                    sendEnterRequest()
                end
                goto continue
            end
            currentPlayer = playerName
            PimPresence.missCount = 0
            PimPresence.lastPositive = computer.uptime()
            currentToken = nil
            alreadyAuthorized = false
            coinBalance = 0.0
            emaBalance = 0.0
            playerAgreed = false
            currentScreen = "auth"
            authStartTime = computer.uptime()
            authLastSendTime = 0
            drawAuthScreen()
            sendEnterRequest()
        elseif e == "player_off" or e == "pim_player_leave" then
            local leavingPlayer = trimPlayerName(ev[2] or "")
            if currentPlayer and leavingPlayer ~= "" and not samePlayerName(leavingPlayer, currentPlayer) then
                goto continue
            end
            closePimSession()
        elseif e == "modem_message" then
            local sender = ev[3]
            local data = ev[6]
            if sender == serverAddress then
                local success, msg = pcall(serialization.unserialize, data)
                if success and msg then
                    if msg.op == "welcome" and msg.token then
                        currentToken = msg.token
                        authStartTime = 0
                        authLastSendTime = 0
                        authTechWork = false
                        coinBalance = msg.balance or 0.0
                        emaBalance = msg.emaBalance or 0.0
                        playerTransactions = msg.transactions or 0
                        playerRegDate = msg.regDate or ""
                        playerAgreed = msg.agreed or false
                        alreadyAuthorized = true
                        -- Обновление статистики посещений
                        updatePlayerStat(currentPlayer, "visits")
                        if selector then
                            modem.send(serverAddress, 0xffef, serialization.serialize({
                                op = "selector_status",
                                name = currentPlayer,
                                token = currentToken,
                                available = true
                            }))
                        end
                        if currentScreen == "auth" or currentScreen == "account_loading" then
                            currentScreen = "menu"
                            drawMainMenu()
                        end
                    elseif msg.op == "error" then
                        if currentScreen == "auth" then
                            drawTechWorkScreen()
                        end
                    elseif msg.op == "accountData" then
                        if msg.error then
                            retryAccountAfterTokenRefresh()
                        else
                            if currentScreen == "account_loading" then
                                currentScreen = "account"
                                playerAgreed = msg.data.agreed or false
                                drawAccount(msg.data)
                            end
                        end
                    elseif msg.op == "agree" then
                        if msg.success then
                            playerAgreed = true
                            showShopDenied = false
                            drawCenteredText(20, "Спасибо! Теперь вам доступен магазин.", colors.success)
                            os.sleep(0.8)
                            drawMainMenu()
                            currentScreen = "menu"
                        elseif msg.error and msg.message == "Токен устарел" then
                            drawCenteredText(20, "Сессия устарела. Обновление...", colors.accent_light)
                            os.sleep(1)
                            modem.send(serverAddress, 0xffef, serialization.serialize({op="enter", name=currentPlayer}))
                            local start = os.clock()
                            local refreshed = false
                            while os.clock() - start < 3 do
                                local evt = safeEventPull(0.3)
                                if evt[1] == "modem_message" then
                                    local s, d = evt[3], evt[6]
                                    if s == serverAddress then
                                        local ok, m = pcall(serialization.unserialize, d)
                                        if ok and m and m.op == "welcome" and m.token then
                                            currentToken = m.token
                                            coinBalance = m.balance or 0.0
                                            emaBalance = m.emaBalance or 0.0
                                            playerAgreed = m.agreed or false
                                            refreshed = true
                                            break
                                        end
                                    end
                                elseif evt[1] == "player_off" or evt[1] == "pim_player_leave" then
                                    break
                                end
                            end
                            if refreshed then
                                modem.send(serverAddress, 0xffef, serialization.serialize({
                                    op = "agree",
                                    name = currentPlayer,
                                    token = currentToken
                                }))
                                drawCenteredText(20, "Повторная отправка...", colors.success)
                            else
                                drawCenteredText(20, "Не удалось обновить сессию", colors.error)
                                os.sleep(2)
                                drawMainMenu()
                                currentScreen = "menu"
                            end
                        else
                            drawCenteredText(20, "Ошибка: " .. (msg.message or "неизвестная"), colors.error)
                            os.sleep(2)
                            drawMainMenu()
                            currentScreen = "menu"
                        end
                    elseif msg.op == "add_buy_item" then
                        local ok, err = pcall(function()
                            local buyItems = dofile("/home/buy_items.lua")
                            if type(buyItems) ~= "table" then buyItems = {} end
                            local damage = tonumber(msg.damage) or 0
                            local priceCoin = tonumber(msg.price_coin)
                            if priceCoin == nil then priceCoin = tonumber(msg.price) or 0 end
                            local priceEma = tonumber(msg.price_ema) or 0
                            local msgNbtHash = msg.nbt_hash or msg.nbtHash or msg.nbt
                            if msgNbtHash ~= nil and tostring(msgNbtHash) == "" then msgNbtHash = nil end
                            local found = false
                            for _, item in ipairs(buyItems) do
                                local itemNbtHash = item.nbt_hash or item.nbtHash or item.nbt
                                if itemNbtHash ~= nil and tostring(itemNbtHash) == "" then itemNbtHash = nil end
                                if item.internalName == msg.internalName
                                    and (item.damage or 0) == damage
                                    and tostring(itemNbtHash or "") == tostring(msgNbtHash or "")
                                then
                                    item.displayName = msg.displayName
                                    item.price_coin = priceCoin
                                    item.price_ema = priceEma
                                    item.nbt_hash = msgNbtHash
                                    item.nbtHash = nil
                                    item.nbt = nil
                                    if damage ~= 0 then item.damage = damage else item.damage = nil end
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                local newItem = {
                                    internalName = msg.internalName,
                                    displayName = msg.displayName,
                                    price_coin = priceCoin,
                                    price_ema = priceEma,
                                    nbt_hash = msgNbtHash,
                                }
                                if damage ~= 0 then newItem.damage = damage end
                                table.insert(buyItems, newItem)
                            end
                            local file = assert(io.open("/home/buy_items.lua", "w"))
                            file:write("return " .. serialization.serialize(buyItems))
                            file:close()
                            buyItemsData = dofile("/home/buy_items.lua")
                            buyItemMap = {}
                            for _, item in ipairs(buyItemsData) do
                                local dmg = item.damage or 0
                                local nbt = item.nbt_hash or item.nbtHash or item.nbt
                                local key = item.internalName .. ":" .. dmg .. "|nbt=" .. tostring(nbt or "")
                                buyItemMap[key] = item
                            end
                            if currentScreen == "shop_buy" then
                                loadBuyItems()
                                drawBuyStatic()
                                drawBuyItemsList()
                                drawBuyButtons()
                            end
                        end)
                        if ok then
                            modem.send(sender, 0xffef, serialization.serialize({op = "add_buy_item_response", success = true}))
                            showTempMessage("✅ Предмет добавлен: " .. msg.displayName, 10)
                        else
                            modem.send(sender, 0xffef, serialization.serialize({op = "add_buy_item_response", success = false, error = tostring(err)}))
                            showTempMessage("❌ Ошибка добавления: " .. tostring(err), 10)
                        end
                        goto continue
                    elseif msg.op == "add_buy_item_response" then
                        if msg.success then
                            print("Предмет успешно добавлен на сервере")
                        else
                            print("Ошибка добавления предмета: " .. (msg.error or "неизвестная"))
                        end
                    elseif msg.op == "reload_buy_items" then
                        buyItemsData = dofile("/home/buy_items.lua")
                        buyItemMap = {}
                        for _, item in ipairs(buyItemsData) do
                            local dmg = item.damage or 0
                            local nbt = item.nbt_hash or item.nbtHash or item.nbt
                            local key = item.internalName .. ":" .. dmg .. "|nbt=" .. tostring(nbt or "")
                            buyItemMap[key] = item
                        end
                        if currentScreen == "shop_buy" then
                            loadBuyItems()
                            drawBuyStatic()
                            drawBuyItemsList()
                            drawBuyButtons()
                        end
                        goto continue
                    elseif msg.op == "feedbacks_list" then
                        feedbacks = msg.feedbacks or {}
                        playerHasFeedback = msg.hasFeedback or false
                        feedbacksPage = 1
                        if currentScreen == "feedbacks" then
                            drawFeedbacksList()
                        end
                        goto continue
                    elseif msg.op == "add_feedback_response" then
                        if msg.success then
                            showTempMessage("✅ Отзыв добавлен!", 10)
                            loadFeedbacksFromServer()
                        else
                            showTempMessage("❌ Ошибка: " .. (msg.error or "неизвестная"), 10)
                        end
                        goto continue
                    end
                end
            end
        end
        ::continue::
    end
end

-- ============================================================
-- АДМИН-ПАНЕЛЬ
-- ============================================================
AdminUpdate = AdminUpdate or {}
AdminUpdate.CONFIG_PATH = "/admin_config.cfg"
AdminUpdate.FLAG_PATH = "/.just_updated"
AdminUpdate.HOME = "/home"
AdminUpdate.DEFAULT_PASSWORD = "yVGF7wT"
AdminUpdate.FRAME = {tl="╔", tr="╗", bl="╚", br="╝", h="═", v="║"}
AdminUpdate.FILES = {
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/buy_items.lua",  path = "/home/buy_items.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/shop_items.lua", path = "/home/shop_items.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/pimserver.lua",  path = "/home/pimserver.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/primarket.lua",  path = "/home/primarket.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/agreement.lua",  path = "/home/agreement.lua" },
}

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

function AdminUpdate.setLine(x, y, w, value, color)
    if color then gpu.setForeground(color) end
    local t = tostring(value or "")
    local len = AdminUpdate.ulen(t)
    if len > w then
        local outText, count = "", 0
        for c in t:gmatch("[%z\1-\127\192-\255][\128-\191]*") do
            count = count + 1
            if count <= w then outText = outText .. c else break end
        end
        t, len = outText, w
    end
    gpu.set(x, y, t .. string.rep(" ", math.max(0, w - len)))
end

function AdminUpdate.drawFrame(x, y, w, h)
    local f = AdminUpdate.FRAME
    gpu.set(x, y, f.tl .. string.rep(f.h, w - 2) .. f.tr)
    for i = 1, h - 2 do
        gpu.set(x, y + i, f.v .. string.rep(" ", w - 2) .. f.v)
    end
    gpu.set(x, y + h - 1, f.bl .. string.rep(f.h, w - 2) .. f.br)
end

function AdminUpdate.drawPassword(password, statusText, statusColor)
    gpu.setResolution(SCREEN_W, SCREEN_H)
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    local fw, fh = 60, 15
    local fx = math.floor((SCREEN_W - fw) / 2) + 1
    local fy = math.floor((SCREEN_H - fh) / 2) + 1
    local title = "АДМИН-ПАНЕЛЬ"
    gpu.setForeground(colors.text_bright)
    gpu.set(fx + math.floor((fw - unicode.len(title)) / 2), fy - 1, title)
    gpu.setForeground(colors.border_accent)
    AdminUpdate.drawFrame(fx, fy, fw, fh)
    drawCenteredText(fy + 3, "Введите пароль администратора", colors.text_bright)
    local fieldW = 34
    local fieldX = fx + math.floor((fw - fieldW) / 2)
    local fieldY = fy + 6
    gpu.setBackground(colors.bg_button)
    gpu.fill(fieldX, fieldY, fieldW, 1, " ")
    gpu.setForeground(colors.accent_light)
    local masked = string.rep("*", unicode.len(password or ""))
    if unicode.len(masked) > fieldW - 2 then
        masked = unicode.sub(masked, -(fieldW - 2))
    end
    gpu.set(fieldX + 1, fieldY, masked .. "_")
    gpu.setBackground(colors.bg_main)
    if statusText and statusText ~= "" then
        drawCenteredText(fy + 9, statusText, statusColor or colors.text_main)
    else
        drawCenteredText(fy + 9, "Enter - войти   Esc - назад", colors.text_dim)
    end
    drawCenteredText(fy + 11, "Пароль на экране не отображается", colors.text_dim)
end

function AdminUpdate.redrawShop()
    if currentScreen == "welcome" then
        drawWelcomeScreen()
    elseif currentScreen == "auth" then
        drawAuthScreen()
    elseif currentScreen == "menu" then
        drawMainMenu()
    elseif currentScreen == "shop" then
        drawShopMenu()
    elseif currentScreen == "shop_buy" or currentScreen == "shop_sell" then
        drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
    elseif currentScreen == "purchase" then
        drawPurchaseScreen()
        if showInsufficientPopup then drawInsufficientPopup() end
        if showPartialPopup then drawPartialPopup() end
        if showInventoryFullPopup then drawInventoryFullPopup() end
    elseif currentScreen == "sell_scan" then
        drawSellScanScreen()
    elseif currentScreen == "account" then
        drawAccount({balance=coinBalance, emaBalance=emaBalance, transactions=playerTransactions, regDate=playerRegDate, agreed=playerAgreed})
    elseif currentScreen == "account_loading" then
        drawAccountLoading()
    elseif currentScreen == "report" then
        drawReportScreen()
    elseif currentScreen == "feedbacks" then
        drawFeedbacksList()
    elseif currentScreen == "feedback_input" then
        drawFeedbackInputScreen()
    elseif currentScreen == "top" then
        drawTopScreen()
    elseif currentScreen == "agreement" then
        drawAgreementScreen()
    else
        drawWelcomeScreen()
    end
end

function AdminUpdate.drawInterface()
    local mw, mh = gpu.maxResolution()
    gpu.setResolution(mw >= SCREEN_W and SCREEN_W or mw, mh >= SCREEN_H and SCREEN_H or mh)
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    local fw, fh = 60, 15
    local fx = math.floor((SCREEN_W - fw) / 2) + 1
    local fy = math.floor((SCREEN_H - fh) / 2) + 1
    local title = "ОБНОВЛЕНИЕ"
    gpu.setForeground(colors.text_bright)
    gpu.set(fx + math.floor((fw - AdminUpdate.ulen(title)) / 2), fy - 1, title)
    gpu.setForeground(colors.border_accent)
    AdminUpdate.drawFrame(fx, fy, fw, fh)
    gpu.setForeground(colors.text_bright)
    gpu.set(1, SCREEN_H, "By KaRMa__")
    return fx, fy, fw, fh
end

function AdminUpdate.drawBar(x, y, w, p)
    p = math.max(0, math.min(1, tonumber(p) or 0))
    local inner = w - 2
    local filled = math.floor(inner * p)
    gpu.setForeground(colors.text_bright)
    gpu.set(x, y, "[" .. string.rep("█", filled) .. string.rep(" ", inner - filled) .. "]")
end

function AdminUpdate.showStatus(fx, fy, fw, fh, l1, l2, l3, color)
    local cy = fy + math.floor(fh / 2) - 1
    AdminUpdate.setLine(fx + 2, cy,     fw - 4, l1 or "", color)
    AdminUpdate.setLine(fx + 2, cy + 1, fw - 4, l2 or "", color)
    AdminUpdate.setLine(fx + 2, cy + 2, fw - 4, l3 or "", color)
end

function AdminUpdate.downloadFile(url, path)
    local ok = os.execute('wget -fq "' .. url .. '" "' .. path .. '"')
    if not (ok and fs.exists(path) and fs.size(path) > 0) then
        os.execute('wget -f "' .. url .. '" "' .. path .. '"')
    end
    return fs.exists(path) and fs.size(path) > 0
end

function AdminUpdate.setupAutorun()
    if not fs.exists("/autorun") then fs.makeDirectory("/autorun") end
    local f = io.open("/autorun/99_start.lua", "w")
    if not f then return false end
    f:write([[
local fs = require("filesystem")
os.sleep(2)
if fs.exists("/.just_updated") then
    fs.remove("/.just_updated")
    if fs.exists("/home/primarket.lua") then
        os.execute("/home/primarket.lua")
    end
end
if fs.exists("/loader.lua") then
    loadfile("/loader.lua")("watch")
end
]])
    f:close()
    return true
end

function AdminUpdate.run()
    local fx, fy, fw, fh = AdminUpdate.drawInterface()
    AdminUpdate.drawBar(fx, fy + fh + 1, fw, 0)
    local total, done = #AdminUpdate.FILES, 0
    for _, file in ipairs(AdminUpdate.FILES) do
        fx, fy, fw, fh = AdminUpdate.drawInterface()
        AdminUpdate.drawBar(fx, fy + fh + 1, fw, done / total)
        AdminUpdate.showStatus(fx, fy, fw, fh, "Идёт скачивание:", fs.name(file.path), "Скачано: " .. done .. "/" .. total, colors.text_bright)
        local success = false
        for attempt = 1, 2 do
            if AdminUpdate.downloadFile(file.url, file.path) then success = true break end
            os.sleep(1)
        end
        fx, fy, fw, fh = AdminUpdate.drawInterface()
        if success then
            done = done + 1
            AdminUpdate.showStatus(fx, fy, fw, fh, "Готово:", fs.name(file.path), "Скачано: " .. done .. "/" .. total, colors.success)
        else
            AdminUpdate.showStatus(fx, fy, fw, fh, "Ошибка:", fs.name(file.path), "Скачано: " .. done .. "/" .. total, colors.error)
        end
        AdminUpdate.drawBar(fx, fy + fh + 1, fw, done / total)
        os.sleep(0.3)
    end
    if done == total then
        AdminUpdate.setupAutorun()
        local flag = io.open(AdminUpdate.FLAG_PATH, "w")
        if flag then flag:write("1"); flag:close() end
        for i = 5, 1, -1 do
            fx, fy, fw, fh = AdminUpdate.drawInterface()
            AdminUpdate.drawBar(fx, fy + fh + 1, fw, 1)
            AdminUpdate.showStatus(fx, fy, fw, fh, "Обновление завершено!", "", "Перезагрузка через " .. i .. " сек...", colors.success)
            os.sleep(1)
        end
        computer.shutdown(true)
        return true
    end
    fx, fy, fw, fh = AdminUpdate.drawInterface()
    AdminUpdate.drawBar(fx, fy + fh + 1, fw, done / total)
    AdminUpdate.showStatus(fx, fy, fw, fh, "Ошибка при обновлении!", "", "Перезагрузка не выполнена.", colors.error)
    os.sleep(3)
    return false
end

function AdminUpdate.openPanel(triggerPlayer)
    local cfg = AdminUpdate.loadConfig()
    local adminName = trimPlayerName(triggerPlayer or "")
    if not AdminUpdate.isAdmin(adminName, cfg) then
        local oldScreen = currentScreen
        AdminUpdate.drawPassword("", "ДОСТУП ЗАПРЕЩЁН", colors.error)
        os.sleep(1.5)
        currentScreen = oldScreen
        AdminUpdate.redrawShop()
        return false
    end
    local previousScreen = currentScreen
    local password = ""
    AdminUpdate.drawPassword(password, "", colors.text_main)
    while true do
        local ev = safeEventPull(0.25)
        local e = ev[1]
        if e == "player_off" or e == "pim_player_leave" then
            local leavingPlayer = trimPlayerName(extractEventPlayerName(ev) or ev[2] or "")
            if currentPlayer and (leavingPlayer == "" or samePlayerName(leavingPlayer, currentPlayer)) then
                closePimSession()
                return false
            end
        elseif e == "key_down" then
            local char = tonumber(ev[3]) or 0
            local code = tonumber(ev[4]) or 0
            local keyPlayer = trimPlayerName(ev[5] or "")
            if keyPlayer ~= "" and not samePlayerName(keyPlayer, adminName) then
            elseif char == 27 or (keyboard.keys and code == keyboard.keys.escape) then
                currentScreen = previousScreen
                AdminUpdate.redrawShop()
                return false
            elseif char == 8 or (keyboard.keys and code == keyboard.keys.back) then
                if unicode.len(password) > 0 then password = unicode.sub(password, 1, -2) end
                AdminUpdate.drawPassword(password, "", colors.text_main)
            elseif char == 13 or (keyboard.keys and code == keyboard.keys.enter) then
                if password == tostring(cfg.password or "") then
                    AdminUpdate.drawPassword(password, "Доступ разрешён. Запуск обновления...", colors.success)
                    os.sleep(0.5)
                    local ok = AdminUpdate.run()
                    if not ok then
                        currentScreen = previousScreen
                        AdminUpdate.redrawShop()
                    end
                    return ok
                end
                password = ""
                AdminUpdate.drawPassword(password, "Неверный пароль!", colors.error)
            elseif char >= 32 and char <= 0x10FFFF then
                if unicode.len(password) < 32 then password = password .. unicode.char(char) end
                AdminUpdate.drawPassword(password, "", colors.text_main)
            end
        end
    end
end

-- Отрисовка popup ошибки
local function drawCrashPopup(errText)
    local popupWidth = 55
    local popupHeight = 9
    local popupX = math.floor((SCREEN_W - popupWidth) / 2)
    local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    gpu.setBackground(colors.bg_main)
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)
    gpu.setForeground(colors.error)
    local title = "ОШИБКА"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)
    gpu.setForeground(colors.text_main)
    local shortErr = errText:sub(1, popupWidth - 4)
    local errX = popupX + 2
    gpu.set(errX, popupY + 2, shortErr)
    for i = 3, 1, -1 do
        gpu.setForeground(colors.success)
        local msg = "Перезагрузка через " .. i .. " сек..."
        local msgX = popupX + math.floor((popupWidth - unicode.len(msg)) / 2)
        gpu.set(msgX, popupY + 5, msg)
        os.sleep(1)
    end
end

-- Главный цикл с обработкой ошибок
while true do
    local ok, err = pcall(main)
    if not ok then
        local errText = tostring(err)
        local lowerErr = string.lower(errText)
        if string.find(lowerErr, "interrupted", 1, true)
            or string.find(lowerErr, "terminate", 1, true) then
        else
            pcall(drawCrashPopup, errText)
        end
    end
end
