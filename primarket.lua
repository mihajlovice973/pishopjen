-- ============================================================
-- PRIMARKET.LUA v3.5 — ПОЛНЫЙ РАБОЧИЙ КОД
-- + сессия НЕ закрывается при открытии инвентаря/ячеек
-- + [ ИСТОРИЯ ] отодвинута дальше от [ ТОП ]
-- + продажа: количество без ".0"
-- + ТОП "Продаж": топ по деньгам (₵ | ۞), ранжирование по сумме
-- ============================================================
local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local keyboard = require("keyboard")
local computer = require("computer")
local fs = require("filesystem")
local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)
local TIMEZONE_OFFSET = 3 * 3600
event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)
local tmpfs = component.proxy(computer.tmpAddress())
local function getRealTimestamp()
    local handle = tmpfs.open("/time", "w")
    tmpfs.write(handle, "time")
    tmpfs.close(handle)
    return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
end
local function getRealTimeString()
    return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end
local function safeEventPull(timeout)
    local result = {pcall(event.pull, timeout)}
    if not result[1] then return {} end
    table.remove(result, 1)
    return result
end
local serverAddress = "a7096c74-1bc4-43a6-8dff-2d4394d22c0e"
local ACCESS_PASSWORD = "yVGF7wT"
colors = {
    bg_main = 0x0E0E14, bg_secondary = 0x16161F, bg_tertiary = 0x1E1E2A,
    bg_button = 0x2A2A3A, bg_button_hover = 0x3A3A4E, bg_button_active = 0x1A1A28,
    accent_main = 0x7B2CBF, accent_light = 0x9D4EDD, accent_dark = 0x5A189A,
    border_main = 0x4A4A5A, border_accent = 0x6A0DAD,
    text_main = 0xB8B8C8, text_bright = 0xE8E8F0, text_dim = 0x6A6A7A,
    success = 0x00D9A3, error = 0xFF4D6D, warning = 0xFFB700,
    inactive = 0x4A4A5A, tomato = 0xFF6B6B, white = 0xFFFFFF,
    gold = 0xFFD700, medal_1 = 0xFFD700, medal_2 = 0xC0C0C0, medal_3 = 0xCD7F32,
}
local maxW, maxH = gpu.maxResolution()
SCREEN_W = math.min(120, maxW)
SCREEN_H = math.min(40, maxH)
shop = {
    items = {}, search = "", searchActive = false, searchInput = "",
    mode = "buy", stockFilterMode = "available", stockFilterOpen = false,
    listScroll = 1, selectedIndex = 0, hoveredIndex = 0,
    filteredItems = {}, selectedItem = nil, horizontalScroll = 1,
    purchaseQuantity = 1, purchaseItem = nil, sellConfirmItem = nil,
    foundAmount = 0, showSellPopup = false, showPartialPopup = false,
    partialExtracted = 0, partialRequested = 0, partialRefundCoin = 0, partialRefundEma = 0,
    showInsufficientPopup = false, insufficientBalanceCoin = 0, insufficientBalanceEma = 0,
    showInventoryFullPopup = false,
    sellAmountInput = "", sellInvCount = 0, sellScanItem = nil,
}
ui = { currentScreen = "welcome", tempMessage = "", tempMessageTimer = nil, showShopDenied = false }
player = { name = nil, token = nil, coinBalance = 0.0, emaBalance = 0.0, transactions = 0, regDate = "", agreed = false }
auth = { startTime = 0, lastSendTime = 0, retryInterval = 1.0, noResponseNotice = 8.0, techWork = false, accountRequestTime = 0, accountTimeout = 3, alreadyAuthorized = false }
stats = { visits = 0, totalSpent = 0, totalEarned = 0, purchases = 0, sells = 0, spentCoin = 0, spentEma = 0 }
top = { data = {}, category = "balance", page = 1, perPage = 10, totalPages = 1, loading = false, lastRequest = 0, requestInterval = 0.3, serverSeen = false }
feedbacks = { list = {}, page = 1, totalPages = 1, input = "", editMode = false, rating = 0, playerHasFeedback = false }
report = { input = "", lastTime = nil }
AGREE_BTN = nil
local STATS_FILE = "/home/player_stats.json"
local playerStats = {}
local function loadPlayerStats()
    if fs.exists(STATS_FILE) then
        local f = io.open(STATS_FILE, "r")
        if f then
            local content = f:read("*a")
            f:close()
            local ok, data = pcall(serialization.unserialize, content)
            if ok and type(data) == "table" then playerStats = data; return end
        end
    end
    playerStats = {}
end
local function savePlayerStats()
    local f = io.open(STATS_FILE, "w")
    if f then f:write(serialization.serialize(playerStats)); f:close() end
end
local function updatePlayerStatLocal(name, field, value)
    if not playerStats[name] then
        playerStats[name] = {
            visits = 0, totalSpent = 0, totalEarned = 0, purchases = 0, sells = 0,
            balance = 0, balanceCoin = 0, balanceEma = 0, spentCoin = 0, spentEma = 0,
            earnedCoin = 0, earnedEma = 0, lastVisit = ""
        }
    end
    local s = playerStats[name]
    if field == "visits" then
        s.visits = (s.visits or 0) + 1
        s.lastVisit = getRealTimeString()
    elseif field == "spent" then s.totalSpent = (s.totalSpent or 0) + value
    elseif field == "spentCoin" then s.spentCoin = (s.spentCoin or 0) + value
    elseif field == "spentEma" then s.spentEma = (s.spentEma or 0) + value
    elseif field == "earned" then s.totalEarned = (s.totalEarned or 0) + value
    elseif field == "earnedCoin" then s.earnedCoin = (s.earnedCoin or 0) + value
    elseif field == "earnedEma" then s.earnedEma = (s.earnedEma or 0) + value
    elseif field == "purchases" then s.purchases = (s.purchases or 0) + 1
    elseif field == "sells" then s.sells = (s.sells or 0) + 1
    elseif field == "balance" then s.balance = value
    elseif field == "balanceCoin" then s.balanceCoin = value
    elseif field == "balanceEma" then s.balanceEma = value
    end
    savePlayerStats()
end
local function getTopPlayersLocal(category, limit)
    local sorted = {}
    for name, s in pairs(playerStats) do
        local val
        if category == "sells" then
            val = (s.earnedCoin or 0) + (s.earnedEma or 0)
        else
            val = s[category] or 0
        end
        table.insert(sorted, {
            name = name, value = val,
            coin = s.balanceCoin or 0, ema = s.balanceEma or 0,
            spentCoin = s.spentCoin or 0, spentEma = s.spentEma or 0,
            earnedCoin = s.earnedCoin or 0, earnedEma = s.earnedEma or 0,
        })
    end
    table.sort(sorted, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    return sorted
end
loadPlayerStats()
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
    if not fs.exists(path) then return {} end
    local ok, result = pcall(dofile, path)
    if not ok then return {} end
    return result
end
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
    for upper, lower in pairs(CYRILLIC_LOWER) do s = s:gsub(upper, lower) end
    s = s:gsub("ё", "е")
    return s
end
local function sortableName(name)
    if not name then return "" end
    local lower = normalizeSearchText(name)
    return lower:gsub("(%d+)", function(d) return string.format("%08d", tonumber(d)) end)
end
local function trimPlayerName(name)
    if type(name) ~= "string" then return "" end
    return name:match("^%s*(.-)%s*$") or name
end
local function samePlayerName(a, b)
    a = trimPlayerName(a); b = trimPlayerName(b)
    if a == "" or b == "" then return false end
    return unicode.lower(a) == unicode.lower(b)
end
local function getStarX()
    local span = 13
    return math.floor((SCREEN_W - span) / 2) + 1
end
local function getReportSendButton()
    return {x = math.floor(SCREEN_W / 2) - 8, y = 18, xs = 17, ys = 1, text = "[ ОТПРАВИТЬ ]", bg = colors.bg_button, fg = colors.success}
end
local deferredEvents = {}
local function deferShopEvent(ev)
    if type(ev) == "table" and ev[1] then deferredEvents[#deferredEvents + 1] = ev end
end
local function nextShopEvent(timeout)
    if #deferredEvents > 0 then return table.remove(deferredEvents, 1) end
    return safeEventPull(timeout)
end
local function extractEventPlayerName(ev)
    if type(ev) ~= "table" then return nil end
    for i = 2, math.min(#ev, 7) do
        local value = ev[i]
        if type(value) == "string" and value ~= "" and value ~= "null" then
            local looksLikeAddress = value:match("^[0-9a-fA-F%-]+$") and #value >= 30
            if not looksLikeAddress and value:match("^[%w_]+$") then return value end
        end
    end
    return nil
end
local function isPimControlEvent(name)
    return name == "player_off" or name == "pim_player_leave"
        or name == "player_on" or name == "pim_player_enter" or name == "pim"
end
local function getPimAddr()
    for addr in component.list("pim") do return addr end
    return nil
end
local PimPresence = { missCount = 0, lastPositive = 0, missLimit = 10, graceSeconds = 4.0 }
-- ОТКЛЮЧЕНО: больше не сбрасываем сессию из-за опроса инвентаря
-- (раньше сеанс "тух" при открытии инвентаря/ячеек).
local function isPlayerPhysicallyOnPim()
    return nil
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
    end
    return true
end
local function checkPimSessionAlive(expectedPlayer)
    for _ = 1, 64 do
        local ev = safeEventPull(0)
        if not ev[1] then break end
        if isPimControlEvent(ev[1]) then
            if not processPimControlEvent(ev, expectedPlayer) then return false end
        else
            deferShopEvent(ev)
        end
    end
    if expectedPlayer and player.name and not samePlayerName(player.name, expectedPlayer) then return false end
    return player.name ~= nil
end
local function pimAwareSleep(seconds, expectedPlayer)
    local deadline = computer.uptime() + math.max(0, tonumber(seconds) or 0)
    while computer.uptime() < deadline do
        local wait = math.min(0.05, math.max(0, deadline - computer.uptime()))
        local ev = safeEventPull(wait)
        if ev[1] then
            if isPimControlEvent(ev[1]) then
                if not processPimControlEvent(ev, expectedPlayer) then return false end
            else
                deferShopEvent(ev)
            end
        end
    end
    return checkPimSessionAlive(expectedPlayer)
end
local function isPimOwner(playerName)
    return player.name ~= nil and samePlayerName(playerName, player.name)
end
local function sendEnterRequest()
    if not player.name or player.name == "" then return false end
    local sent = modem.send(serverAddress, 0xffef, serialization.serialize({ op = "enter", name = player.name }))
    auth.lastSendTime = computer.uptime()
    return sent
end
local selector = nil
for addr in component.list("openperipheral_selector") do selector = component.proxy(addr); break end
if not selector then
    for addr in component.list("item_selector") do selector = component.proxy(addr); break end
end
local function safeSelectorSetSlot(slot, stack)
    if not selector then return false end
    local ok, result = pcall(function() return selector.setSlot(slot, stack) end)
    return ok, result
end
local function updateSelectorDisplay(item)
    if not selector then return end
    if not item then safeSelectorSetSlot(0, nil); safeSelectorSetSlot(1, nil); return end
    local raw = item.internalName or item.name or item.displayName
    if not raw then return end
    local id = raw
    if not id:find(":") then id = "minecraft:" .. id end
    local stack = { id = id, dmg = item.damage or 0 }
    safeSelectorSetSlot(0, stack); safeSelectorSetSlot(1, stack)
end
local shopData = safeDoFile("/home/shop_items.lua")
local sellItems = shopData.sellItems
local buyItemsData = safeDoFile("/home/buy_items.lua")
local buyItemMap = {}
for _, item in ipairs(buyItemsData) do
    local dmg = item.damage or 0
    local nbt = item.nbt_hash or item.nbtHash or item.nbt
    local key = item.internalName .. ":" .. dmg .. "|nbt=" .. tostring(nbt or "")
    buyItemMap[key] = item
end
local drawAgreementScreen = safeDoFile("/home/agreement.lua")
-- ============================================================
-- ЗАГРУЗКА КВЕСТОВ (/home/questlist.lua или quwestlist.lua)
-- ============================================================
local questRaw = safeDoFile("/home/questlist.lua")
if type(questRaw) ~= "table" or #questRaw == 0 then questRaw = safeDoFile("/home/quwestlist.lua") end
local quests = {}
if type(questRaw) == "table" then
    for _, q in ipairs(questRaw) do
        table.insert(quests, {
            questName = q.questName or q.name or q.displayName or "Квест",
            rewardName = q.rewardName or q.reward or q.displayName or "Награда",
            internalName = q.internalName,
            damage = q.damage or 0,
            count = math.max(1, math.floor(tonumber(q.count or q.qty) or 1)),
            price = tonumber(q.price or q.price_coin) or 0,
            price_ema = tonumber(q.price_ema) or 0,
            enabled = (q.enabled ~= false) and (q.available ~= false),
        })
    end
end
local questScroll = 1
local questSelected = 1
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
    local id = tostring(value or ""); id = id:gsub("\\:", ":")
    if id ~= "" and not id:find(":", 1, true) then id = "minecraft:" .. id end
    return id
end
local function parseExportCount(result, requested)
    requested = math.max(0, math.floor(tonumber(requested) or 0))
    if type(result) == "number" then return math.max(0, math.min(requested, math.floor(result))) end
    if result == true then return requested end
    if type(result) == "table" then
        return math.max(0, math.min(requested, math.floor(tonumber(result.size or result.count or result.amount or result.qty) or 0)))
    end
    return 0
end
local NBTDelivery = {}
function NBTDelivery.getMeAddress(me)
    if type(me) == "table" and type(me.address) == "string" and me.address ~= "" then return me.address end
    for addr in component.list("me_interface") do return addr end
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
    return tonumber(entry.size or entry.qty or entry.count or entry.amount or entry.available
        or fp.size or fp.qty or fp.count or fp.amount or fp.available) or tonumber(requested) or 0
end
function NBTDelivery.getEntryIdDamage(entry)
    local fp = NBTDelivery.unwrapFingerprint(entry)
    local id = normalizeMeItemId(fp.id or fp.name or fp.item_name or fp.itemName
        or fp.internal_name or fp.internalName or entry.id or entry.name
        or entry.item_name or entry.itemName or entry.internal_name or entry.internalName)
    local damage = tonumber(fp.dmg or fp.damage or fp.meta or fp.item_damage or fp.itemDamage
        or entry.dmg or entry.damage or entry.meta or entry.item_damage or entry.itemDamage) or 0
    return id, damage
end
function NBTDelivery.readNetworkList(me, methodName, details)
    local address = NBTDelivery.getMeAddress(me)
    local useDetails = details
    if methodName == "getAvailableItems" and useDetails == nil then useDetails = "NONE" end
    if address then
        local ok, result
        if useDetails ~= nil then ok, result = pcall(component.invoke, address, methodName, useDetails)
        else ok, result = pcall(component.invoke, address, methodName) end
        if ok and type(result) == "table" then return result end
    end
    if not me or type(me[methodName]) ~= "function" then return nil end
    local ok, result
    if useDetails ~= nil then ok, result = pcall(me[methodName], useDetails)
    else ok, result = pcall(me[methodName]) end
    if ok and type(result) == "table" then return result end
    if useDetails ~= nil then ok, result = pcall(me[methodName], me, useDetails)
    else ok, result = pcall(me[methodName], me) end
    if ok and type(result) == "table" then return result end
    return nil
end
function NBTDelivery.minimalFingerprint(item, includeNbt)
    local fp = { id = normalizeMeItemId(item and (item.internalName or item.id or item.name)), dmg = tonumber(item and item.damage) or 0 }
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
    local found = {}; local seen = {}
    local list = NBTDelivery.readNetworkList(me, "getAvailableItems", "NONE")
    if type(list) ~= "table" then list = NBTDelivery.readNetworkList(me, "getAvailableItems", nil) end
    if type(list) ~= "table" then list = NBTDelivery.readNetworkList(me, "getItemsInNetwork", nil) end
    if type(list) == "table" then
        for _, entry in pairs(list) do
            if type(entry) == "table" then
                local fp = type(entry.fingerprint) == "table" and entry.fingerprint or entry
                if type(fp) == "table" then
                    local id, damage = NBTDelivery.getEntryIdDamage(entry)
                    local hash = NBTDelivery.getFingerprintHash(entry)
                    local amount = math.max(0, math.floor(NBTDelivery.getEntryAmount(entry, requested)))
                    local hashMatches = (wantedHash == nil) or tostring(hash or "") == tostring(wantedHash)
                    if id == targetId and damage == targetDamage and amount > 0 and hashMatches then
                        local key = id .. ":" .. tostring(damage) .. ":" .. tostring(hash or "")
                        if not seen[key] then
                            seen[key] = true
                            found[#found + 1] = { fingerprint = fp, amount = amount, hash = hash }
                        end
                    end
                end
            end
        end
    end
    list = nil
    pcall(collectgarbage, "step", 10)
    table.sort(found, function(a, b) return (tonumber(a.amount) or 0) > (tonumber(b.amount) or 0) end)
    return found
end
function NBTDelivery.callExport(me, fingerprint, direction, amount)
    local address = NBTDelivery.getMeAddress(me); local ok, result
    if address then ok, result = pcall(component.invoke, address, "exportItem", fingerprint, direction, amount) end
    if not ok then ok, result = pcall(me.exportItem, fingerprint, direction, amount) end
    if not ok then ok, result = pcall(me.exportItem, me, fingerprint, direction, amount) end
    if not ok then return 0, tostring(result) end
    return parseExportCount(result, amount), result
end
function NBTDelivery.exportExact(me, item, qty, direction, maxStackSize, expectedPlayer)
    local remaining = math.max(0, math.floor(tonumber(qty) or 0)); local movedTotal = 0
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
                local compact = { id = normalizeMeItemId(item.internalName), dmg = tonumber(item.damage) or 0, nbt_hash = tostring(entry.hash) }
                got = NBTDelivery.callExport(me, compact, direction, request)
                got = math.max(0, math.min(request, available, tonumber(got) or 0))
            end
            if got <= 0 then break end
            movedTotal = movedTotal + got; remaining = remaining - got; available = available - got
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
            movedTotal = movedTotal + got; remaining = remaining - got
        end
    end
    return movedTotal
end
function NBTDelivery.exportLegacy(me, item, qty, direction, maxStackSize, expectedPlayer)
    local remaining = math.max(0, math.floor(tonumber(qty) or 0)); local movedTotal = 0
    local fingerprint = NBTDelivery.minimalFingerprint(item, false)
    while remaining > 0 do
        if not checkPimSessionAlive(expectedPlayer) then return movedTotal end
        local request = math.min(remaining, maxStackSize or 64)
        local got = NBTDelivery.callExport(me, fingerprint, direction, request)
        got = math.max(0, math.min(request, tonumber(got) or 0))
        if got <= 0 then break end
        movedTotal = movedTotal + got; remaining = remaining - got
    end
    return movedTotal
end
local function exportItemToPlayer(me, item, qty, maxStackSize, expectedPlayer)
    local requested = math.max(0, math.floor(tonumber(qty) or 0))
    if requested <= 0 then return 0 end
    if getItemNbtHash(item) then
        return NBTDelivery.exportExact(me, item, requested, "up", maxStackSize, expectedPlayer)
    end
    return NBTDelivery.exportLegacy(me, item, requested, "up", maxStackSize, expectedPlayer)
end
local function getActualItemQuantity(itemOrName, damage)
    if not component.isAvailable("me_interface") then return 0 end
    local me = component.me_interface; local item
    if type(itemOrName) == "table" then item = itemOrName else item = {internalName = itemOrName, damage = tonumber(damage) or 0} end
    local wantedHash = getItemNbtHash(item)
    if wantedHash then
        local entries = NBTDelivery.getFingerprints(me, item, 0); local total = 0
        for _, entry in ipairs(entries) do total = total + math.max(0, tonumber(entry.amount) or 0) end
        return total
    end
    local ok, items = pcall(me.getItemsInNetwork)
    if not ok then ok, items = pcall(me.getItemsInNetwork, me) end
    if not ok or type(items) ~= "table" then return 0 end
    local total = 0
    for _, meItem in ipairs(items) do
        local name = meItem.name or meItem.id; local dmg = meItem.damage or meItem.dmg or 0
        if tostring(name or "") == tostring(item.internalName or "") and tonumber(dmg or 0) == tonumber(item.damage or 0) then
            total = total + (tonumber(meItem.size or meItem.qty or meItem.count) or 0)
        end
    end
    return total
end
local function sendStatsToServer()
    if not player.name then return end
    modem.send(serverAddress, 0xffef, serialization.serialize({
        op = "update_stats", name = player.name,
        visits = stats.visits, totalSpent = stats.totalSpent, totalEarned = stats.totalEarned,
        purchases = stats.purchases, sells = stats.sells,
        balance = player.coinBalance + player.emaBalance,
        balanceCoin = player.coinBalance, balanceEma = player.emaBalance,
        spentCoin = stats.spentCoin or 0, spentEma = stats.spentEma or 0,
        lastUpdate = getRealTimeString(),
    }))
end
local function requestTopFromServer(category)
    local now = computer.uptime()
    if now - top.lastRequest < top.requestInterval then return end
    top.lastRequest = now
    top.loading = true
    modem.send(serverAddress, 0xffef, serialization.serialize({
        op = "get_top", category = category or top.category, page = top.page, perPage = top.perPage,
    }))
end
local function updatePlayerStat(field, value)
    if field == "visits" then stats.visits = (stats.visits or 0) + 1
    elseif field == "spent" then stats.totalSpent = (stats.totalSpent or 0) + value
    elseif field == "spentCoin" then stats.spentCoin = (stats.spentCoin or 0) + value
    elseif field == "spentEma" then stats.spentEma = (stats.spentEma or 0) + value
    elseif field == "earned" then stats.totalEarned = (stats.totalEarned or 0) + value
    elseif field == "purchases" then stats.purchases = (stats.purchases or 0) + 1
    elseif field == "sells" then stats.sells = (stats.sells or 0) + 1
    end
    if player.name then
        updatePlayerStatLocal(player.name, field, value)
        sendStatsToServer()
    end
end
local function syncBalanceStats()
    if not player.name then return end
    updatePlayerStatLocal(player.name, "balance", player.coinBalance + player.emaBalance)
    updatePlayerStatLocal(player.name, "balanceCoin", player.coinBalance)
    updatePlayerStatLocal(player.name, "balanceEma", player.emaBalance)
end
-- ============================================================
-- ЗАГРУЗКА ПРЕДМЕТОВ С КЭШЕМ СКАНА МЭ (60 сек)
-- ============================================================
local qtyCacheMap = nil
local qtyCacheAt = -1e9
local function getQtyMap()
    local now = computer.uptime()
    if qtyCacheMap and (now - qtyCacheAt) < 60 then return qtyCacheMap end
    local qtyMap = {}
    if component.isAvailable("me_interface") then
        local me = component.me_interface
        local ok, rawItems = pcall(me.getItemsInNetwork)
        if not ok then ok, rawItems = pcall(me.getItemsInNetwork, me) end
        if ok and type(rawItems) == "table" then
            for _, meItem in ipairs(rawItems) do
                local name = meItem.name or meItem.id
                if name then
                    local damage = meItem.damage or meItem.dmg or 0
                    local key = tostring(name) .. ":" .. tostring(damage)
                    qtyMap[key] = (qtyMap[key] or 0) + (tonumber(meItem.size or meItem.qty or meItem.count) or 0)
                end
            end
        end
    end
    qtyCacheMap = qtyMap; qtyCacheAt = now
    return qtyMap
end
local function loadBuyItems()
    local qtyMap = getQtyMap()
    local newShopItems = {}
    for _, mapping in ipairs(buyItemsData) do
        local name = mapping.internalName
        if name and name ~= "customnpcs:npcMoney" then
            local damage = mapping.damage or 0
            local priceCoin = tonumber(mapping.price_coin or mapping.price or 0) or 0
            local priceEma = tonumber(mapping.price_ema or 0) or 0
            if priceCoin > 0 or priceEma > 0 then
                local qty = qtyMap[tostring(name) .. ":" .. tostring(damage)] or 0
                table.insert(newShopItems, {
                    internalName = name, displayName = mapping.displayName or name,
                    qty = qty, priceCoin = priceCoin, priceEma = priceEma, damage = damage,
                    nbt_hash = mapping.nbt_hash or mapping.nbtHash or mapping.tag_hash or mapping.tagHash or mapping.nbt,
                    canBuy = qty > 0
                })
            end
        end
    end
    shop.items = newShopItems
    table.sort(shop.items, function(a, b) return sortableName(a.displayName) < sortableName(b.displayName) end)
end
local function loadSellItems()
    shop.items = {}
    for _, item in ipairs(sellItems) do
        local internal = item.internalName or item.name
        if internal then
            table.insert(shop.items, {
                displayName = item.displayName or item.name or internal,
                internalName = internal, qty = item.qty or 0, price = item.price or 0, damage = item.damage or 0
            })
        end
    end
end
local function drawPopupBorder(x, y, w, h, color)
    gpu.setForeground(color or colors.border_accent)
    gpu.fill(x, y, w, 1, "─"); gpu.fill(x, y + h - 1, w, 1, "─")
    for i = 1, h - 2 do gpu.set(x, y + i, "│"); gpu.set(x + w - 1, y + i, "│") end
    gpu.set(x, y, "┌"); gpu.set(x + w - 1, y, "┐")
    gpu.set(x, y + h - 1, "└"); gpu.set(x + w - 1, y + h - 1, "┘")
end
local function drawScreenBorder()
    local left, right, top, bottom = 1, SCREEN_W, 1, SCREEN_H - 1
    gpu.setForeground(colors.border_accent)
    gpu.fill(left, top, right - left + 1, 1, "═")
    gpu.fill(left, bottom, right - left + 1, 1, "═")
    for y = top + 1, bottom - 1 do gpu.set(left, y, "║"); gpu.set(right, y, "║") end
    gpu.set(left, top, "╔"); gpu.set(right, top, "╗")
    gpu.set(left, bottom, "╚"); gpu.set(right, bottom, "╝")
end
local function drawBigTitle()
    gpu.setForeground(colors.white)
    local titleLines = {
        "██████╗ ██╗    ███████╗██╗  ██╗ ██████╗ ██████╗ ",
        "██╔══██╗██║    ██╔════╝██║  ██║██╔═══██╗██╔══██╗",
        "██████╔╝██║    ███████╗███████║██║   ██║██████╔╝",
        "██╔═══╝ ██║    ╚════██║██╔══██║██║   ██║██╔═══╝ ",
        "██║     ██║    ███████║██║  ██║╚██████╝██║     ",
        "╚═╝     ╚═╝    ╚══════╝╚═╝  ╚═╝ ═════╝ ╚═╝     "
    }
    local startY = math.floor(SCREEN_H * 0.2)
    for i, line in ipairs(titleLines) do
        local x = math.floor((SCREEN_W - unicode.len(line)) / 2) + 1
        gpu.set(x, startY + i - 1, line)
    end
    gpu.setForeground(colors.border_accent)
    local decoText = string.rep("═", math.min(60, SCREEN_W - 4))
    gpu.set(math.floor((SCREEN_W - unicode.len(decoText)) / 2) + 1, startY + #titleLines + 1, decoText)
end
local function drawTempMessage()
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, SCREEN_H, SCREEN_W, 1, " ")
    if ui.tempMessage ~= "" then
        gpu.setForeground(colors.success)
        local x = math.floor((SCREEN_W - unicode.len(ui.tempMessage)) / 2) + 1
        gpu.set(x, SCREEN_H, ui.tempMessage)
    end
end
local function showTempMessage(msg, duration)
    ui.tempMessage = msg
    if ui.tempMessageTimer then event.cancel(ui.tempMessageTimer) end
    ui.tempMessageTimer = event.timer(duration, function()
        ui.tempMessage = ""; ui.tempMessageTimer = nil
        if ui.currentScreen == "welcome" or ui.currentScreen == "auth" or ui.currentScreen == "menu" then
        elseif ui.currentScreen == "shop_buy" or ui.currentScreen == "shop_sell" then
            if not shop.purchaseItem and not shop.sellConfirmItem then
                drawTempMessage(); return
            end
            drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
        elseif ui.currentScreen == "purchase" then
            if not shop.purchaseItem then drawTempMessage(); return end
            drawPurchaseScreen()
        elseif ui.currentScreen == "sell_scan" then
            if not shop.sellConfirmItem then drawTempMessage(); return end
            drawSellScanScreen()
        elseif ui.currentScreen == "quests" then
            drawQuestsScreen()
        elseif ui.currentScreen == "history" then
            drawHistoryScreen()
        elseif ui.currentScreen == "account" then drawAccount()
        elseif ui.currentScreen == "feedbacks" then drawFeedbacksList()
        elseif ui.currentScreen == "top" then drawTopScreen()
        elseif ui.currentScreen == "shop" then drawShopMenu()
        else drawTempMessage()
        end
    end)
    drawTempMessage()
end
local function loadFeedbacksFromServer()
    if not player.token then return end
    modem.send(serverAddress, 0xffef, serialization.serialize({ op = "get_feedbacks", name = player.name, token = player.token }))
end
local TOP_CATEGORIES = {
    {key = "balance",   text = "💰 Баланс"},
    {key = "visits",    text = "👁 Посещ."},
    {key = "spent",     text = "💸 Траты"},
    {key = "purchases", text = "🛒 Покуп."},
    {key = "sells",     text = "💰 Продаж"},
}
local function getTopList()
    -- Категория "Продаж": всегда локальный топ по деньгам (₵ + ۞)
    if top.category == "sells" then
        return getTopPlayersLocal(top.category, 100)
    end
    if top.serverSeen then return top.data end
    return getTopPlayersLocal(top.category, 100)
end
function drawTopScreen()
    clear(); drawScreenBorder()
    local title = " ═ ТОП ИГРОКОВ ══ "
    gpu.setForeground(colors.accent_light)
    gpu.set(math.floor((SCREEN_W - unicode.len(title)) / 2) + 1, 3, title)
    local catY = 5
    local catWidth = math.floor((SCREEN_W - 10) / #TOP_CATEGORIES)
    for i, cat in ipairs(TOP_CATEGORIES) do
        local catX = 5 + (i - 1) * catWidth
        local isActive = (top.category == cat.key)
        gpu.setBackground(isActive and colors.accent_dark or colors.bg_button)
        gpu.fill(catX, catY, catWidth - 2, 1, " ")
        gpu.setForeground(isActive and colors.text_bright or colors.text_main)
        gpu.set(catX + math.floor((catWidth - 2 - unicode.len(cat.text)) / 2), catY, cat.text)
        gpu.setBackground(colors.bg_main)
    end
    if #top.data == 0 and not top.loading then
        requestTopFromServer(top.category)
    end
    local list = getTopList()
    top.totalPages = math.max(1, math.ceil(#list / top.perPage))
    if top.page > top.totalPages then top.page = 1 end
    local startIndex = (top.page - 1) * top.perPage + 1
    local endIndex = math.min(startIndex + top.perPage - 1, #list)
    local tableY = 8
    gpu.setBackground(colors.bg_tertiary); gpu.fill(5, tableY, SCREEN_W - 10, 1, " ")
    gpu.setForeground(colors.text_bright)
    gpu.set(7, tableY, "№"); gpu.set(12, tableY, "Игрок"); gpu.set(50, tableY, "Значение")
    gpu.setBackground(colors.bg_main)
    local rowY = tableY + 1
    for i = startIndex, endIndex do
        local entry = list[i]
        if entry then
            local rank = i
            local rankStr = tostring(rank) .. "."
            local rankColor = colors.white
            if rank == 1 then rankColor = colors.medal_1
            elseif rank == 2 then rankColor = colors.medal_2
            elseif rank == 3 then rankColor = colors.medal_3
            end
            local isCurrentPlayer = (entry.name == player.name)
            if isCurrentPlayer then gpu.setBackground(colors.accent_dark)
            elseif rank % 2 == 0 then gpu.setBackground(colors.bg_secondary)
            else gpu.setBackground(colors.bg_main)
            end
            gpu.fill(5, rowY, SCREEN_W - 10, 1, " ")
            gpu.setForeground(rankColor); gpu.set(7, rowY, rankStr)
            gpu.setForeground(isCurrentPlayer and colors.text_bright or colors.text_main)
            gpu.set(12, rowY, unicode.sub(entry.name, 1, 15))
            local valueStr
            if top.category == "balance" then
                if entry.coin ~= nil or entry.ema ~= nil then
                    valueStr = string.format("%.2f ₵ | %.2f ۞", entry.coin or 0, entry.ema or 0)
                else
                    valueStr = string.format("%.2f", entry.value)
                end
            elseif top.category == "spent" then
                if entry.spentCoin ~= nil or entry.spentEma ~= nil then
                    valueStr = string.format("%.2f ₵ | %.2f ۞", entry.spentCoin or 0, entry.spentEma or 0)
                else
                    valueStr = string.format("%.2f", entry.value)
                end
            elseif top.category == "sells" then
                if entry.earnedCoin ~= nil or entry.earnedEma ~= nil then
                    valueStr = string.format("%.2f ₵ | %.2f ۞", entry.earnedCoin or 0, entry.earnedEma or 0)
                else
                    valueStr = tostring(entry.value)
                end
            else
                valueStr = tostring(entry.value)
            end
            gpu.setForeground(colors.white); gpu.set(50, rowY, valueStr)
            gpu.setBackground(colors.bg_main)
            rowY = rowY + 1
        end
    end
    if #list == 0 then
        if top.serverSeen and top.loading then
            drawCenteredText(15, "Загрузка...", colors.accent_light)
        else
            drawCenteredText(15, "Пока нет данных. Совершите покупки/продажи!", colors.text_dim)
        end
    end
    drawCenteredText(SCREEN_H - 3, "Страница " .. top.page .. " из " .. top.totalPages .. " | Всего: " .. #list, colors.text_dim)
    local prevBtn = {x = math.floor(SCREEN_W / 2) - 20, y = SCREEN_H - 1, xs = 8, ys = 1, text = "[ < ]", bg = colors.bg_button, fg = colors.accent_light}
    local nextBtn = {x = math.floor(SCREEN_W / 2) + 12, y = SCREEN_H - 1, xs = 8, ys = 1, text = "[ > ]", bg = colors.bg_button, fg = colors.accent_light}
    local backBtn = {x = math.floor(SCREEN_W / 2) - 6, y = SCREEN_H - 1, xs = 12, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_light}
    if top.page > 1 then drawFlexButton(prevBtn) end
    drawFlexButton(backBtn)
    if top.page < top.totalPages then drawFlexButton(nextBtn) end
    drawTempMessage()
end
local function handleTopCategoryClick(x, y)
    if y ~= 5 then return false end
    local catWidth = math.floor((SCREEN_W - 10) / #TOP_CATEGORIES)
    for i, cat in ipairs(TOP_CATEGORIES) do
        local catX = 5 + (i - 1) * catWidth
        if x >= catX and x < catX + catWidth - 2 then
            top.category = cat.key; top.page = 1; top.data = {}
            requestTopFromServer(top.category)
            drawTopScreen()
            return true
        end
    end
    return false
end
function drawFeedbacksList()
    clear(); drawScreenBorder()
    local title = " ═ ОТЗЫВЫ ══ "
    gpu.setForeground(colors.accent_light)
    gpu.set(math.floor((SCREEN_W - unicode.len(title)) / 2) + 1, 3, title)
    local totalRating = 0; local ratingCount = 0
    for _, fb in ipairs(feedbacks.list) do
        if fb.rating and fb.rating > 0 then totalRating = totalRating + fb.rating; ratingCount = ratingCount + 1 end
    end
    local avgRating = ratingCount > 0 and totalRating / ratingCount or 0
    local ratingLabel = "⭐ Рейтинг: "
    local ratingValue = string.format("%.1f", avgRating)
    local ratingSuffix = " (" .. ratingCount .. " оценок)"
    local fullRating = ratingLabel .. ratingValue .. ratingSuffix
    local rx = math.floor((SCREEN_W - unicode.len(fullRating)) / 2) + 1
    gpu.setForeground(colors.white); gpu.set(rx, 5, ratingLabel)
    gpu.setForeground(colors.gold); gpu.set(rx + unicode.len(ratingLabel), 5, ratingValue)
    gpu.setForeground(colors.white); gpu.set(rx + unicode.len(ratingLabel) + unicode.len(ratingValue), 5, ratingSuffix)
    if #feedbacks.list == 0 then
        drawCenteredText(12, "Пока нет ни одного отзыва.", colors.text_main)
        drawCenteredText(14, "Будьте первым, кто оставит отзыв!", colors.accent_light)
        if not feedbacks.playerHasFeedback then
            drawCenteredText(16, "Нажмите [ДОБАВИТЬ] чтобы оставить отзыв", colors.text_dim)
        end
    else
        local startIdx = (feedbacks.page - 1) * 3 + 1
        local endIdx = math.min(startIdx + 2, #feedbacks.list)
        local y = 7
        local cardX = 8
        local cardW = SCREEN_W - 16
        for i = startIdx, endIdx do
            local fb = feedbacks.list[i]
            if fb then
                gpu.setForeground(colors.border_accent); gpu.fill(cardX, y, cardW, 5, " ")
                gpu.setBackground(colors.bg_tertiary); gpu.fill(cardX + 1, y + 1, cardW - 2, 3, " ")
                gpu.setForeground(colors.accent_light); gpu.set(cardX + 2, y + 1, "👤 " .. fb.name)
                local timeStr = fb.time or ""
                gpu.setForeground(colors.text_dim); gpu.set(cardX + 2 + unicode.len("👤 " .. fb.name) + 2, y + 1, timeStr)
                local stars = ""
                for s = 1, 5 do stars = stars .. ((fb.rating or 0) >= s and "★" or "☆") end
                gpu.setForeground(colors.gold); gpu.set(cardX + cardW - 14, y + 1, stars)
                gpu.setForeground(colors.text_bright); gpu.set(cardX + 2, y + 2, unicode.sub(fb.text, 1, cardW - 4))
                gpu.setBackground(colors.bg_main)
                y = y + 6
            end
        end
        feedbacks.totalPages = math.max(1, math.ceil(#feedbacks.list / 3))
        drawCenteredText(SCREEN_H - 4, "Страница " .. feedbacks.page .. " из " .. feedbacks.totalPages, colors.text_dim)
    end
    local backBtn = {x = 5, y = SCREEN_H - 1, xs = 11, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_light}
    local addBtn = {x = math.floor(SCREEN_W / 2) - 7, y = SCREEN_H - 1, xs = 14, ys = 1, text = "[ ДОБАВИТЬ ]", bg = colors.bg_button, fg = colors.success}
    local prevBtn = {x = SCREEN_W - 30, y = SCREEN_H - 1, xs = 7, ys = 1, text = "[ < ]", bg = colors.bg_button, fg = colors.accent_light}
    local nextBtn = {x = SCREEN_W - 20, y = SCREEN_H - 1, xs = 7, ys = 1, text = "[ > ]", bg = colors.bg_button, fg = colors.accent_light}
    if not feedbacks.playerHasFeedback then drawFlexButton(addBtn) end
    drawFlexButton(backBtn)
    if #feedbacks.list > 3 then drawFlexButton(prevBtn); drawFlexButton(nextBtn) end
    drawTempMessage()
end
function drawFeedbackInputScreen()
    if feedbacks.playerHasFeedback then showTempMessage("Вы уже оставляли отзыв!", 2); goBackToMenu(); return end
    ui.currentScreen = "feedback_input"; clear(); drawScreenBorder()
    drawCenteredText(4, "ОСТАВИТЬ ОТЗЫВ", colors.accent_light)
    drawCenteredText(8, "Ваше имя: " .. tostring(player.name), colors.accent_light)
    drawCenteredText(10, "Оцените магазин:", colors.text_main)
    local starY = 12
    local starX = getStarX()
    for i = 1, 5 do
        gpu.setForeground(i <= feedbacks.rating and colors.gold or colors.inactive)
        gpu.set(starX + (i - 1) * 3, starY, i <= feedbacks.rating and "★" or "☆")
    end
    drawCenteredText(15, "Оставьте свой отзыв о магазине:", colors.text_main)
    drawCenteredText(16, "Ваше мнение поможет нам стать лучше!", colors.text_dim)
    gpu.setBackground(colors.bg_tertiary); gpu.fill(15, 18, SCREEN_W - 30, 3, " ")
    if feedbacks.input ~= "" then
        gpu.setForeground(colors.text_bright); gpu.set(16, 19, unicode.sub(feedbacks.input, -(SCREEN_W - 34)) .. (feedbacks.editMode and "_" or ""))
    else
        gpu.setForeground(colors.text_dim); gpu.set(16, 19, "Введите ваш отзыв..." .. (feedbacks.editMode and "_" or ""))
    end
    gpu.setBackground(colors.bg_main)
    local cancelBtn = {x = math.floor(SCREEN_W / 2) - 18, y = SCREEN_H - 1, xs = 12, ys = 1, text = "[ ОТМЕНА ]", bg = colors.bg_button, fg = colors.error}
    local sendBtn = {x = math.floor(SCREEN_W / 2) + 6, y = SCREEN_H - 1, xs = 15, ys = 1, text = "[ ОТПРАВИТЬ ]", bg = colors.bg_button, fg = colors.success}
    drawFlexButton(cancelBtn); drawFlexButton(sendBtn); drawTempMessage()
end
local menuButtons = {
    shop    = {x = math.floor((SCREEN_W - 24) / 2), xs = 24, y = math.floor(SCREEN_H * 0.40), ys = 3, text = "🛒 Магазин", bg = 0x808080, fg = 0xFFFFFF},
    account = {x = math.floor((SCREEN_W - 24) / 2), xs = 24, y = math.floor(SCREEN_H * 0.56), ys = 3, text = "👤 Аккаунт", bg = 0x808080, fg = 0xFFFFFF},
}
local function getBottomPanelItems()
    local w = SCREEN_W
    return {
        { id = "report",    text = "[ ПОДДЕРЖКА ]",  color = colors.error,        x = 4 },
        { id = "agreement", text = "[ СОГЛАШЕНИЕ ]", color = colors.accent_light, x = math.floor(w * 0.27) },
        { id = "feedbacks", text = "[ ОТЗЫВЫ ]",     color = colors.gold,         x = math.floor(w * 0.50) },
        { id = "top",       text = "[ ТОП ]",        color = colors.success,      x = math.floor(w * 0.72) },
        -- [ ИСТОРИЯ ] отодвинута дальше от [ ТОП ], к правому краю
        { id = "history",   text = "[ ИСТОРИЯ ]",    color = colors.warning,      x = w - 13 },
    }
end
local function drawBottomPanel()
    for _, item in ipairs(getBottomPanelItems()) do
        gpu.setForeground(item.color)
        gpu.set(item.x, SCREEN_H, item.text)
    end
end
local backButton = { text = "[ НАЗАД ]", x = math.floor((SCREEN_W - 12) / 2), y = SCREEN_H - 1, xs = 12, ys = 1, bg = colors.bg_button, fg = colors.accent_light }
local function isButtonClicked(btn, x, y)
    return y >= btn.y and y < btn.y + btn.ys and x >= btn.x and x < btn.x + btn.xs
end
local nextButton = {text = "[ КУПИТЬ ]", x = math.floor(SCREEN_W / 2) + 10, y = SCREEN_H - 1, xs = 11, ys = 1, bg = colors.bg_button, fg = colors.inactive}
local sellScanSellButton = {text = "[ ПРОДАТЬ ]", x = math.floor(SCREEN_W / 2) - 7, y = math.floor(SCREEN_H * 0.5), xs = 14, ys = 1, bg = colors.bg_button, fg = colors.accent_light}
local stockFilterButton = {text = "[ В НАЛИЧИИ ▼ ]", x = 3, y = SCREEN_H - 1, xs = 22, ys = 1, bg = colors.bg_button, fg = colors.accent_light}
local stockAvailableButton = {text = "✓ В НАЛИЧИИ", x = 3, y = SCREEN_H - 3, xs = 22, ys = 1, bg = colors.bg_button, fg = colors.success}
local stockAllButton = {text = "  ВСЕ", x = 3, y = SCREEN_H - 2, xs = 22, ys = 1, bg = colors.bg_button, fg = colors.text_bright}
local shopMenuButtons = {
    buy    = {x = math.floor((SCREEN_W - 24) / 2), xs = 24, y = math.floor(SCREEN_H * 0.40), ys = 3, text = "🛍 Покупка",    bg = 0x808080, fg = 0xFFFFFF},
    quests = {x = math.floor((SCREEN_W - 24) / 2), xs = 24, y = math.floor(SCREEN_H * 0.55), ys = 3, text = "📜 Квесты",     bg = 0x808080, fg = 0xFFFFFF},
    sell   = {x = math.floor((SCREEN_W - 24) / 2), xs = 24, y = math.floor(SCREEN_H * 0.70), ys = 3, text = "💰 Пополнение", bg = 0x808080, fg = 0xFFFFFF},
}
local function canSendReport()
    if not report.lastTime then return true end
    local now = getRealTimestamp()
    local rd = os.date("*t", report.lastTime); local nd = os.date("*t", now)
    return not (rd.day == nd.day and rd.month == nd.month and rd.year == nd.year)
end
-- ============================================================
-- ИСТОРИЯ ОПЕРАЦИЙ (файл + автоочистка раз в 30 дней)
-- ============================================================
local HISTORY_PATH = "/home/market_history.json"
local MONTH_SECONDS = 30 * 24 * 3600
local historyData = nil
local historyScroll = 1
local function saveHistory()
    local f = io.open(HISTORY_PATH, "w")
    if f then f:write(serialization.serialize(historyData)); f:close() end
end
local function loadHistory()
    if historyData then return historyData end
    historyData = { lastClear = getRealTimestamp(), players = {} }
    if fs.exists(HISTORY_PATH) then
        local f = io.open(HISTORY_PATH, "r")
        if f then
            local raw = f:read("*a"); f:close()
            local ok, data = pcall(serialization.unserialize, raw)
            if ok and type(data) == "table" then
                historyData = data
                if type(historyData.players) ~= "table" then historyData.players = {} end
            end
        end
    end
    local now = getRealTimestamp()
    if (now - (tonumber(historyData.lastClear) or now)) >= MONTH_SECONDS then
        historyData = { lastClear = now, players = {} }
        saveHistory()
    end
    return historyData
end
local function addHistoryEntry(kind, itemName, qty, coin, ema)
    if not player.name then return end
    local h = loadHistory()
    local key = player.name
    if not h.players[key] then h.players[key] = {} end
    table.insert(h.players[key], 1, {
        kind = kind, item = itemName, qty = qty,
        coin = coin or 0, ema = ema or 0,
        time = getRealTimeString(), ts = getRealTimestamp(),
    })
    while #h.players[key] > 300 do table.remove(h.players[key]) end
    saveHistory()
end
local function getHistoryList(name)
    local h = loadHistory()
    for k, v in pairs(h.players) do
        if samePlayerName(k, name) then return v end
    end
    return {}
end
local function historyMetrics()
    local perEntry = 3
    local listTop = 6
    local listBottom = SCREEN_H - 4
    local visibleEntries = math.max(1, math.floor((listBottom - listTop + 1) / perEntry))
    return perEntry, listTop, listBottom, visibleEntries
end
drawHistoryScreen = function()
    ui.currentScreen = "history"; clear(); drawScreenBorder()
    drawCenteredText(3, "═══ ИСТОРИЯ ОПЕРАЦИЙ ═══", colors.accent_light)
    local list = getHistoryList(player.name or "")
    local perEntry, listTop, listBottom, visibleEntries = historyMetrics()
    local maxScroll = math.max(1, #list - visibleEntries + 1)
    if historyScroll < 1 then historyScroll = 1 end
    if historyScroll > maxScroll then historyScroll = maxScroll end
    gpu.setBackground(colors.bg_main); gpu.fill(2, listTop, SCREEN_W - 4, listBottom - listTop + 1, " ")
    if #list == 0 then
        drawCenteredText(math.floor(SCREEN_H / 2), "История пока пуста.", colors.text_dim)
        drawCenteredText(math.floor(SCREEN_H / 2) + 1, "Совершите покупку или пополнение!", colors.text_dim)
    else
        for i = 1, visibleEntries do
            local idx = historyScroll + i - 1
            local e = list[idx]
            if not e then break end
            local y0 = listTop + (i - 1) * perEntry
            local isBuy = (e.kind == "buy")
            local badge = isBuy and "🛒 ПОКУПКА:" or "💰 ПОПОЛНЕНИЕ:"
            gpu.setForeground(isBuy and colors.accent_light or colors.success)
            gpu.set(3, y0, badge)
            gpu.setForeground(colors.text_bright)
            gpu.set(3 + unicode.len(badge) + 1, y0, unicode.sub(tostring(e.item or "?") .. " x" .. tostring(e.qty or 0), 1, SCREEN_W - 42))
            local dx = 5
            local coin = tonumber(e.coin) or 0
            local ema = tonumber(e.ema) or 0
            if coin ~= 0 then
                gpu.setForeground(coin < 0 and colors.tomato or colors.gold)
                local t = string.format("%+.2f ₵", coin)
                gpu.set(dx, y0 + 1, t); dx = dx + unicode.len(t) + 2
            end
            if ema ~= 0 then
                gpu.setForeground(ema < 0 and colors.tomato or colors.success)
                local t = string.format("%+.2f ۞", ema)
                gpu.set(dx, y0 + 1, t)
            end
            gpu.setForeground(colors.text_dim)
            gpu.set(SCREEN_W - 24, y0 + 1, "🕒 " .. tostring(e.time or ""))
        end
        if #list > visibleEntries then
            local barX = SCREEN_W - 2; local barH = listBottom - listTop + 1
            gpu.setBackground(colors.bg_secondary); gpu.fill(barX, listTop, 2, barH, " ")
            local thumbH = math.max(2, math.floor(barH * visibleEntries / #list))
            local maxPos = barH - thumbH
            local pos = math.min(math.floor((historyScroll - 1) * maxPos / (#list - visibleEntries)) + 1, maxPos + 1)
            gpu.setBackground(colors.accent_main); gpu.fill(barX, listTop + pos - 1, 2, thumbH, " ")
        end
    end
    gpu.setBackground(colors.bg_main)
    drawCenteredText(SCREEN_H - 3, "Колёсико / ↑↓ — прокрутка | Автоочистка раз в 30 дней", colors.text_dim)
    drawFlexButton({x = math.floor(SCREEN_W / 2) - 20, y = SCREEN_H - 1, xs = 8, ys = 1, text = "[ < ]", bg = colors.bg_button, fg = colors.accent_light})
    drawFlexButton(backButton)
    drawFlexButton({x = math.floor(SCREEN_W / 2) + 12, y = SCREEN_H - 1, xs = 8, ys = 1, text = "[ > ]", bg = colors.bg_button, fg = colors.accent_light})
    drawTempMessage()
end
-- ============================================================
-- ОТРИСОВКА МАГАЗИНА
-- ============================================================
local function drawBalanceLine(x, y)
    gpu.setForeground(colors.text_bright); gpu.set(x, y, "💰 Баланс: ")
    local coinStr = string.format("%.2f", player.coinBalance) .. " ₵"
    gpu.setForeground(colors.gold); gpu.set(x + unicode.len("💰 Баланс: "), y, coinStr)
    gpu.setForeground(colors.text_dim); gpu.set(x + unicode.len("💰 Баланс: ") + unicode.len(coinStr), y, " | ")
    gpu.setForeground(colors.tomato)
    gpu.set(x + unicode.len("💰 Баланс: ") + unicode.len(coinStr) + unicode.len(" | "), y, "ЭМЫ: " .. string.format("%.2f", player.emaBalance) .. " ۞")
end
local function getSearchRects()
    local fieldW = 25; local clearW = 5
    local clearX = SCREEN_W - 7
    local searchX = clearX - 1 - fieldW
    return searchX, fieldW, clearX, clearW
end
local function drawSearchBar()
    local sx, sw, cx, cw = getSearchRects()
    local searchText = shop.searchActive and shop.searchInput .. "_" or (shop.search == "" and "🔍 Поиск..." or shop.search)
    gpu.setBackground(colors.bg_tertiary); gpu.fill(sx, 3, sw, 1, " ")
    gpu.setForeground(colors.accent_light); gpu.set(sx + 1, 3, unicode.sub(searchText, 1, sw - 2))
    gpu.setBackground(colors.error); gpu.fill(cx, 3, cw, 1, " ")
    gpu.setForeground(colors.text_bright); gpu.set(cx, 3, "[ X ]")
    gpu.setBackground(colors.bg_main)
end
local COL_QTY = 74
local COL_COIN = 88
local COL_EMA = 102
local COL_PRICE = 102
drawBuyStatic = function()
    clear(); drawScreenBorder(); drawBalanceLine(3, 1)
    gpu.setForeground(colors.accent_light)
    gpu.set(3, 3, shop.mode == "buy" and "🏪 Магазин продаёт" or "💰 Магазин покупает")
    drawSearchBar()
    gpu.setBackground(colors.bg_tertiary); gpu.fill(2, 5, SCREEN_W - 4, 1, " ")
    gpu.setForeground(colors.text_bright)
    gpu.set(3, 5, "Название"); gpu.set(COL_QTY, 5, "Кол-во")
    if shop.mode == "buy" then
        gpu.set(COL_COIN, 5, "₵ Coina"); gpu.set(COL_EMA, 5, "۞ ЭМЫ")
    else
        gpu.set(COL_PRICE, 5, "Цена")
    end
    gpu.setBackground(colors.bg_main); drawTempMessage()
end
local function listVisibleRows() return math.min(30, SCREEN_H - 10) end
local function drawSingleRow(y, item, isHovered, isSelected, itemIndex)
    if not item then return end
    local bg, fg
    if shop.mode == "buy" and item.qty == 0 then bg = colors.bg_main; fg = colors.inactive
    elseif isSelected then bg = colors.accent_dark; fg = colors.text_bright
    else bg = colors.bg_main; fg = colors.text_main
    end
    gpu.setBackground(bg); gpu.fill(2, y, SCREEN_W - 4, 1, " "); gpu.setForeground(fg)
    local name = item.displayName or item.internalName
    local maxNameLen = COL_QTY - 6
    if unicode.len(name) > maxNameLen then name = unicode.sub(name, shop.horizontalScroll, shop.horizontalScroll + maxNameLen - 1) end
    gpu.set(3, y, name); gpu.set(COL_QTY, y, tostring(item.qty))
    if shop.mode == "sell" then
        if item.internalName == "customnpcs:npcMoney" then
            gpu.setForeground(colors.tomato); gpu.set(COL_PRICE, y, string.format("%.2f", item.price) .. " ۞")
        else
            gpu.setForeground(colors.gold); gpu.set(COL_PRICE, y, string.format("%.2f", item.price) .. " ₵")
        end
    else
        gpu.setForeground(item.priceCoin and item.priceCoin > 0 and colors.gold or colors.inactive)
        gpu.set(COL_COIN, y, item.priceCoin and item.priceCoin > 0 and string.format("%.2f", item.priceCoin) or "0")
        gpu.setForeground(item.priceEma and item.priceEma > 0 and colors.tomato or colors.inactive)
        gpu.set(COL_EMA, y, item.priceEma and item.priceEma > 0 and string.format("%.2f", item.priceEma) or "0")
    end
    gpu.setBackground(colors.bg_main)
end
local function drawScrollBar()
    local total = #shop.filteredItems; local barX = SCREEN_W - 2; local barY = 7
    local barHeight = listVisibleRows()
    gpu.setBackground(colors.bg_main); gpu.fill(barX, barY, 2, barHeight, " ")
    if total <= barHeight then return end
    gpu.setBackground(colors.bg_secondary); gpu.fill(barX, barY, 2, barHeight, " ")
    local thumbHeight = math.max(2, math.floor(barHeight * barHeight / total))
    local maxPos = barHeight - thumbHeight
    local thumbPos = math.min(math.floor((shop.listScroll - 1) * maxPos / (total - barHeight)) + 1, maxPos + 1)
    gpu.setBackground(colors.accent_main); gpu.fill(barX, barY + thumbPos - 1, 2, thumbHeight, " ")
    gpu.setBackground(colors.bg_main)
end
drawBuyItemsList = function()
    local filtered = {}; local searchLower = normalizeSearchText(shop.search); local searchWords = {}
    if searchLower ~= "" then for word in searchLower:gmatch("%S+") do table.insert(searchWords, word) end end
    for _, item in ipairs(shop.items) do
        local haystack = normalizeSearchText(item.displayName or "") .. " " .. normalizeSearchText(item.internalName or "")
        local matchesSearch = (#searchWords == 0)
        if not matchesSearch then
            for _, word in ipairs(searchWords) do
                if string.find(haystack, word, 1, true) then matchesSearch = true; break end
            end
        end
        local matchesStock = true
        if shop.mode == "buy" and shop.stockFilterMode == "available" then matchesStock = (tonumber(item.qty) or 0) > 0 end
        if matchesSearch and matchesStock then table.insert(filtered, item) end
    end
    table.sort(filtered, function(a, b) return sortableName(a.displayName or a.internalName) < sortableName(b.displayName or b.internalName) end)
    shop.filteredItems = filtered
    local visibleRows = listVisibleRows()
    shop.listScroll = math.max(1, math.min(shop.listScroll, math.max(1, #filtered - visibleRows + 1)))
    gpu.setBackground(colors.bg_main); gpu.fill(2, 7, SCREEN_W - 4, visibleRows, " ")
    if #filtered == 0 then
        local msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
        gpu.setForeground(colors.error); gpu.set(math.floor((SCREEN_W - unicode.len(msg)) / 2) + 1, math.floor(SCREEN_H / 2), msg)
    else
        for i = 1, visibleRows do
            local itemIndex = shop.listScroll + i - 1
            local item = filtered[itemIndex]
            if not item then break end
            drawSingleRow(6 + i, item, itemIndex == shop.hoveredIndex, itemIndex == shop.selectedIndex, itemIndex)
        end
    end
    drawScrollBar()
    if shop.selectedItem then updateSelectorDisplay(shop.selectedItem) end
end
local function smoothScroll(steps)
    local total = #shop.filteredItems
    local visibleRows = listVisibleRows()
    local newScroll = math.max(1, math.min(shop.listScroll + steps, math.max(1, total - visibleRows + 1)))
    if newScroll == shop.listScroll then return end
    shop.listScroll = newScroll; drawBuyItemsList()
end
local function drawStockFilter()
    if shop.mode ~= "buy" then return end
    stockFilterButton.text = shop.stockFilterMode == "available" and "[ В НАЛИЧИИ ▼ ]" or "[ ВСЕ ▼ ]"
    gpu.setBackground(colors.bg_main); gpu.fill(stockFilterButton.x, SCREEN_H - 3, stockFilterButton.xs, 2, " ")
    if shop.stockFilterOpen then
        stockAvailableButton.text = (shop.stockFilterMode == "available" and "✓ " or "  ") .. "В НАЛИЧИИ"
        stockAllButton.text = (shop.stockFilterMode == "all" and "✓ " or "  ") .. "ВСЕ"
        drawFlexButton(stockAvailableButton); drawFlexButton(stockAllButton)
    end
    drawFlexButton(stockFilterButton)
end
local function applyStockFilter(mode)
    if mode ~= "available" and mode ~= "all" then return end
    shop.stockFilterMode = mode; shop.stockFilterOpen = false
    shop.listScroll = 1; shop.selectedIndex = 0; shop.hoveredIndex = 0; shop.selectedItem = nil
    updateSelectorDisplay(nil); drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
end
drawBuyButtons = function()
    if shop.mode == "buy" then nextButton.text = "[ КУПИТЬ ]" else nextButton.text = "[ ПРОДАТЬ ]" end
    nextButton.xs = unicode.len(nextButton.text) + 2
    nextButton.fg = shop.selectedItem and (shop.mode ~= "buy" or shop.selectedItem.qty > 0) and colors.accent_light or colors.inactive
    drawFlexButton(backButton); drawFlexButton(nextButton); drawStockFilter(); drawTempMessage()
end
-- ============================================================
-- ЭКРАНЫ
-- ============================================================
function drawPurchaseScreen()
    if not shop.purchaseItem then ui.currentScreen = "menu"; drawMainMenu(); return end
    ui.currentScreen = "purchase"; clear(); drawScreenBorder(); drawBalanceLine(3, 1)
    local px, py, pw, ph = 3, 5, SCREEN_W - 6, SCREEN_H - 9
    gpu.setBackground(colors.bg_secondary); gpu.fill(px, py, pw, ph, " ")
    drawPopupBorder(px, py, pw, ph, colors.border_accent)
    gpu.setForeground(colors.accent_light); gpu.set(px + 2, py, " 🛒 ПОКУПКА ПРЕДМЕТА ")
    local item = shop.purchaseItem
    local lblItem = "📦 Предмет: "
    local lblStock = "📊 В наличии: "
    local lblQty = "🔢 Количество: "
    gpu.setForeground(colors.success); gpu.set(px + 3, py + 2, lblItem)
    gpu.setForeground(colors.text_bright); gpu.set(px + 3 + unicode.len(lblItem), py + 2, unicode.sub(item.displayName, 1, pw - 24))
    gpu.setForeground(colors.success); gpu.set(px + 3, py + 3, lblStock)
    gpu.setForeground(colors.text_bright); gpu.set(px + 3 + unicode.len(lblStock), py + 3, tostring(item.qty))
    local half = px + math.floor(pw / 2) + 6
    local lblPrice = "💰 Цена: "
    local lblSum = "💵 Сумма: "
    gpu.setForeground(colors.success); gpu.set(half, py + 2, lblPrice)
    local vx = half + unicode.len(lblPrice)
    local cy2 = py + 2
    if item.priceCoin and item.priceCoin > 0 then
        gpu.setForeground(colors.gold); gpu.set(vx, cy2, string.format("%.2f", item.priceCoin) .. " ₵"); cy2 = cy2 + 1
    end
    if item.priceEma and item.priceEma > 0 then
        gpu.setForeground(colors.tomato); gpu.set(vx, cy2, string.format("%.2f", item.priceEma) .. " ۞")
    end
    local totalCoin = (item.priceCoin or 0) * shop.purchaseQuantity
    local totalEma = (item.priceEma or 0) * shop.purchaseQuantity
    gpu.setForeground(colors.success); gpu.set(half, py + 5, lblSum)
    local sx2 = half + unicode.len(lblSum)
    local sy = py + 5
    if totalCoin > 0 then gpu.setForeground(colors.gold); gpu.set(sx2, sy, string.format("%.2f", totalCoin) .. " ₵"); sy = sy + 1 end
    if totalEma > 0 then gpu.setForeground(colors.tomato); gpu.set(sx2, sy, string.format("%.2f", totalEma) .. " ۞") end
    gpu.setForeground(colors.success); gpu.set(px + 3, py + 5, lblQty)
    local qbx = px + 3 + unicode.len(lblQty)
    gpu.setBackground(colors.bg_tertiary); gpu.fill(qbx, py + 5, 12, 1, " ")
    gpu.setForeground(colors.gold); gpu.set(qbx + 1, py + 5, tostring(shop.purchaseQuantity) .. "_")
    gpu.setBackground(colors.bg_secondary)
    gpu.setForeground(colors.text_dim)
    gpu.set(px + 3, py + ph - 2, "Цифры — количество | Backspace — стереть | Enter — купить")
    gpu.setBackground(colors.bg_main)
    drawFlexButton({x = math.floor(SCREEN_W / 2) - 18, y = SCREEN_H - 1, xs = 12, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_light})
    drawFlexButton({x = math.floor(SCREEN_W / 2) + 6, y = SCREEN_H - 1, xs = 12, ys = 1, text = "[ КУПИТЬ ]", bg = colors.bg_button, fg = colors.success})
    drawTempMessage()
end
local function goToPurchase(item)
    if not item then return end
    shop.purchaseItem = item; shop.purchaseQuantity = 1; drawPurchaseScreen()
end
local function drawSellPopup()
    if not shop.sellConfirmItem then return end
    local popupWidth = 45; local popupHeight = 11
    local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(popupX, popupY+2, popupWidth, popupHeight-4, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.border_accent)
    local name = shop.sellConfirmItem.displayName
    local value = shop.foundAmount * shop.sellConfirmItem.price
    gpu.setForeground(colors.text_bright); gpu.set(popupX+16, popupY, "Подтверждение")
    gpu.setForeground(colors.success); gpu.set(popupX+3, popupY+3, "Магазин заберёт: ")
    gpu.setForeground(colors.text_bright); gpu.set(popupX+3 + unicode.len("Магазин заберёт: "), popupY+3, tostring(shop.foundAmount))
    gpu.setForeground(colors.success); gpu.set(popupX+3, popupY+4, name .. " x")
    gpu.setForeground(colors.text_bright); gpu.set(popupX+3 + unicode.len(name .. " x"), popupY+4, tostring(shop.foundAmount))
    gpu.setForeground(colors.success); gpu.set(popupX+3, popupY+5, "Вы получите: ")
    if shop.sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato); gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ۞")
    else
        gpu.setForeground(colors.gold); gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ₵")
    end
    drawFlexButton({x=popupX+5, y=popupY+8, xs=15, ys=1, text="[ Принять ]", bg=colors.bg_button, fg=colors.success})
    drawFlexButton({x=popupX+popupWidth-18, y=popupY+8, xs=14, ys=1, text="[ Отмена ]", bg=colors.bg_button, fg=colors.error})
    drawTempMessage()
end
local function drawInsufficientPopup()
    local popupWidth = 55; local popupHeight = 12
    local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)
    gpu.setForeground(colors.error)
    gpu.set(popupX + math.floor((popupWidth - unicode.len("НЕДОСТАТОЧНО СРЕДСТВ")) / 2), popupY, "НЕДОСТАТОЧНО СРЕДСТВ")
    gpu.setForeground(colors.text_main)
    gpu.set(popupX + math.floor((popupWidth - unicode.len("Пополни баланс, не можешь купить")) / 2), popupY+2, "Пополни баланс, не можешь купить")
    gpu.set(popupX + math.floor((popupWidth - unicode.len("хотя бы 1 штуку предмета.")) / 2), popupY+3, "хотя бы 1 штуку предмета.")
    gpu.setForeground(colors.success); gpu.set(popupX+3, popupY+5, "Твой баланс Coin: ")
    gpu.setForeground(colors.gold); gpu.set(popupX+3 + unicode.len("Твой баланс Coin: "), popupY+5, string.format("%.2f", shop.insufficientBalanceCoin) .. " ₵")
    if shop.insufficientBalanceEma > 0 then
        gpu.setForeground(colors.success); gpu.set(popupX+3, popupY+6, "Твой баланс ЭМЫ: ")
        gpu.setForeground(colors.tomato); gpu.set(popupX+3 + unicode.len("Твой баланс ЭМЫ: "), popupY+6, string.format("%.2f", shop.insufficientBalanceEma) .. " ۞")
    end
    drawFlexButton({x = popupX + math.floor((popupWidth - 10) / 2), y = popupY+9, xs = 10, ys = 1, text = "[ ПОНЯТНО ]", bg = colors.bg_button, fg = colors.success})
    drawTempMessage()
end
local function drawPartialPopup()
    local popupWidth = 55; local popupHeight = 10
    local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.warning)
    gpu.setForeground(colors.warning)
    gpu.set(popupX + math.floor((popupWidth - unicode.len("НЕ ПОЛНАЯ ВЫДАЧА")) / 2), popupY, "НЕ ПОЛНАЯ ВЫДАЧА")
    gpu.setForeground(colors.text_main)
    gpu.set(popupX + math.floor((popupWidth - unicode.len("Не хватило места в инвентаре!")) / 2), popupY+2, "Не хватило места в инвентаре!")
    local line2 = "Выдано " .. shop.partialExtracted .. " из " .. shop.partialRequested
    gpu.set(popupX + math.floor((popupWidth - unicode.len(line2)) / 2), popupY+3, line2)
    drawFlexButton({x = popupX + math.floor((popupWidth - 10) / 2), y = popupY+7, xs = 10, ys = 1, text = "[ ПРИНЯТЬ ]", bg = colors.bg_button, fg = colors.success})
    drawTempMessage()
end
local function drawInventoryFullPopup()
    local popupWidth = 55; local popupHeight = 10
    local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.warning)
    gpu.setForeground(colors.warning)
    gpu.set(popupX + math.floor((popupWidth - unicode.len("ПРЕДУПРЕЖДЕНИЕ")) / 2), popupY, "ПРЕДУПРЕЖДЕНИЕ")
    gpu.setForeground(colors.text_main)
    gpu.set(popupX + math.floor((popupWidth - unicode.len("Ваш инвентарь полон!")) / 2), popupY+2, "Ваш инвентарь полон!")
    gpu.set(popupX + math.floor((popupWidth - unicode.len("Освободите его и повторите попытку.")) / 2), popupY+3, "Освободите его и повторите попытку.")
    drawFlexButton({x = popupX + math.floor((popupWidth - 10) / 2), y = popupY+7, xs = 10, ys = 1, text = "[ ПОНЯТНО ]", bg = colors.bg_button, fg = colors.success})
    drawTempMessage()
end
function drawSellScanScreen()
    if not shop.sellConfirmItem then ui.currentScreen = "menu"; drawMainMenu(); return end
    if shop.sellScanItem ~= shop.sellConfirmItem.internalName then
        shop.sellScanItem = shop.sellConfirmItem.internalName
        shop.sellInvCount = math.floor(scanPlayerInventory(shop.sellConfirmItem.internalName, shop.sellConfirmItem.damage or 0) or 0)
        shop.sellAmountInput = tostring(shop.sellInvCount)
    end
    ui.currentScreen = "sell_scan"; clear(); drawScreenBorder(); drawBalanceLine(3, 1)
    local px, py, pw, ph = 3, 5, SCREEN_W - 6, SCREEN_H - 9
    gpu.setBackground(colors.bg_secondary); gpu.fill(px, py, pw, ph, " ")
    drawPopupBorder(px, py, pw, ph, colors.border_accent)
    gpu.setForeground(colors.accent_light); gpu.set(px + 2, py, " 💰 ПРОДАЖА / ПОПОЛНЕНИЕ ")
    local it = shop.sellConfirmItem
    local lblName = "📦 Предмет: "
    local lblPrice = "💰 Цена: "
    local lblInv = "🎒 У вас в инвентаре: "
    local lblQty = "🔢 Количество: "
    local lblSum = "💵 Баланс пополнится на: "
    gpu.setForeground(colors.success); gpu.set(px + 3, py + 2, lblName)
    gpu.setForeground(colors.text_bright); gpu.set(px + 3 + unicode.len(lblName), py + 2, unicode.sub(it.displayName, 1, pw - 24))
    gpu.setForeground(colors.success); gpu.set(px + 3, py + 3, lblPrice)
    if it.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato); gpu.set(px + 3 + unicode.len(lblPrice), py + 3, string.format("%.2f", it.price) .. " ۞")
    else
        gpu.setForeground(colors.gold); gpu.set(px + 3 + unicode.len(lblPrice), py + 3, string.format("%.2f", it.price) .. " ₵")
    end
    gpu.setForeground(colors.accent_light); gpu.set(px + 3, py + 5, lblInv)
    gpu.setForeground(colors.text_bright); gpu.set(px + 3 + unicode.len(lblInv), py + 5, tostring(math.floor(shop.sellInvCount or 0)))
    local amount = math.max(0, math.floor(tonumber(shop.sellAmountInput) or 0))
    gpu.setForeground(colors.success); gpu.set(px + 3, py + 7, lblQty)
    local qbx = px + 3 + unicode.len(lblQty)
    gpu.setBackground(colors.bg_tertiary); gpu.fill(qbx, py + 7, 14, 1, " ")
    gpu.setForeground(colors.text_bright); gpu.set(qbx + 1, py + 7, unicode.sub((shop.sellAmountInput or "") .. "_", 1, 12))
    gpu.setBackground(colors.bg_secondary)
    local value = amount * (it.price or 0)
    gpu.setForeground(colors.success); gpu.set(px + 3, py + 9, lblSum)
    if it.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato); gpu.set(px + 3 + unicode.len(lblSum), py + 9, string.format("%.2f", value) .. " ۞")
    else
        gpu.setForeground(colors.gold); gpu.set(px + 3 + unicode.len(lblSum), py + 9, string.format("%.2f", value) .. " ₵")
    end
    gpu.setForeground(colors.text_dim); gpu.set(px + 3, py + ph - 2, "Цифры — ввод | Backspace — стереть | Enter — продать")
    gpu.setBackground(colors.bg_main)
    drawFlexButton(backButton)
    drawFlexButton(sellScanSellButton)
    if shop.showSellPopup then drawSellPopup() end
    drawTempMessage()
end
function drawReportScreen()
    ui.currentScreen = "report"; clear(); drawScreenBorder()
    drawCenteredText(4, "РЕПОРТ", colors.accent_light)
    gpu.setForeground(colors.text_main)
    local help1 = "Опишите проблему: баг, предложение, жалоба."
    gpu.set(math.floor((SCREEN_W - unicode.len(help1)) / 2) + 1, 6, help1)
    if not canSendReport() then
        drawCenteredText(9, "Вы уже отправляли репорт сегодня.", colors.error)
        drawCenteredText(10, "Лимит: 1 сообщение в сутки (сброс в 00:00 МСК).", colors.error)
        drawFlexButton(backButton); drawTempMessage(); return
    end
    gpu.setBackground(colors.bg_tertiary); gpu.fill(15, 8, SCREEN_W - 30, 3, " ")
    if report.input ~= "" then
        gpu.setForeground(colors.text_bright); gpu.set(16, 9, unicode.sub(report.input, -(SCREEN_W - 34)))
    else
        gpu.setForeground(colors.text_dim); gpu.set(16, 9, "Введите текст сообщения...")
    end
    gpu.setBackground(colors.bg_main)
    drawCenteredText(16, "Ограничение: 1 репорт в сутки (сброс в 00:00 МСК)", colors.text_dim)
    drawFlexButton(getReportSendButton())
    drawFlexButton(backButton)
    drawTempMessage()
end
function drawShopMenu()
    clear(); drawScreenBorder()
    drawCenteredText(math.floor(SCREEN_H * 0.25), "МАГАЗИН", colors.accent_light)
    if not player.agreed then
        drawCenteredText(9, "Доступ запрещён.", colors.error)
        drawCenteredText(10, "Примите соглашение, нажав [СОГЛАШЕНИЕ] внизу.", colors.accent_light)
        drawFlexButton(backButton); drawTempMessage(); return
    end
    for _, btn in pairs(shopMenuButtons) do drawButton(btn) end
    drawFlexButton(backButton); drawTempMessage()
end
local function drawWelcomeScreen()
    gpu.setBackground(colors.bg_main); gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    drawBigTitle()
    drawCenteredText(math.floor(SCREEN_H * 0.75), "↓   Встаньте на PIM   ↓", colors.white)
    drawCenteredText(math.floor(SCREEN_H * 0.75) + 1, "━━━━━━━━━━━━━━━━━━━", colors.border_accent)
    gpu.setForeground(colors.text_main); gpu.setBackground(colors.bg_main)
    drawTempMessage()
end
closePimSession = function()
    if ui.tempMessageTimer then pcall(event.cancel, ui.tempMessageTimer); ui.tempMessageTimer = nil end
    ui.tempMessage = ""
    ui.currentScreen = "welcome"
    player.name = nil; player.token = nil; auth.alreadyAuthorized = false
    player.coinBalance = 0.0; player.emaBalance = 0.0; player.transactions = 0; player.regDate = ""; player.agreed = false
    auth.startTime = 0; auth.lastSendTime = 0; auth.techWork = false; auth.accountRequestTime = 0
    stats.visits = 0; stats.totalSpent = 0; stats.totalEarned = 0; stats.purchases = 0; stats.sells = 0
    stats.spentCoin = 0; stats.spentEma = 0
    top.data = {}; top.page = 1; top.serverSeen = false
    shop.selectedItem = nil; shop.purchaseItem = nil; shop.sellConfirmItem = nil
    shop.selectedIndex = 0; shop.hoveredIndex = 0; shop.listScroll = 1; shop.purchaseQuantity = 1; shop.foundAmount = 0
    shop.showSellPopup = false; shop.showPartialPopup = false; shop.showInsufficientPopup = false; shop.showInventoryFullPopup = false
    shop.stockFilterOpen = false; shop.searchActive = false; shop.searchInput = ""; shop.search = ""
    shop.sellAmountInput = ""; shop.sellInvCount = 0; shop.sellScanItem = nil
    pcall(updateSelectorDisplay, nil)
    safeSelectorSetSlot(0, nil); safeSelectorSetSlot(1, nil)
    drawWelcomeScreen()
end
local function drawAuthScreen()
    auth.techWork = false
    gpu.setBackground(colors.bg_main); gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    drawBigTitle()
    gpu.setForeground(colors.text_bright)
    drawCenteredText(math.floor(SCREEN_H * 0.75), "Авторизация...", colors.text_bright)
    gpu.setForeground(colors.text_main); gpu.setBackground(colors.bg_main)
    drawTempMessage()
end
local function drawTechWorkScreen()
    if auth.techWork then return end
    auth.techWork = true
    gpu.setBackground(colors.bg_main); gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    drawBigTitle()
    drawCenteredText(math.floor(SCREEN_H * 0.75), "Тех.Работа", colors.error)
    gpu.setForeground(colors.text_main); gpu.setBackground(colors.bg_main)
end
function drawMainMenu()
    clear(); drawScreenBorder()
    if player.name then
        local hello1 = "Добро пожаловать, "; local hello2 = player.name .. "!"
        local full1 = hello1 .. hello2
        local x1 = math.floor((SCREEN_W - unicode.len(full1))/2) + 2
        gpu.setForeground(colors.success); gpu.set(x1, 4, hello1)
        gpu.setForeground(colors.text_bright); gpu.set(x1 + unicode.len(hello1), 4, hello2)
        local balanceText = "Баланс: " .. string.format("%.2f", player.coinBalance) .. " ₵"
        local balanceX = math.floor((SCREEN_W - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", player.emaBalance) .. " ۞")) / 2) + 1
        gpu.setForeground(colors.text_bright); gpu.set(balanceX, 5, "Баланс: ")
        gpu.setForeground(colors.gold); gpu.set(balanceX + unicode.len("Баланс: "), 5, string.format("%.2f", player.coinBalance) .. " ₵")
        gpu.setForeground(colors.text_dim); gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", player.coinBalance) .. " ₵"), 5, " | ")
        gpu.setForeground(colors.tomato)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", player.coinBalance) .. " ₵") + unicode.len(" | "), 5, "ЭМЫ: " .. string.format("%.2f", player.emaBalance) .. " ۞")
        if not player.agreed then
            if ui.showShopDenied then drawCenteredText(7, "Доступ запрещён. Примите соглашение [СОГЛАШЕНИЕ]", colors.error)
            else drawCenteredText(7, "Вы не приняли пользовательское соглашение! Нажмите [СОГЛАШЕНИЕ]", colors.accent_light) end
        end
        for _, btn in pairs(menuButtons) do drawButton(btn) end
        drawTempMessage()
        drawBottomPanel()
    else
        drawWelcomeScreen()
    end
end
function drawAccount()
    clear(); drawScreenBorder()
    drawCenteredText(10, "Аккаунт игрока: " .. tostring(player.name), colors.text_bright)
    local balanceText = "Баланс: " .. string.format("%.2f", player.coinBalance) .. " ₵"
    local balanceX = math.floor((SCREEN_W - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", player.emaBalance) .. " ۞")) / 2) + 1
    gpu.setForeground(colors.text_bright); gpu.set(balanceX, 12, "Баланс: ")
    gpu.setForeground(colors.gold); gpu.set(balanceX + unicode.len("Баланс: "), 12, string.format("%.2f", player.coinBalance) .. " ₵")
    gpu.setForeground(colors.text_dim); gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", player.coinBalance) .. " ₵"), 12, " | ")
    gpu.setForeground(colors.tomato)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", player.coinBalance) .. " ₵") + unicode.len(" | "), 12, "ЭМЫ: " .. string.format("%.2f", player.emaBalance) .. " ۞")
    local transLabel = "Совершенно транзакций: "
    local fullTrans = transLabel .. tostring(player.transactions)
    local transX = math.floor((SCREEN_W - unicode.len(fullTrans)) / 2) + 1
    gpu.setForeground(colors.accent_main); gpu.set(transX, 13, transLabel)
    gpu.setForeground(colors.text_bright); gpu.set(transX + unicode.len(transLabel), 13, tostring(player.transactions))
    local regLabel = "Регистрация: "
    local regDate = player.regDate or "Неизвестно"
    local fullReg = regLabel .. regDate
    local regX = math.floor((SCREEN_W - unicode.len(fullReg)) / 2) + 1
    gpu.setForeground(colors.accent_main); gpu.set(regX, 14, regLabel)
    gpu.setForeground(colors.text_bright); gpu.set(regX + unicode.len(regLabel), 14, regDate)
    local agreeLabel = "Соглашение: "
    local agreeStatus = player.agreed and "ознакомлен" or "не ознакомлен"
    local fullAgree = agreeLabel .. agreeStatus
    local agreeX = math.floor((SCREEN_W - unicode.len(fullAgree)) / 2) + 1
    gpu.setForeground(colors.accent_main); gpu.set(agreeX, 15, agreeLabel)
    gpu.setForeground(player.agreed and colors.text_bright or colors.error); gpu.set(agreeX + unicode.len(agreeLabel), 15, agreeStatus)
    drawFlexButton(backButton); drawTempMessage()
end
function drawAccountLoading()
    clear(); drawScreenBorder(); drawCenteredText(12, "Загрузка...", colors.text_main)
    drawFlexButton(backButton); drawTempMessage()
end
-- ============================================================
-- НАВИГАЦИЯ
-- ============================================================
function goToBuy()
    if not player.agreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [СОГЛАШЕНИЕ] внизу.", colors.text_main)
        os.sleep(3); drawMainMenu(); return
    end
    ui.currentScreen = "shop_buy"; shop.mode = "buy"; shop.listScroll = 1; shop.horizontalScroll = 1
    shop.selectedIndex = 0; shop.hoveredIndex = 0; shop.selectedItem = nil; shop.search = ""
    shop.searchActive = false; shop.searchInput = ""; shop.stockFilterMode = "available"; shop.stockFilterOpen = false
    loadBuyItems(); drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
end
function goToSell()
    if not player.agreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [СОГЛАШЕНИЕ] внизу.", colors.text_main)
        os.sleep(3); drawMainMenu(); return
    end
    ui.currentScreen = "shop_sell"; shop.mode = "sell"; shop.listScroll = 1; shop.horizontalScroll = 1
    shop.selectedIndex = 0; shop.hoveredIndex = 0; shop.selectedItem = nil; shop.search = ""
    shop.searchActive = false; shop.searchInput = ""; shop.stockFilterOpen = false
    loadSellItems(); drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
end
function goToShop() ui.currentScreen = "shop"; drawShopMenu() end
function goToAccount()
    if not player.token then drawCenteredText(12, "Ошибка: нет авторизации", colors.error); return end
    ui.currentScreen = "account_loading"; auth.accountRequestTime = computer.uptime()
    drawAccountLoading()
    modem.send(serverAddress, 0xffef, serialization.serialize({op = "getAccount", name = player.name, token = player.token}))
end
function goToTop()
    ui.currentScreen = "top"; top.category = "balance"; top.page = 1; top.data = {}
    top.serverSeen = false
    requestTopFromServer(top.category)
    drawTopScreen()
end
function goToHistory()
    if not player.name then return end
    loadHistory()
    historyScroll = 1
    drawHistoryScreen()
end
function goToReport() ui.currentScreen = "report"; report.input = ""; drawReportScreen() end
function goToHelp() ui.currentScreen = "agreement"; drawAgreementScreen() end
function goBackToMenu()
    ui.showShopDenied = false; ui.currentScreen = "menu"; drawMainMenu()
    updateSelectorDisplay(nil); safeSelectorSetSlot(0, nil); safeSelectorSetSlot(1, nil)
end
local function submitReport()
    if not canSendReport() or report.input == "" then return end
    if player.token then
        modem.send(serverAddress, 0xffef, serialization.serialize({op = "report", name = player.name, token = player.token, text = report.input, time = getRealTimeString()}))
    end
    report.lastTime = getRealTimestamp()
    report.input = ""
    showTempMessage("✅ Сообщение отправлено! Ожидайте ответа.", 3)
    goBackToMenu()
end
local function refreshAndAgree()
    if player.agreed then goBackToMenu(); return end
    if player.token then
        modem.send(serverAddress, 0xffef, serialization.serialize({op = "agree", name = player.name, token = player.token}))
        drawCenteredText(20, "Отправка подтверждения...", colors.success)
    else
        goBackToMenu()
    end
end
local function retryAccountAfterTokenRefresh()
    if not player.name then return end
    modem.send(serverAddress, 0xffef, serialization.serialize({op="enter", name=player.name}))
    local start = computer.uptime()
    while computer.uptime() - start < 3 do
        local ev = safeEventPull(0.3)
        if ev[1] == "modem_message" then
            local sender = ev[3]; local data = ev[6]
            if sender == serverAddress then
                local success, msg = pcall(serialization.unserialize, data)
                if success and msg and msg.op == "welcome" and msg.token then
                    player.token = msg.token; player.coinBalance = msg.balance or 0.0; player.emaBalance = msg.emaBalance or 0.0
                    player.agreed = msg.agreed or false; auth.alreadyAuthorized = true
                    ui.currentScreen = "account_loading"; auth.accountRequestTime = computer.uptime()
                    drawAccountLoading()
                    modem.send(serverAddress, 0xffef, serialization.serialize({op = "getAccount", name = player.name, token = player.token}))
                    return
                end
            end
        elseif ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            player.name = nil; player.token = nil; auth.alreadyAuthorized = false
            ui.currentScreen = "welcome"; drawWelcomeScreen(); return
        end
    end
    ui.currentScreen = "menu"; drawMainMenu()
end
-- ============================================================
-- ПОКУПКА И ПРОДАЖА
-- ============================================================
scanPlayerInventory = function(targetName, targetDamage)
    local pimAddr = getPimAddr(); if not pimAddr then return 0 end
    targetDamage = targetDamage or 0; local total = 0
    local slots = 36
    local okSize, size = pcall(component.invoke, pimAddr, "getInventorySize")
    if okSize and tonumber(size) then slots = math.floor(tonumber(size)) end
    for slot = 1, slots do
        local okStack, stack = pcall(component.invoke, pimAddr, "getStackInSlot", slot)
        if okStack and stack then
            local qty = math.floor(tonumber(stack.size or stack.qty) or 0)
            if qty > 0 then
                local cleanName = tostring(stack.name or stack.label or stack.id or ""):gsub("§.", "")
                local cleanId = tostring(stack.id or stack.name or ""):gsub("§.", "")
                if (cleanName == targetName or cleanId == targetName) and (stack.damage or 0) == targetDamage then
                    total = total + qty
                end
            end
        end
    end
    if player.token then
        modem.send(serverAddress, 0xffef, serialization.serialize({op = "scan_report", name = player.name, token = player.token, target = targetName, found = total}))
    end
    return total
end
local function pimPush(pimAddr, slot, count)
    local variants = {
        {"pushItem", "down", slot, count},
        {"pushItem", slot, "down", count},
        {"push", "down", slot, count},
        {"pushItem", "down", slot},
    }
    for _, v in ipairs(variants) do
        local ok, res = pcall(component.invoke, pimAddr, v[1], v[2], v[3], v[4])
        if ok then
            if type(res) == "number" and res > 0 then return math.min(res, count) end
            if res == true then return count end
        end
    end
    return 0
end
local function extractToME(targetName, amount, targetDamage)
    local pimAddr = getPimAddr(); if not pimAddr or amount <= 0 then return 0 end
    targetDamage = targetDamage or 0; local extracted = 0
    local slots = 36
    local okSize, size = pcall(component.invoke, pimAddr, "getInventorySize")
    if okSize and tonumber(size) then slots = math.floor(tonumber(size)) end
    for slot = 1, slots do
        if extracted >= amount then break end
        local okStack, stack = pcall(component.invoke, pimAddr, "getStackInSlot", slot)
        if okStack and stack then
            local qty = math.floor(tonumber(stack.size or stack.qty) or 0)
            if qty > 0 then
                local cleanName = tostring(stack.name or stack.label or stack.id or ""):gsub("§.", "")
                local cleanId = tostring(stack.id or stack.name or ""):gsub("§.", "")
                if (cleanName == targetName or cleanId == targetName) and (stack.damage or 0) == targetDamage then
                    local toTake = math.min(qty, amount - extracted)
                    if toTake > 0 then
                        local moved = pimPush(pimAddr, slot, toTake)
                        if moved > 0 then extracted = extracted + moved end
                    end
                end
            end
        end
    end
    return extracted
end
function performSell()
    local sellOwner = player.name
    if not sellOwner or not checkPimSessionAlive(sellOwner) then return end
    if not player.agreed then
        drawCenteredText(17, "Сначала примите пользовательское соглашение", colors.error)
        if not pimAwareSleep(2, sellOwner) then return end
        ui.currentScreen = "menu"; drawMainMenu(); return
    end
    if not shop.sellConfirmItem then return end
    shop.showSellPopup = false; drawSellScanScreen()
    drawCenteredText(17, "Выполняется пополнение...", colors.accent_light)
    if not pimAwareSleep(0.2, sellOwner) then return end
    if not shop.sellConfirmItem then return end
    local realExtracted = extractToME(shop.sellConfirmItem.internalName, shop.foundAmount, shop.sellConfirmItem.damage or 0)
    if realExtracted == 0 then
        drawCenteredText(17, "Не удалось изъять предметы! Проверьте инвентарь.", colors.error)
        os.sleep(2); ui.currentScreen = "shop_sell"; drawBuyStatic(); drawBuyItemsList(); drawBuyButtons(); return
    end
    if not shop.sellConfirmItem then return end
    local value = realExtracted * shop.sellConfirmItem.price
    local curItem = shop.sellConfirmItem
    local coinGain, emaGain = 0, 0
    if curItem.internalName == "customnpcs:npcMoney" then
        player.emaBalance = player.emaBalance + value; emaGain = value
    else
        player.coinBalance = player.coinBalance + value; coinGain = value
    end
    player.transactions = player.transactions + 1
    updatePlayerStat("earned", value); updatePlayerStat("sells")
    updatePlayerStat("earnedCoin", coinGain); updatePlayerStat("earnedEma", emaGain)
    syncBalanceStats()
    addHistoryEntry("sell", curItem.displayName, realExtracted, coinGain, emaGain)
    if player.token then
        modem.send(serverAddress, 0xffef, serialization.serialize({op = "sell", name = player.name, token = player.token, item = curItem.displayName, internalName = curItem.internalName, qty = realExtracted, value = value}))
    end
    gpu.setBackground(colors.bg_main); gpu.fill(2, 17, SCREEN_W - 4, 1, " ")
    local cur = (curItem.internalName == "customnpcs:npcMoney") and "۞" or "₵"
    drawCenteredText(17, "Успешно! +" .. string.format("%.2f", value) .. " " .. cur, colors.success)
    if not pimAwareSleep(0.8, sellOwner) then return end
    ui.currentScreen = "shop_sell"; shop.showSellPopup = false
    shop.sellScanItem = nil
    drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
end
function performBuy()
    local purchaseOwner = player.name
    if not purchaseOwner or not checkPimSessionAlive(purchaseOwner) then return end
    if not player.agreed then
        drawCenteredText(20, "Сначала примите пользовательское соглашение", colors.error)
        if not pimAwareSleep(2, purchaseOwner) then return end
        ui.currentScreen = "menu"; drawMainMenu(); return
    end
    if not shop.purchaseItem then return end
    local me = component.me_interface; local item = shop.purchaseItem
    local actualQty = tonumber(item.qty) or 0
    if actualQty <= 0 then
        drawCenteredText(20, "Товар закончился! Обновление списка...", colors.error)
        if not pimAwareSleep(0.8, purchaseOwner) then return end
        loadBuyItems(); drawBuyStatic(); drawBuyItemsList(); drawBuyButtons(); ui.currentScreen = "shop_buy"; return
    end
    local qty = shop.purchaseQuantity
    if qty > actualQty then qty = actualQty; shop.purchaseQuantity = qty; drawPurchaseScreen() end
    if qty <= 0 then
        drawCenteredText(20, "Выберите количество!", colors.error)
        if not pimAwareSleep(0.8, purchaseOwner) then return end
        drawPurchaseScreen(); return
    end
    local totalCoin = (item.priceCoin or 0) * qty; local totalEma = (item.priceEma or 0) * qty
    if player.coinBalance < totalCoin or player.emaBalance < totalEma then
        shop.showInsufficientPopup = true; shop.insufficientBalanceCoin = player.coinBalance; shop.insufficientBalanceEma = player.emaBalance
        drawPurchaseScreen(); drawInsufficientPopup(); return
    end
    drawCenteredText(20, "Выполняется покупка...", colors.accent_light)
    if not pimAwareSleep(0.2, purchaseOwner) then return end
    local extracted = exportItemToPlayer(me, item, qty, 64, purchaseOwner)
    if not checkPimSessionAlive(purchaseOwner) then return end
    if extracted == 0 then
        drawPurchaseScreen(); drawCenteredText(20, "МЭ не смогла выдать этот вариант предмета", colors.error); return
    end
    item.qty = math.max(0, (tonumber(item.qty) or 0) - extracted)
    local ck = tostring(item.internalName) .. ":" .. tostring(item.damage or 0)
    if qtyCacheMap and qtyCacheMap[ck] then qtyCacheMap[ck] = math.max(0, qtyCacheMap[ck] - extracted) end
    if extracted < qty then
        local spentCoin = extracted * (item.priceCoin or 0); local spentEma = extracted * (item.priceEma or 0)
        player.coinBalance = player.coinBalance - spentCoin; player.emaBalance = player.emaBalance - spentEma
        player.transactions = player.transactions + 1
        updatePlayerStat("spent", spentCoin + spentEma); updatePlayerStat("spentCoin", spentCoin); updatePlayerStat("spentEma", spentEma)
        updatePlayerStat("purchases"); syncBalanceStats()
        addHistoryEntry("buy", item.displayName, extracted, -spentCoin, -spentEma)
        if player.token then
            modem.send(serverAddress, 0xffef, serialization.serialize({op = "buy", name = player.name, token = player.token, item = item.displayName, internalName = item.internalName, qty = extracted, value_coin = spentCoin, value_ema = spentEma}))
        end
        shop.partialExtracted = extracted; shop.partialRequested = qty
        shop.showPartialPopup = true; drawPurchaseScreen(); drawPartialPopup(); return
    end
    player.coinBalance = player.coinBalance - totalCoin; player.emaBalance = player.emaBalance - totalEma
    player.transactions = player.transactions + 1
    updatePlayerStat("spent", totalCoin + totalEma); updatePlayerStat("spentCoin", totalCoin); updatePlayerStat("spentEma", totalEma)
    updatePlayerStat("purchases"); syncBalanceStats()
    addHistoryEntry("buy", item.displayName, extracted, -totalCoin, -totalEma)
    if player.token then
        modem.send(serverAddress, 0xffef, serialization.serialize({op = "buy", name = player.name, token = player.token, item = item.displayName, internalName = item.internalName, qty = extracted, value_coin = totalCoin, value_ema = totalEma}))
    end
    local priceStr = ""
    if totalCoin > 0 then priceStr = priceStr .. string.format("%.2f", totalCoin) .. "₵" end
    if totalEma > 0 then
        if priceStr ~= "" then priceStr = priceStr .. " + " end
        priceStr = priceStr .. string.format("%.2f", totalEma) .. "۞"
    end
    shop.purchaseQuantity = 1
    if not pimAwareSleep(0.3, purchaseOwner) then return end
    ui.currentScreen = "shop_buy"
    showTempMessage("✅ Куплено " .. extracted .. " шт. за " .. priceStr, 4)
    drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
end
-- ============================================================
-- КВЕСТЫ
-- ============================================================
local function questAvailable(q)
    if not q or q.enabled == false then return false end
    if not q.internalName then return false end
    local stock = getActualItemQuantity(q.internalName, q.damage or 0)
    return stock >= (q.count or 1)
end
local function questAffordable(q)
    if not q then return false end
    return player.coinBalance >= (q.price or 0) and player.emaBalance >= (q.price_ema or 0)
end
function goToQuests()
    ui.currentScreen = "quests"
    if questSelected < 1 then questSelected = 1 end
    questScroll = 1
    drawQuestsScreen()
end
drawQuestsScreen = function()
    ui.currentScreen = "quests"; clear(); drawScreenBorder(); drawBalanceLine(3, 1)
    gpu.setForeground(colors.accent_light); gpu.set(3, 3, "📜 Квесты магазина")
    gpu.setBackground(colors.bg_tertiary); gpu.fill(2, 5, SCREEN_W - 4, 1, " ")
    gpu.setForeground(colors.text_bright)
    gpu.set(3, 5, "Квест"); gpu.set(26, 5, "Награда"); gpu.set(50, 5, "Кол-во"); gpu.set(60, 5, "₵ Coina"); gpu.set(72, 5, "۞ ЭМЫ"); gpu.set(84, 5, "Наличие")
    gpu.setBackground(colors.bg_main)
    local visibleRows = math.min(20, SCREEN_H - 12)
    if #quests == 0 then
        drawCenteredText(math.floor(SCREEN_H / 2), "Квестов пока нет. Создайте /home/questlist.lua", colors.text_dim)
    else
        if questSelected < 1 then questSelected = 1 end
        if questSelected > #quests then questSelected = #quests end
        if questSelected <= questScroll then questScroll = math.max(1, questSelected - 1) end
        if questSelected > questScroll + visibleRows then questScroll = questSelected - visibleRows end
        gpu.setBackground(colors.bg_main); gpu.fill(2, 7, SCREEN_W - 4, visibleRows, " ")
        for i = 1, visibleRows do
            local idx = questScroll + i - 1
            local q = quests[idx]
            if not q then break end
            local y = 6 + i
            local active = questAvailable(q) and questAffordable(q)
            local bg = (idx == questSelected) and colors.accent_dark or (i % 2 == 0 and colors.bg_secondary or colors.bg_main)
            local fg = active and colors.text_bright or colors.inactive
            gpu.setBackground(bg); gpu.fill(2, y, SCREEN_W - 4, 1, " ")
            gpu.setForeground(fg)
            gpu.set(3, y, unicode.sub(q.questName, 1, 21))
            gpu.set(26, y, unicode.sub(q.rewardName, 1, 22))
            gpu.set(50, y, tostring(q.count))
            gpu.setForeground(active and colors.gold or colors.inactive)
            gpu.set(60, y, string.format("%.2f", q.price))
            gpu.setForeground(active and colors.tomato or colors.inactive)
            gpu.set(72, y, string.format("%.2f", q.price_ema))
            gpu.setForeground(q.enabled and colors.success or colors.error)
            gpu.set(84, y, q.enabled and "Есть в наличии" or "Нет в наличии")
            gpu.setBackground(colors.bg_main)
        end
    end
    local q = quests[questSelected]
    local canDo = q and questAvailable(q) and questAffordable(q)
    drawFlexButton(backButton)
    drawFlexButton({x = math.floor(SCREEN_W / 2) + 10, y = SCREEN_H - 1, xs = 16, ys = 1, text = "[ ВЫПОЛНИТЬ ]", bg = colors.bg_button, fg = canDo and colors.accent_light or colors.inactive})
    drawTempMessage()
end
local function performQuest(q)
    local owner = player.name
    if not owner or not checkPimSessionAlive(owner) then return end
    if not player.agreed then showTempMessage("❌ Сначала примите соглашение", 3); return end
    if not q then return end
    if not questAvailable(q) then showTempMessage("❌ Квест недоступен: нет награды в МЭ", 3); drawQuestsScreen(); return end
    if not questAffordable(q) then showTempMessage("❌ Недостаточно средств", 3); drawQuestsScreen(); return end
    local me = component.me_interface
    player.coinBalance = player.coinBalance - (q.price or 0)
    player.emaBalance = player.emaBalance - (q.price_ema or 0)
    player.transactions = player.transactions + 1
    updatePlayerStat("spent", (q.price or 0) + (q.price_ema or 0))
    updatePlayerStat("spentCoin", q.price or 0)
    updatePlayerStat("spentEma", q.price_ema or 0)
    updatePlayerStat("purchases")
    syncBalanceStats()
    local extracted = exportItemToPlayer(me, q, q.count, 64, owner)
    if not checkPimSessionAlive(owner) then return end
    addHistoryEntry("buy", q.questName .. " (квест)", extracted, -(q.price or 0), -(q.price_ema or 0))
    if player.token then
        modem.send(serverAddress, 0xffef, serialization.serialize({op = "buy", name = player.name, token = player.token, item = q.questName, internalName = q.internalName, qty = extracted, value_coin = q.price or 0, value_ema = q.price_ema or 0}))
    end
    if extracted >= q.count then
        showTempMessage("✅ Квест выполнен: " .. q.questName, 5)
    elseif extracted > 0 then
        showTempMessage("⚠ Выдано " .. extracted .. " из " .. q.count .. " (мало места)", 5)
    else
        showTempMessage("❌ МЭ не смогла выдать награду", 4)
    end
    drawQuestsScreen()
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
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/buy_items.lua",  path = "/home/buy_items.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/shop_items.lua", path = "/home/shop_items.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/pimserver.lua",  path = "/home/pimserver.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/primarket.lua",  path = "/home/primarket.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/agreement.lua",  path = "/home/agreement.lua" },
}
function AdminUpdate.saveConfig(cfg)
    local f = io.open(AdminUpdate.CONFIG_PATH, "w"); if not f then return false end
    f:write(serialization.serialize(cfg)); f:close(); return true
end
function AdminUpdate.loadConfig()
    local cfg = nil
    if fs.exists(AdminUpdate.CONFIG_PATH) then
        local f = io.open(AdminUpdate.CONFIG_PATH, "r")
        if f then
            local raw = f:read("*a"); f:close()
            local ok, data = pcall(serialization.unserialize, raw)
            if ok and type(data) == "table" then cfg = data end
        end
    end
    if type(cfg) ~= "table" then cfg = {} end
    if type(cfg.admins) ~= "table" then cfg.admins = {"KaRMa__"} end
    if type(cfg.password) ~= "string" or cfg.password == "" then cfg.password = AdminUpdate.DEFAULT_PASSWORD end
    AdminUpdate.saveConfig(cfg); return cfg
end
function AdminUpdate.isAdmin(name, cfg)
    name = trimPlayerName(name); if name == "" then return false end
    cfg = cfg or AdminUpdate.loadConfig()
    for _, adminName in ipairs(cfg.admins or {}) do
        if samePlayerName(name, tostring(adminName or "")) then return true end
    end
    return false
end
function AdminUpdate.ulen(s) s = tostring(s or ""); local _, cont = s:gsub("[\128-\191]", ""); return #s - cont end
function AdminUpdate.drawFrame(x, y, w, h)
    local f = AdminUpdate.FRAME
    gpu.set(x, y, f.tl .. string.rep(f.h, w - 2) .. f.tr)
    for i = 1, h - 2 do gpu.set(x, y + i, f.v .. string.rep(" ", w - 2) .. f.v) end
    gpu.set(x, y + h - 1, f.bl .. string.rep(f.h, w - 2) .. f.br)
end
function AdminUpdate.drawPassword(password, statusText, statusColor)
    gpu.setResolution(SCREEN_W, SCREEN_H); gpu.setBackground(colors.bg_main); gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    local fw, fh = 60, 15; local fx = math.floor((SCREEN_W - fw) / 2) + 1; local fy = math.floor((SCREEN_H - fh) / 2) + 1
    local title = "АДМИН-ПАНЕЛЬ"
    gpu.setForeground(colors.text_bright); gpu.set(fx + math.floor((fw - unicode.len(title)) / 2), fy - 1, title)
    gpu.setForeground(colors.border_accent); AdminUpdate.drawFrame(fx, fy, fw, fh)
    drawCenteredText(fy + 3, "Введите пароль администратора", colors.text_bright)
    local fieldW = 34; local fieldX = fx + math.floor((fw - fieldW) / 2); local fieldY = fy + 6
    gpu.setBackground(colors.bg_button); gpu.fill(fieldX, fieldY, fieldW, 1, " ")
    gpu.setForeground(colors.accent_light)
    local masked = string.rep("*", unicode.len(password or ""))
    if unicode.len(masked) > fieldW - 2 then masked = unicode.sub(masked, -(fieldW - 2)) end
    gpu.set(fieldX + 1, fieldY, masked .. "_"); gpu.setBackground(colors.bg_main)
    if statusText and statusText ~= "" then drawCenteredText(fy + 9, statusText, statusColor or colors.text_main)
    else drawCenteredText(fy + 9, "Enter - войти   Esc - назад", colors.text_dim) end
    drawCenteredText(fy + 11, "Пароль на экране не отображается", colors.text_dim)
end
function AdminUpdate.redrawShop()
    if ui.currentScreen == "welcome" then drawWelcomeScreen()
    elseif ui.currentScreen == "auth" then drawAuthScreen()
    elseif ui.currentScreen == "menu" then drawMainMenu()
    elseif ui.currentScreen == "shop" then drawShopMenu()
    elseif ui.currentScreen == "quests" then drawQuestsScreen()
    elseif ui.currentScreen == "history" then drawHistoryScreen()
    elseif ui.currentScreen == "shop_buy" or ui.currentScreen == "shop_sell" then drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
    elseif ui.currentScreen == "purchase" then
        if not shop.purchaseItem then ui.currentScreen = "menu"; drawMainMenu(); return end
        drawPurchaseScreen()
        if shop.showInsufficientPopup then drawInsufficientPopup() end
        if shop.showPartialPopup then drawPartialPopup() end
        if shop.showInventoryFullPopup then drawInventoryFullPopup() end
    elseif ui.currentScreen == "sell_scan" then
        if not shop.sellConfirmItem then ui.currentScreen = "menu"; drawMainMenu(); return end
        drawSellScanScreen()
    elseif ui.currentScreen == "account" then drawAccount()
    elseif ui.currentScreen == "account_loading" then drawAccountLoading()
    elseif ui.currentScreen == "report" then drawReportScreen()
    elseif ui.currentScreen == "feedbacks" then drawFeedbacksList()
    elseif ui.currentScreen == "feedback_input" then drawFeedbackInputScreen()
    elseif ui.currentScreen == "top" then drawTopScreen()
    elseif ui.currentScreen == "agreement" then drawAgreementScreen()
    else drawWelcomeScreen()
    end
end
function AdminUpdate.drawInterface()
    local mw, mh = gpu.maxResolution()
    gpu.setResolution(mw >= SCREEN_W and SCREEN_W or mw, mh >= SCREEN_H and SCREEN_H or mh)
    gpu.setBackground(colors.bg_main); gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    local fw, fh = 60, 15; local fx = math.floor((SCREEN_W - fw) / 2) + 1; local fy = math.floor((SCREEN_H - fh) / 2) + 1
    local title = "ОБНОВЛЕНИЕ"
    gpu.setForeground(colors.text_bright); gpu.set(fx + math.floor((fw - AdminUpdate.ulen(title)) / 2), fy - 1, title)
    gpu.setForeground(colors.border_accent); AdminUpdate.drawFrame(fx, fy, fw, fh)
    gpu.setForeground(colors.text_bright); gpu.set(1, SCREEN_H, "By KaRMa__")
    return fx, fy, fw, fh
end
function AdminUpdate.drawBar(x, y, w, p)
    p = math.max(0, math.min(1, tonumber(p) or 0)); local inner = w - 2; local filled = math.floor(inner * p)
    gpu.setForeground(colors.text_bright); gpu.set(x, y, "[" .. string.rep("█", filled) .. string.rep(" ", inner - filled) .. "]")
end
function AdminUpdate.showStatus(fx, fy, fw, fh, l1, l2, l3, color)
    local cy = fy + math.floor(fh / 2) - 1
    local function clipLine(t, w) t = tostring(t); if unicode.len(t) <= w then return t end; return unicode.sub(t, 1, w) end
    gpu.setForeground(color)
    gpu.set(fx + 2, cy, clipLine(l1 or "", fw - 4))
    gpu.set(fx + 2, cy + 1, clipLine(l2 or "", fw - 4))
    gpu.set(fx + 2, cy + 2, clipLine(l3 or "", fw - 4))
end
function AdminUpdate.downloadFile(url, path)
    local ok = os.execute('wget -fq "' .. url .. '" "' .. path .. '"')
    if not (ok and fs.exists(path) and fs.size(path) > 0) then os.execute('wget -f "' .. url .. '" "' .. path .. '"') end
    return fs.exists(path) and fs.size(path) > 0
end
function AdminUpdate.setupAutorun()
    if not fs.exists("/autorun") then fs.makeDirectory("/autorun") end
    local f = io.open("/autorun/99_start.lua", "w"); if not f then return false end
    f:write('local fs = require("filesystem")\nos.sleep(2)\nif fs.exists("/.just_updated") then\nfs.remove("/.just_updated")\nif fs.exists("/home/primarket.lua") then os.execute("/home/primarket.lua") end\nend\nif fs.exists("/loader.lua") then loadfile("/loader.lua")("watch") end\n')
    f:close(); return true
end
function AdminUpdate.run()
    local fx, fy, fw, fh = AdminUpdate.drawInterface()
    AdminUpdate.drawBar(fx, fy + fh + 1, fw, 0); local total, done = #AdminUpdate.FILES, 0
    for _, file in ipairs(AdminUpdate.FILES) do
        fx, fy, fw, fh = AdminUpdate.drawInterface()
        AdminUpdate.drawBar(fx, fy + fh + 1, fw, done / total)
        AdminUpdate.showStatus(fx, fy, fw, fh, "Идёт скачивание:", fs.name(file.path), "Скачано: " .. done .. "/" .. total, colors.text_bright)
        local success = false
        for attempt = 1, 2 do
            if AdminUpdate.downloadFile(file.url, file.path) then success = true; break end
            os.sleep(1)
        end
        fx, fy, fw, fh = AdminUpdate.drawInterface()
        if success then
            done = done + 1
            AdminUpdate.showStatus(fx, fy, fw, fh, "Готово:", fs.name(file.path), "Скачано: " .. done .. "/" .. total, colors.success)
        else
            AdminUpdate.showStatus(fx, fy, fw, fh, "Ошибка:", fs.name(file.path), "Скачано: " .. done .. "/" .. total, colors.error)
        end
        AdminUpdate.drawBar(fx, fy + fh + 1, fw, done / total); os.sleep(0.3)
    end
    if done == total then
        AdminUpdate.setupAutorun()
        local flag = io.open(AdminUpdate.FLAG_PATH, "w"); if flag then flag:write("1"); flag:close() end
        for i = 5, 1, -1 do
            fx, fy, fw, fh = AdminUpdate.drawInterface(); AdminUpdate.drawBar(fx, fy + fh + 1, fw, 1)
            AdminUpdate.showStatus(fx, fy, fw, fh, "Обновление завершено!", "", "Перезагрузка через " .. i .. " сек...", colors.success); os.sleep(1)
        end
        computer.shutdown(true); return true
    end
    fx, fy, fw, fh = AdminUpdate.drawInterface(); AdminUpdate.drawBar(fx, fy + fh + 1, fw, done / total)
    AdminUpdate.showStatus(fx, fy, fw, fh, "Ошибка при обновлении!", "", "Перезагрузка не выполнена.", colors.error); os.sleep(3); return false
end
function AdminUpdate.openPanel(triggerPlayer)
    local cfg = AdminUpdate.loadConfig(); local adminName = trimPlayerName(triggerPlayer or "")
    if not AdminUpdate.isAdmin(adminName, cfg) then
        local oldScreen = ui.currentScreen
        AdminUpdate.drawPassword("", "ДОСТУП ЗАПРЕЩЁН", colors.error)
        os.sleep(1.5); ui.currentScreen = oldScreen; AdminUpdate.redrawShop(); return false
    end
    local previousScreen = ui.currentScreen; local password = ""
    AdminUpdate.drawPassword(password, "", colors.text_main)
    while true do
        local ev = safeEventPull(0.25); local e = ev[1]
        if e == "player_off" or e == "pim_player_leave" then
            local leavingPlayer = trimPlayerName(extractEventPlayerName(ev) or ev[2] or "")
            if player.name and (leavingPlayer == "" or samePlayerName(leavingPlayer, player.name)) then closePimSession(); return false end
        elseif e == "key_down" then
            local char = tonumber(ev[3]) or 0; local code = tonumber(ev[4]) or 0
            local keyPlayer = trimPlayerName(ev[5] or "")
            if keyPlayer ~= "" and not samePlayerName(keyPlayer, adminName) then
            elseif char == 27 or (keyboard.keys and code == keyboard.keys.escape) then
                ui.currentScreen = previousScreen; AdminUpdate.redrawShop(); return false
            elseif char == 8 or (keyboard.keys and code == keyboard.keys.back) then
                if unicode.len(password) > 0 then password = unicode.sub(password, 1, -2) end
                AdminUpdate.drawPassword(password, "", colors.text_main)
            elseif char == 13 or (keyboard.keys and code == keyboard.keys.enter) then
                if password == tostring(cfg.password or "") then
                    AdminUpdate.drawPassword(password, "Доступ разрешён. Запуск обновления...", colors.success)
                    os.sleep(0.5); local ok = AdminUpdate.run()
                    if not ok then ui.currentScreen = previousScreen; AdminUpdate.redrawShop() end
                    return ok
                end
                password = ""; AdminUpdate.drawPassword(password, "Неверный пароль!", colors.error)
            elseif char >= 32 and char <= 0x10FFFF then
                if unicode.len(password) < 32 then password = password .. unicode.char(char) end
                AdminUpdate.drawPassword(password, "", colors.text_main)
            end
        end
    end
end
-- ============================================================
-- ГЛАВНЫЙ ЦИКЛ
-- ============================================================
local function main()
    drawWelcomeScreen()
    modem.send(serverAddress, 0xffef, serialization.serialize({op="register", password=ACCESS_PASSWORD}))
    while true do
        local ev = nextShopEvent(0.5); local e = ev[1]
        if ui.currentScreen == "auth" and player.name and not player.token then
            local now = computer.uptime()
            if now - auth.lastSendTime >= auth.retryInterval then sendEnterRequest() end
            if now - auth.startTime >= auth.noResponseNotice then drawTechWorkScreen() end
        end
        if ui.currentScreen == "account_loading" then
            if computer.uptime() - auth.accountRequestTime >= auth.accountTimeout then retryAccountAfterTokenRefresh() end
        end
        if player.name and (e == "touch" or e == "scroll" or e == "key_down") then
            local inputPlayer
            if e == "touch" or e == "scroll" then inputPlayer = ev[6] elseif e == "key_down" then inputPlayer = ev[5] end
            if not isPimOwner(inputPlayer) then goto continue end
        end
        if e == "key_down" and tonumber(ev[3]) == 7 then AdminUpdate.openPanel(ev[5]); goto continue end
        if e == "touch" then
            local x, y = ev[3], ev[4]
            if shop.showSellPopup and ui.currentScreen == "sell_scan" then
                local popupWidth = 45; local popupHeight = 11
                local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
                if isButtonClicked({x=popupX+5, y=popupY+8, xs=15, ys=1}, x, y) then performSell()
                elseif isButtonClicked({x=popupX+popupWidth-18, y=popupY+8, xs=14, ys=1}, x, y) then shop.showSellPopup = false; drawSellScanScreen()
                elseif not (x >= popupX and x < popupX + popupWidth and y >= popupY and y < popupY + popupHeight) then shop.showSellPopup = false; drawSellScanScreen()
                end
                goto continue
            elseif shop.showInsufficientPopup then
                local popupWidth = 55; local popupHeight = 12
                local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
                if isButtonClicked({x = popupX + math.floor((popupWidth - 10) / 2), y = popupY+9, xs = 10, ys = 1}, x, y) then
                    shop.showInsufficientPopup = false; ui.currentScreen = "shop_buy"; drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
                end
                goto continue
            elseif shop.showPartialPopup then
                local popupWidth = 55; local popupHeight = 10
                local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
                if isButtonClicked({x = popupX + math.floor((popupWidth - 10) / 2), y = popupY+7, xs = 10, ys = 1}, x, y) then
                    shop.showPartialPopup = false; ui.currentScreen = "shop_buy"; drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
                end
                goto continue
            elseif shop.showInventoryFullPopup then
                local popupWidth = 55; local popupHeight = 10
                local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
                if isButtonClicked({x = popupX + math.floor((popupWidth - 10) / 2), y = popupY+7, xs = 10, ys = 1}, x, y) then
                    shop.showInventoryFullPopup = false; ui.currentScreen = "shop_buy"; drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
                end
                goto continue
            elseif ui.currentScreen == "shop_buy" or ui.currentScreen == "shop_sell" then
                if shop.mode == "buy" then
                    if shop.stockFilterOpen then
                        if isButtonClicked(stockAvailableButton, x, y) then applyStockFilter("available"); goto continue
                        elseif isButtonClicked(stockAllButton, x, y) then applyStockFilter("all"); goto continue
                        elseif isButtonClicked(stockFilterButton, x, y) then shop.stockFilterOpen = false; drawBuyButtons(); goto continue
                        else shop.stockFilterOpen = false; drawBuyButtons()
                        end
                    elseif isButtonClicked(stockFilterButton, x, y) then shop.stockFilterOpen = true; drawBuyButtons(); goto continue
                    end
                end
                local visibleRows = listVisibleRows()
                if y == 3 then
                    local sx, sw, cx, cw = getSearchRects()
                    if x >= sx and x < sx + sw then
                        shop.searchActive = true; shop.searchInput = shop.search; drawSearchBar(); goto continue
                    end
                    if x >= cx and x < cx + cw then
                        shop.search = ""; shop.searchInput = ""; shop.searchActive = false; shop.listScroll = 1
                        drawSearchBar(); drawBuyItemsList(); goto continue
                    end
                end
                if y >= 7 and y <= 6 + visibleRows and x >= 2 and x <= SCREEN_W - 3 then
                    local clickedIndex = shop.listScroll + (y - 6) - 1
                    local item = shop.filteredItems[clickedIndex]
                    if item and (shop.mode ~= "buy" or item.qty > 0) then
                        shop.selectedIndex = clickedIndex; shop.selectedItem = item; shop.hoveredIndex = 0
                        updateSelectorDisplay(shop.selectedItem); drawBuyItemsList(); drawBuyButtons()
                    end
                    goto continue
                end
                if x >= SCREEN_W - 2 and y >= 7 and y <= 6 + visibleRows then
                    local total = #shop.filteredItems
                    if total > visibleRows then
                        shop.listScroll = math.floor(((y - 6) - 1) * (total - visibleRows) / visibleRows) + 1; drawBuyItemsList()
                    end
                    goto continue
                end
                if isButtonClicked(backButton, x, y) then
                    ui.currentScreen = "shop"; shop.selectedIndex = 0; shop.selectedItem = nil; shop.hoveredIndex = 0
                    updateSelectorDisplay(nil); drawShopMenu(); goto continue
                end
                if isButtonClicked(nextButton, x, y) then
                    if shop.selectedItem and (shop.mode ~= "buy" or shop.selectedItem.qty > 0) then
                        if shop.mode == "buy" then
                            local needCoin = shop.selectedItem.priceCoin or 0; local needEma = shop.selectedItem.priceEma or 0
                            if (needCoin > 0 and player.coinBalance < needCoin) or (needEma > 0 and player.emaBalance < needEma) then
                                shop.showInsufficientPopup = true; shop.insufficientBalanceCoin = player.coinBalance; shop.insufficientBalanceEma = player.emaBalance
                                drawBuyStatic(); drawBuyItemsList(); drawBuyButtons(); drawInsufficientPopup(); goto continue
                            end
                            goToPurchase(shop.selectedItem)
                        else
                            shop.sellConfirmItem = shop.selectedItem; shop.foundAmount = 0; shop.showSellPopup = false; drawSellScanScreen()
                        end
                    end
                    goto continue
                end
                if shop.searchActive then
                    shop.search = shop.searchInput; shop.searchActive = false; shop.listScroll = 1
                    shop.selectedIndex = 0; shop.selectedItem = nil; shop.hoveredIndex = 0
                    drawSearchBar(); drawBuyItemsList(); drawBuyButtons(); goto continue
                end
            elseif ui.currentScreen == "purchase" then
                if y == SCREEN_H - 1 and x >= math.floor(SCREEN_W / 2) - 18 and x <= math.floor(SCREEN_W / 2) - 7 then
                    if shop.mode == "buy" then ui.currentScreen = "shop_buy" else ui.currentScreen = "shop_sell" end
                    drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
                elseif y == SCREEN_H - 1 and x >= math.floor(SCREEN_W / 2) + 6 and x <= math.floor(SCREEN_W / 2) + 17 then
                    performBuy()
                end
            elseif ui.currentScreen == "sell_scan" then
                if isButtonClicked(backButton, x, y) then
                    ui.currentScreen = "shop_sell"; shop.showSellPopup = false; shop.sellScanItem = nil
                    drawBuyStatic(); drawBuyItemsList(); drawBuyButtons()
                elseif isButtonClicked(sellScanSellButton, x, y) then
                    local amount = math.max(0, math.min(math.floor(tonumber(shop.sellAmountInput) or 0), shop.sellInvCount or 0, shop.sellConfirmItem and shop.sellConfirmItem.qty or 0))
                    if amount > 0 then
                        shop.foundAmount = amount; shop.showSellPopup = true; drawSellScanScreen()
                    else
                        showTempMessage("❌ Укажите количество больше 0", 2)
                    end
                end
            elseif ui.currentScreen == "quests" then
                local visibleRows = math.min(20, SCREEN_H - 12)
                if y >= 7 and y <= 6 + visibleRows and x >= 2 and x <= SCREEN_W - 3 then
                    local idx = questScroll + (y - 6) - 1
                    if quests[idx] then questSelected = idx; drawQuestsScreen() end
                elseif isButtonClicked(backButton, x, y) then
                    ui.currentScreen = "shop"; drawShopMenu()
                elseif y == SCREEN_H - 1 and x >= math.floor(SCREEN_W / 2) + 10 and x <= math.floor(SCREEN_W / 2) + 25 then
                    local q = quests[questSelected]
                    if q and questAvailable(q) and questAffordable(q) then performQuest(q) end
                end
            elseif ui.currentScreen == "history" then
                local list = getHistoryList(player.name or "")
                local perEntry, listTop, listBottom, visibleEntries = historyMetrics()
                local maxScroll = math.max(1, #list - visibleEntries + 1)
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                elseif isButtonClicked({x = math.floor(SCREEN_W / 2) - 20, y = SCREEN_H - 1, xs = 8, ys = 1}, x, y) then
                    historyScroll = math.max(1, historyScroll - visibleEntries); drawHistoryScreen()
                elseif isButtonClicked({x = math.floor(SCREEN_W / 2) + 12, y = SCREEN_H - 1, xs = 8, ys = 1}, x, y) then
                    historyScroll = math.min(maxScroll, historyScroll + visibleEntries); drawHistoryScreen()
                elseif y >= listTop and y <= listBottom and x >= SCREEN_W - 3 then
                    local pos = math.floor(((y - listTop) / math.max(1, listBottom - listTop)) * maxScroll) + 1
                    historyScroll = math.max(1, math.min(pos, maxScroll)); drawHistoryScreen()
                end
            elseif ui.currentScreen == "menu" then
                for name, btn in pairs(menuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "shop" then
                            if player.agreed then goToShop() else ui.showShopDenied = true; drawMainMenu() end
                        elseif name == "account" then ui.showShopDenied = false; goToAccount() end
                        break
                    end
                end
                if y == SCREEN_H then
                    for _, item in ipairs(getBottomPanelItems()) do
                        if x >= item.x and x < item.x + unicode.len(item.text) then
                            ui.showShopDenied = false
                            if item.id == "report" then goToReport()
                            elseif item.id == "agreement" then goToHelp()
                            elseif item.id == "feedbacks" then
                                ui.currentScreen = "feedbacks"
                                loadFeedbacksFromServer()
                                drawFeedbacksList()
                            elseif item.id == "top" then goToTop()
                            elseif item.id == "history" then goToHistory()
                            end
                            break
                        end
                    end
                end
            elseif ui.currentScreen == "top" then
                if handleTopCategoryClick(x, y) then goto continue end
                if isButtonClicked({x = math.floor(SCREEN_W / 2) - 20, y = SCREEN_H - 1, xs = 8, ys = 1}, x, y) and top.page > 1 then
                    top.page = top.page - 1; drawTopScreen(); goto continue
                end
                if isButtonClicked({x = math.floor(SCREEN_W / 2) + 12, y = SCREEN_H - 1, xs = 8, ys = 1}, x, y) and top.page < top.totalPages then
                    top.page = top.page + 1; drawTopScreen(); goto continue
                end
                if isButtonClicked({x = math.floor(SCREEN_W / 2) - 6, y = SCREEN_H - 1, xs = 12, ys = 1}, x, y) then goBackToMenu(); goto continue end
            elseif ui.currentScreen == "agreement" then
                local clicked = false
                if AGREE_BTN and isButtonClicked(AGREE_BTN, x, y) then clicked = true end
                if clicked then refreshAndAgree()
                elseif isButtonClicked(backButton, x, y) then goBackToMenu()
                end
            elseif ui.currentScreen == "account" or ui.currentScreen == "account_loading" then
                if isButtonClicked(backButton, x, y) then goBackToMenu() end
            elseif ui.currentScreen == "shop" then
                for name, btn in pairs(shopMenuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "buy" then goToBuy()
                        elseif name == "sell" then goToSell()
                        elseif name == "quests" then goToQuests() end
                        break
                    end
                end
                if isButtonClicked(backButton, x, y) then goBackToMenu() end
            elseif ui.currentScreen == "report" then
                if isButtonClicked(backButton, x, y) then goBackToMenu()
                elseif canSendReport() and isButtonClicked(getReportSendButton(), x, y) then submitReport()
                end
            elseif ui.currentScreen == "feedbacks" then
                if isButtonClicked({x=5, y=SCREEN_H - 1, xs=11, ys=1}, x, y) then ui.currentScreen = "menu"; drawMainMenu(); goto continue end
                if isButtonClicked({x=math.floor(SCREEN_W / 2) - 7, y=SCREEN_H - 1, xs=14, ys=1}, x, y) then
                    if feedbacks.playerHasFeedback then showTempMessage("Вы уже оставляли отзыв!", 2)
                    else feedbacks.input = ""; feedbacks.rating = 0; feedbacks.editMode = true; drawFeedbackInputScreen()
                    end
                    goto continue
                end
                if isButtonClicked({x=SCREEN_W - 30, y=SCREEN_H - 1, xs=7, ys=1}, x, y) and feedbacks.page > 1 then feedbacks.page = feedbacks.page - 1; drawFeedbacksList(); goto continue end
                if isButtonClicked({x=SCREEN_W - 20, y=SCREEN_H - 1, xs=7, ys=1}, x, y) and feedbacks.page < feedbacks.totalPages then feedbacks.page = feedbacks.page + 1; drawFeedbacksList(); goto continue end
            elseif ui.currentScreen == "feedback_input" then
                local starY = 12; local starX = getStarX()
                for i = 1, 5 do
                    local sx = starX + (i - 1) * 3
                    if x >= sx and x <= sx + 2 and y >= starY and y <= starY + 1 then
                        feedbacks.rating = (feedbacks.rating == i) and 0 or i
                        drawFeedbackInputScreen(); goto continue
                    end
                end
                if isButtonClicked({x=math.floor(SCREEN_W / 2) - 18, y=SCREEN_H - 1, xs=12, ys=1}, x, y) then
                    feedbacks.editMode = false; feedbacks.input = ""; feedbacks.rating = 0
                    ui.currentScreen = "feedbacks"; drawFeedbacksList(); goto continue
                end
                if isButtonClicked({x=math.floor(SCREEN_W / 2) + 6, y=SCREEN_H - 1, xs=15, ys=1}, x, y) and feedbacks.input ~= "" then
                    if player.token then
                        modem.send(serverAddress, 0xffef, serialization.serialize({op = "add_feedback", name = player.name, token = player.token, text = feedbacks.input, rating = feedbacks.rating, time = getRealTimeString()}))
                        showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                    end
                    feedbacks.editMode = false; feedbacks.input = ""; feedbacks.rating = 0
                    ui.currentScreen = "feedbacks"; drawFeedbacksList(); goto continue
                end
            end
        elseif e == "scroll" and (ui.currentScreen == "shop_buy" or ui.currentScreen == "shop_sell") then
            local direction = ev[5]; local x = ev[3]; local y = ev[4]
            local visibleRows = listVisibleRows()
            if x >= 2 and x <= SCREEN_W - 3 and y >= 7 and y <= 6 + visibleRows then
                local steps = 0
                if direction == -1 then steps = 1 elseif direction == 1 then steps = -1 end
                while true do
                    local ev2 = safeEventPull(0)
                    if not ev2[1] then break end
                    if ev2[1] == "scroll" and (ui.currentScreen == "shop_buy" or ui.currentScreen == "shop_sell") then
                        if ev2[5] == -1 then steps = steps + 1
                        elseif ev2[5] == 1 then steps = steps - 1 end
                    else
                        deferShopEvent(ev2)
                        break
                    end
                end
                if steps ~= 0 then smoothScroll(steps) end
            end
        elseif e == "scroll" and ui.currentScreen == "quests" then
            local direction = ev[5]
            if direction == -1 then questSelected = math.min(#quests, questSelected + 1); drawQuestsScreen()
            elseif direction == 1 then questSelected = math.max(1, questSelected - 1); drawQuestsScreen() end
        elseif e == "scroll" and ui.currentScreen == "history" then
            local list = getHistoryList(player.name or "")
            local perEntry, listTop, listBottom, visibleEntries = historyMetrics()
            local maxScroll = math.max(1, #list - visibleEntries + 1)
            local direction = ev[5]
            if direction == -1 then historyScroll = math.min(maxScroll, historyScroll + 1)
            elseif direction == 1 then historyScroll = math.max(1, historyScroll - 1) end
            drawHistoryScreen()
        elseif e == "key_down" and ui.currentScreen == "report" and canSendReport() then
            local ch = ev[3]
            if ch == 13 then submitReport()
            elseif ch == 8 then report.input = unicode.sub(report.input, 1, -2); drawReportScreen()
            elseif ch >= 32 then report.input = report.input .. unicode.char(ch); drawReportScreen()
            end
        elseif e == "key_down" and ui.currentScreen == "agreement" then
            if ev[3] == 13 then refreshAndAgree() end
        elseif e == "key_down" and ui.currentScreen == "purchase" then
            local ch = ev[3]
            if ch >= 48 and ch <= 57 then
                local digit = ch - 48
                shop.purchaseQuantity = shop.purchaseQuantity == 0 and digit or shop.purchaseQuantity * 10 + digit
                if shop.purchaseItem and shop.purchaseQuantity > shop.purchaseItem.qty then shop.purchaseQuantity = shop.purchaseItem.qty end
                drawPurchaseScreen()
            elseif ch == 8 then
                shop.purchaseQuantity = math.floor(shop.purchaseQuantity / 10)
                drawPurchaseScreen()
            elseif ch == 13 then
                performBuy()
            end
        elseif e == "key_down" and ui.currentScreen == "sell_scan" then
            local ch = ev[3]
            if ch == 13 then
                local amount = math.max(0, math.min(math.floor(tonumber(shop.sellAmountInput) or 0), shop.sellInvCount or 0, shop.sellConfirmItem and shop.sellConfirmItem.qty or 0))
                if amount > 0 then shop.foundAmount = amount; shop.showSellPopup = true; drawSellScanScreen() end
            elseif ch == 8 then
                shop.sellAmountInput = unicode.sub(shop.sellAmountInput or "", 1, -2); drawSellScanScreen()
            elseif ch >= 48 and ch <= 57 then
                if unicode.len(shop.sellAmountInput or "") < 7 then
                    shop.sellAmountInput = (shop.sellAmountInput or "") .. unicode.char(ch); drawSellScanScreen()
                end
            end
        elseif e == "key_down" and ui.currentScreen == "quests" then
            local ch = ev[3]; local code = ev[4]
            if code == 200 then questSelected = math.max(1, questSelected - 1); drawQuestsScreen()
            elseif code == 208 then questSelected = math.min(#quests, questSelected + 1); drawQuestsScreen()
            elseif ch == 13 then
                local q = quests[questSelected]
                if q and questAvailable(q) and questAffordable(q) then performQuest(q) end
            end
        elseif e == "key_down" and ui.currentScreen == "history" then
            local code = ev[4]
            local list = getHistoryList(player.name or "")
            local perEntry, listTop, listBottom, visibleEntries = historyMetrics()
            local maxScroll = math.max(1, #list - visibleEntries + 1)
            if code == 200 then historyScroll = math.max(1, historyScroll - 1); drawHistoryScreen()
            elseif code == 208 then historyScroll = math.min(maxScroll, historyScroll + 1); drawHistoryScreen()
            end
        elseif e == "key_down" and (ui.currentScreen == "shop_buy" or ui.currentScreen == "shop_sell") and shop.stockFilterOpen then
            if ev[3] == 27 then shop.stockFilterOpen = false; drawBuyButtons() end
            goto continue
        elseif e == "key_down" and (ui.currentScreen == "shop_buy" or ui.currentScreen == "shop_sell") and shop.searchActive then
            local ch = ev[3]
            if ch == 13 then
                shop.search = shop.searchInput; shop.searchActive = false; shop.listScroll = 1
                shop.selectedIndex = 0; shop.selectedItem = nil; shop.hoveredIndex = 0
                drawSearchBar(); drawBuyItemsList(); drawBuyButtons()
            elseif ch == 8 then shop.searchInput = unicode.sub(shop.searchInput, 1, -2); shop.search = shop.searchInput; shop.listScroll = 1; drawSearchBar(); drawBuyItemsList()
            elseif ch >= 32 then shop.searchInput = shop.searchInput .. unicode.char(ch); shop.search = shop.searchInput; shop.listScroll = 1; drawSearchBar(); drawBuyItemsList()
            end
            goto continue
        elseif e == "key_down" and (ui.currentScreen == "shop_buy" or ui.currentScreen == "shop_sell") and not shop.searchActive then
            local ch = ev[3]
            if ch >= 32 and ch <= 0x10FFFF then
                shop.searchActive = true; shop.searchInput = unicode.char(ch); shop.search = shop.searchInput
                shop.listScroll = 1; shop.selectedIndex = 0; shop.selectedItem = nil; shop.hoveredIndex = 0
                drawSearchBar(); drawBuyItemsList(); drawBuyButtons()
            end
            goto continue
        elseif e == "key_down" and ui.currentScreen == "feedback_input" and feedbacks.editMode then
            local ch = ev[3]
            if ch == 13 then
                if feedbacks.input ~= "" and player.token then
                    modem.send(serverAddress, 0xffef, serialization.serialize({op = "add_feedback", name = player.name, token = player.token, text = feedbacks.input, rating = feedbacks.rating, time = getRealTimeString()}))
                    showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                end
                feedbacks.editMode = false; feedbacks.input = ""; feedbacks.rating = 0
                ui.currentScreen = "feedbacks"; drawFeedbacksList()
            elseif ch == 8 then feedbacks.input = unicode.sub(feedbacks.input, 1, -2); drawFeedbackInputScreen()
            elseif ch >= 32 then
                if unicode.len(feedbacks.input) < 200 then feedbacks.input = feedbacks.input .. unicode.char(ch); drawFeedbackInputScreen() end
            end
            goto continue
        elseif e == "player_on" or e == "pim" or e == "pim_player_enter" then
            local playerName = trimPlayerName(ev[2] or "")
            if playerName == "" then goto continue end
            if player.name and samePlayerName(playerName, player.name) then
                if player.token then
                    auth.alreadyAuthorized = true
                    updatePlayerStat("visits")
                    syncBalanceStats()
                    if ui.currentScreen == "auth" or ui.currentScreen == "account_loading" then ui.currentScreen = "menu"; drawMainMenu() end
                elseif ui.currentScreen ~= "auth" then
                    ui.currentScreen = "auth"; auth.startTime = computer.uptime(); auth.lastSendTime = 0
                    drawAuthScreen(); sendEnterRequest()
                end
                goto continue
            end
            player.name = playerName; PimPresence.missCount = 0; PimPresence.lastPositive = computer.uptime()
            player.token = nil; auth.alreadyAuthorized = false
            player.coinBalance = 0.0; player.emaBalance = 0.0; player.agreed = false
            stats.visits = 0; stats.totalSpent = 0; stats.totalEarned = 0; stats.purchases = 0; stats.sells = 0
            stats.spentCoin = 0; stats.spentEma = 0
            ui.currentScreen = "auth"; auth.startTime = computer.uptime(); auth.lastSendTime = 0
            drawAuthScreen(); sendEnterRequest()
        elseif e == "player_off" or e == "pim_player_leave" then
            local leavingPlayer = trimPlayerName(ev[2] or "")
            if player.name and leavingPlayer ~= "" and not samePlayerName(leavingPlayer, player.name) then goto continue end
            closePimSession()
        elseif e == "modem_message" then
            local sender = ev[3]; local data = ev[6]
            if sender == serverAddress then
                local success, msg = pcall(serialization.unserialize, data)
                if success and msg then
                    if msg.op == "welcome" and msg.token then
                        player.token = msg.token; auth.startTime = 0; auth.lastSendTime = 0; auth.techWork = false
                        player.coinBalance = msg.balance or 0.0; player.emaBalance = msg.emaBalance or 0.0
                        player.transactions = msg.transactions or 0; player.regDate = msg.regDate or ""
                        player.agreed = msg.agreed or false; auth.alreadyAuthorized = true
                        updatePlayerStat("visits")
                        syncBalanceStats()
                        if selector then modem.send(serverAddress, 0xffef, serialization.serialize({op = "selector_status", name = player.name, token = player.token, available = true})) end
                        if ui.currentScreen == "auth" or ui.currentScreen == "account_loading" then ui.currentScreen = "menu"; drawMainMenu() end
                    elseif msg.op == "error" then
                        if ui.currentScreen == "auth" then drawTechWorkScreen() end
                    elseif msg.op == "accountData" then
                        if msg.error then retryAccountAfterTokenRefresh()
                        elseif ui.currentScreen == "account_loading" then
                            ui.currentScreen = "account"; player.agreed = msg.data.agreed or false; drawAccount()
                        end
                    elseif msg.op == "agree" then
                        if msg.success then
                            player.agreed = true; ui.showShopDenied = false
                            drawCenteredText(20, "Спасибо! Теперь вам доступен магазин.", colors.success)
                            os.sleep(0.8); drawMainMenu(); ui.currentScreen = "menu"
                        elseif msg.error and msg.message == "Токен устарел" then
                            drawCenteredText(20, "Сессия устарела. Обновление...", colors.accent_light); os.sleep(1)
                            modem.send(serverAddress, 0xffef, serialization.serialize({op="enter", name=player.name}))
                            local start = os.clock(); local refreshed = false
                            while os.clock() - start < 3 do
                                local evt = safeEventPull(0.3)
                                if evt[1] == "modem_message" then
                                    local s, d = evt[3], evt[6]
                                    if s == serverAddress then
                                        local ok2, m = pcall(serialization.unserialize, d)
                                        if ok2 and m and m.op == "welcome" and m.token then
                                            player.token = m.token; player.coinBalance = m.balance or 0.0; player.emaBalance = m.emaBalance or 0.0
                                            player.agreed = m.agreed or false; refreshed = true; break
                                        end
                                    end
                                elseif evt[1] == "player_off" or evt[1] == "pim_player_leave" then break
                                end
                            end
                            if refreshed then
                                modem.send(serverAddress, 0xffef, serialization.serialize({op = "agree", name = player.name, token = player.token}))
                                drawCenteredText(20, "Повторная отправка...", colors.success)
                            else
                                drawCenteredText(20, "Не удалось обновить сессию", colors.error); os.sleep(2); drawMainMenu(); ui.currentScreen = "menu"
                            end
                        else
                            drawCenteredText(20, "Ошибка: " .. (msg.message or "неизвестная"), colors.error); os.sleep(2); drawMainMenu(); ui.currentScreen = "menu"
                        end
                    elseif msg.op == "top_data" then
                        top.serverSeen = true
                        top.data = msg.list or {}; top.totalPages = msg.totalPages or 1; top.loading = false
                        if ui.currentScreen == "top" then drawTopScreen() end
                    elseif msg.op == "add_buy_item" then
                        local ok3, err = pcall(function()
                            local buyItems = dofile("/home/buy_items.lua")
                            if type(buyItems) ~= "table" then buyItems = {} end
                            local damage = tonumber(msg.damage) or 0
                            local priceCoin = tonumber(msg.price_coin) or tonumber(msg.price) or 0
                            local priceEma = tonumber(msg.price_ema) or 0
                            local msgNbtHash = msg.nbt_hash or msg.nbtHash or msg.nbt
                            if msgNbtHash ~= nil and tostring(msgNbtHash) == "" then msgNbtHash = nil end
                            local found = false
                            for _, item in ipairs(buyItems) do
                                local itemNbtHash = item.nbt_hash or item.nbtHash or item.nbt
                                if itemNbtHash ~= nil and tostring(itemNbtHash) == "" then itemNbtHash = nil end
                                if item.internalName == msg.internalName and (item.damage or 0) == damage and tostring(itemNbtHash or "") == tostring(msgNbtHash or "") then
                                    item.displayName = msg.displayName; item.price_coin = priceCoin; item.price_ema = priceEma; item.nbt_hash = msgNbtHash
                                    item.nbtHash = nil; item.nbt = nil
                                    if damage ~= 0 then item.damage = damage else item.damage = nil end
                                    found = true; break
                                end
                            end
                            if not found then
                                local newItem = {internalName = msg.internalName, displayName = msg.displayName, price_coin = priceCoin, price_ema = priceEma, nbt_hash = msgNbtHash}
                                if damage ~= 0 then newItem.damage = damage end
                                table.insert(buyItems, newItem)
                            end
                            local file = assert(io.open("/home/buy_items.lua", "w")); file:write("return " .. serialization.serialize(buyItems)); file:close()
                            buyItemsData = dofile("/home/buy_items.lua"); buyItemMap = {}
                            for _, item in ipairs(buyItemsData) do
                                local dmg = item.damage or 0; local nbt = item.nbt_hash or item.nbtHash or item.nbt
                                buyItemMap[item.internalName .. ":" .. dmg .. "|nbt=" .. tostring(nbt or "")] = item
                            end
                            qtyCacheMap = nil; qtyCacheAt = -1e9
                            if ui.currentScreen == "shop_buy" then loadBuyItems(); drawBuyStatic(); drawBuyItemsList(); drawBuyButtons() end
                        end)
                        if ok3 then modem.send(sender, 0xffef, serialization.serialize({op = "add_buy_item_response", success = true})); showTempMessage("✅ Предмет добавлен: " .. msg.displayName, 10)
                        else modem.send(sender, 0xffef, serialization.serialize({op = "add_buy_item_response", success = false, error = tostring(err)})); showTempMessage("❌ Ошибка добавления", 10)
                        end
                        goto continue
                    elseif msg.op == "add_buy_item_response" then
                    elseif msg.op == "reload_buy_items" then
                        buyItemsData = dofile("/home/buy_items.lua"); buyItemMap = {}
                        for _, item in ipairs(buyItemsData) do
                            local dmg = item.damage or 0; local nbt = item.nbt_hash or item.nbtHash or item.nbt
                            buyItemMap[item.internalName .. ":" .. dmg .. "|nbt=" .. tostring(nbt or "")] = item
                        end
                        qtyCacheMap = nil; qtyCacheAt = -1e9
                        if ui.currentScreen == "shop_buy" then loadBuyItems(); drawBuyStatic(); drawBuyItemsList(); drawBuyButtons() end
                        goto continue
                    elseif msg.op == "feedbacks_list" then
                        feedbacks.list = msg.feedbacks or {}; feedbacks.playerHasFeedback = msg.hasFeedback or false; feedbacks.page = 1
                        if ui.currentScreen == "feedbacks" then drawFeedbacksList() end
                        goto continue
                    elseif msg.op == "add_feedback_response" then
                        if msg.success then showTempMessage("✅ Отзыв добавлен!", 10); loadFeedbacksFromServer()
                        else showTempMessage("❌ Ошибка: " .. (msg.error or "неизвестная"), 10)
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
-- ОБРАБОТКА ОШИБОК
-- ============================================================
local function drawCrashPopup(errText)
    local popupWidth = 55; local popupHeight = 9
    local popupX = math.floor((SCREEN_W - popupWidth) / 2); local popupY = math.floor((SCREEN_H - popupHeight) / 2)
    gpu.setBackground(colors.bg_main); gpu.fill(1, 1, SCREEN_W, SCREEN_H, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)
    gpu.setForeground(colors.error); gpu.set(popupX + math.floor((popupWidth - unicode.len("ОШИБКА")) / 2), popupY, "ОШИБКА")
    gpu.setForeground(colors.text_main); gpu.set(popupX + 2, popupY + 2, errText:sub(1, popupWidth - 4))
    for i = 3, 1, -1 do
        gpu.setForeground(colors.success)
        local msg = "Перезагрузка через " .. i .. " сек..."
        gpu.set(popupX + math.floor((popupWidth - unicode.len(msg)) / 2), popupY + 5, msg); os.sleep(1)
    end
end
gpu.setResolution(SCREEN_W, SCREEN_H); gpu.setBackground(colors.bg_main)
while true do
    local ok, err = pcall(main)
    if not ok then
        local errText = tostring(err); local lowerErr = string.lower(errText)
        if string.find(lowerErr, "interrupted", 1, true) or string.find(lowerErr, "terminate", 1, true) then
        else
            pcall(drawCrashPopup, errText)
        end
    end
end
