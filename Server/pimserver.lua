-- ============================================================
-- PIM MARKET SERVER v2.3
-- + в карточке игрока (панель УПРАВЛЕНИЕ) для забаненных теперь:
--   КТО забанил | КОГДА (дата и время) | РАЗБАН (дата или навсегда) | ПРИЧИНА
-- + всё из v2.2: nowEpoch (реальное время, визиты и баны без 1970),
--   сортировка плиток, владелец-only кнопки, список админов,
--   автооткрытие .shrc, update.lua, анти-мерцание, поиски, закрепы
-- АВТОРИЗАЦИЯ НЕ ТРОНУТА: экран разработки -> PIM -> пароль
-- ============================================================
local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local unicode = require("unicode")
local computer = require("computer")
local gpu = component.gpu
local modem = component.modem

PORT_MARKET = 0xffef
PORT_SERVICE = 0xfffe
ACCESS_PASSWORD = "yVGF7wT"
TIMEZONE_OFFSET = 3 * 3600
SESSION_TIMEOUT = 31536000
OWNER = "KaRMa__"
DEFAULT_PASSWORD = "yVGF7wT"

modem.open(PORT_MARKET)
modem.open(PORT_SERVICE)

-- ============================================================
-- ФАЙЛЫ ДАННЫХ
-- ============================================================
DB_PATH = "/home/players.db"
STATS_PATH = "/home/global_stats.db"
ADMINS_PATH = "/home/admins.db"
REPORTS_DB_PATH = "/home/reports.db"
REPORTS_LOG_PATH = "/home/reports.log"
FEEDBACKS_PATH = "/home/feedbacks.db"
EVENTS_PATH = "/home/market_events.db"
EVENTS_LOG_PATH = "/home/market_server.log"
TX_PATH = "/home/market_transactions.db"
TOP_STATS_PATH = "/home/top_stats.db"

-- ============================================================
-- ЦВЕТА
-- ============================================================
C = {
  bg = 0x0B1018, panel = 0x111A27, panel2 = 0x172334, panel3 = 0x0E1622,
  border = 0x2C6E8F, accent = 0x00B6FF, accent2 = 0x35D0BA,
  white = 0xF2F6FA, text = 0xD7E2EC, muted = 0x8DA2B5,
  green = 0x55E98D, yellow = 0xFFD166, orange = 0xFF9F43, red = 0xFF6262,
  purple = 0xC792EA, select = 0x21455C, input = 0x071018,
  button = 0x1C3345, buttonHot = 0x27516B,
  starOff = 0x39424E,
}

-- ============================================================
-- ФАЙЛОВЫЕ ХЕЛПЕРЫ
-- ============================================================
function loadSerialized(path, fallback)
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

function saveSerialized(path, data)
  local file = io.open(path, "w")
  if not file then return false end
  file:write(serialization.serialize(data))
  file:close()
  return true
end

function appendText(path, text)
  local file = io.open(path, "a")
  if not file then return false end
  file:write(text .. "\n")
  file:close()
  return true
end

function readWholeFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data or ""
end

function writeWholeFile(path, text)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

function splitLines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

function trimLine(s)
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

-- ============================================================
-- АВТООТКРЫТИЕ: СТРОКА В .shrc
-- ============================================================
AUTORUN_LINE = "lua /home/pimserver.lua"
RC_PATHS = {"/home/.shrc", "/.shrc"}

function isAutorunEnabled()
  for _, path in ipairs(RC_PATHS) do
    local data = readWholeFile(path)
    if data then
      for _, line in ipairs(splitLines(data)) do
        if trimLine(line) == AUTORUN_LINE then return true end
      end
    end
  end
  return false
end

function setAutorun(enabled)
  local fail = nil
  for _, path in ipairs(RC_PATHS) do
    local data = readWholeFile(path)
    if enabled then
      if data == nil then data = "" end
      local lines = splitLines(data)
      local found = false
      for _, line in ipairs(lines) do
        if trimLine(line) == AUTORUN_LINE then found = true; break end
      end
      if not found then
        lines[#lines + 1] = AUTORUN_LINE
        if not writeWholeFile(path, table.concat(lines, "\n") .. "\n") then
          fail = "не удалось записать " .. path
        end
      end
    else
      if data then
        local out = {}
        for _, line in ipairs(splitLines(data)) do
          if trimLine(line) ~= AUTORUN_LINE then out[#out + 1] = line end
        end
        local text = #out > 0 and (table.concat(out, "\n") .. "\n") or ""
        if not writeWholeFile(path, text) then
          fail = "не удалось записать " .. path
        end
      end
    end
  end
  return fail == nil, fail
end

-- ============================================================
-- ВРЕМЯ (реальное через tmpfs; os.time() на этом ПК = 1970)
-- ============================================================
tmpfs = component.proxy(computer.tmpAddress())

function getRealTimestamp()
  local ok, result = pcall(function()
    local handle = tmpfs.open("/time", "w")
    tmpfs.write(handle, "time")
    tmpfs.close(handle)
    return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
  end)
  if ok and result then return result end
  return os.time() + TIMEZONE_OFFSET
end

_nowCacheU = -10
_nowValue = 0
function nowEpoch()
  local t = computer.uptime()
  if t - _nowCacheU >= 1 then
    _nowCacheU = t
    _nowValue = getRealTimestamp()
  end
  return _nowValue
end

function getRealTimeString() return os.date("%H:%M:%S", getRealTimestamp()) end
function getRealDateTimeString() return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp()) end
function getRealDateString() return os.date("%d.%m.%Y", getRealTimestamp()) end

function timeToMidnight()
  local now = getRealTimestamp()
  local dt = os.date("*t", now)
  local secondsLeft = (23 - dt.hour) * 3600 + (59 - dt.min) * 60 + (60 - dt.sec)
  if secondsLeft < 0 then secondsLeft = 0 end
  return string.format("%02d:%02d:%02d",
    math.floor(secondsLeft / 3600),
    math.floor((secondsLeft % 3600) / 60),
    secondsLeft % 60)
end

-- ============================================================
-- ТЕКСТ
-- ============================================================
function ulen(text) return unicode.len(tostring(text or "")) end
function usub(text, first, last) return unicode.sub(tostring(text or ""), first, last) end

function clip(text, width)
  text = tostring(text or "")
  if width <= 0 then return "" end
  if ulen(text) <= width then return text end
  if width <= 1 then return usub(text, 1, width) end
  return usub(text, 1, width - 1) .. "…"
end

function padRight(text, width)
  text = clip(text, width)
  local n = width - ulen(text)
  if n > 0 then text = text .. string.rep(" ", n) end
  return text
end

function normalizeName(name)
  if type(name) ~= "string" then return "" end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  return string.lower(name)
end

function eraseLastChar(text)
  text = tostring(text or "")
  local n = ulen(text)
  if n <= 0 then return "" end
  return usub(text, 1, n - 1)
end

function wrapText(text, width)
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

function trimPlayerName(name)
  if type(name) ~= "string" then return "" end
  return name:match("^%s*(.-)%s*$") or name
end

function samePlayerName(a, b)
  a = trimPlayerName(a)
  b = trimPlayerName(b)
  if a == "" or b == "" then return false end
  return unicode.lower(a) == unicode.lower(b)
end

function clamp(v, minV, maxV)
  if v < minV then return minV end
  if v > maxV then return maxV end
  return v
end

-- ============================================================
-- ДАННЫЕ
-- ============================================================
players = loadSerialized(DB_PATH, {})
globalStats = loadSerialized(STATS_PATH, {})
reports = loadSerialized(REPORTS_DB_PATH, {})
feedbacks = loadSerialized(FEEDBACKS_PATH, {})
eventLog = loadSerialized(EVENTS_PATH, {})
transactionHistory = loadSerialized(TX_PATH, {})
topStats = loadSerialized(TOP_STATS_PATH, {})

admins = {}
do
  local adminsRaw = loadSerialized(ADMINS_PATH, {})
  if type(adminsRaw) == "table" then
    if #adminsRaw > 0 then
      for _, name in ipairs(adminsRaw) do
        if type(name) == "string" and name ~= "" then
          admins[name] = samePlayerName(name, OWNER) and DEFAULT_PASSWORD or ""
        end
      end
    else
      for k, v in pairs(adminsRaw) do
        if type(k) == "string" and k ~= "" then admins[k] = tostring(v or "") end
      end
    end
  end
end
if not admins[OWNER] then admins[OWNER] = DEFAULT_PASSWORD end

if type(players) ~= "table" then players = {} end
if type(globalStats) ~= "table" then globalStats = {} end
if type(reports) ~= "table" then reports = {} end
if type(feedbacks) ~= "table" then feedbacks = {} end
if type(eventLog) ~= "table" then eventLog = {} end
if type(transactionHistory) ~= "table" then transactionHistory = {} end
if type(topStats) ~= "table" then topStats = {} end

function saveAdmins() saveSerialized(ADMINS_PATH, admins) end
saveAdmins()

-- ============================================================
-- БЫСТРЫЕ СОХРАНЕНИЯ
-- ============================================================
pendingSaves = {}
lastFlush = computer.uptime()

function deferSave(path, getter) pendingSaves[path] = getter end

function flushSaves(force)
  for path, getter in pairs(pendingSaves) do
    saveSerialized(path, getter())
  end
  pendingSaves = {}
  lastFlush = computer.uptime()
end

function countPlayers()
  local n = 0
  for _ in pairs(players) do n = n + 1 end
  return n
end

function ensureStats()
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
      date = today, buys = 0, sells = 0, buyCoin = 0, buyEma = 0,
      sellCoin = 0, sellEma = 0, buyItems = 0, sellItems = 0, newUsers = 0, reports = 0,
    }
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

function saveDB() saveSerialized(DB_PATH, players) end
function saveStats() deferSave(STATS_PATH, function() ensureStats() return globalStats end) end
function saveFeedbacks() saveSerialized(FEEDBACKS_PATH, feedbacks) end
function saveTopStats() deferSave(TOP_STATS_PATH, function() return topStats end) end
function saveTransactions() deferSave(TX_PATH, function() return transactionHistory end) end
function saveEvents() deferSave(EVENTS_PATH, function() return eventLog end) end

function saveReports()
  saveSerialized(REPORTS_DB_PATH, reports)
  local file = io.open(REPORTS_LOG_PATH, "w")
  if file then
    for i = 1, #reports do
      local r = reports[i]
      file:write(string.format("[%s] %s%s: %s\n",
        tostring(r.time or "?"),
        r.pinned and "[★] " or "",
        tostring(r.name or "?"),
        tostring(r.text or "")))
    end
    file:close()
  end
end

do
  local needMigrate = (#reports == 0) and filesystem.exists(REPORTS_LOG_PATH)
  if needMigrate then
    local file = io.open(REPORTS_LOG_PATH, "r")
    if file then
      for line in file:lines() do
        local tm, name, text = line:match("^%[(.-)%]%s+([^:]+):%s*(.*)$")
        if tm and name then
          table.insert(reports, 1, {time = tm, name = name, text = text or "", pinned = false})
        end
      end
      file:close()
      if #reports > 0 then saveReports() end
    end
  end
end

-- ============================================================
-- АДМИНИСТРАТОРЫ
-- ============================================================
function isAdmin(name)
  local target = normalizeName(name)
  if target == "" then return false end
  for adminName, _ in pairs(admins) do
    if normalizeName(adminName) == target then return true end
  end
  return false
end

function sortedAdmins()
  local list = {}
  for name, _ in pairs(admins) do table.insert(list, name) end
  table.sort(list, function(a, b) return normalizeName(a) < normalizeName(b) end)
  return list
end

function sortedAdminsOwnerFirst()
  local list = {}
  for name, _ in pairs(admins) do
    if not samePlayerName(name, OWNER) then list[#list + 1] = name end
  end
  table.sort(list, function(a, b) return normalizeName(a) < normalizeName(b) end)
  table.insert(list, 1, OWNER)
  return list
end

function adminPrefix(name)
  if samePlayerName(name, OWNER) then return "[Владелец] ", C.yellow end
  return "[Админ] ", C.accent2
end

function getAdminPassword(name)
  for adminName, pwd in pairs(admins) do
    if samePlayerName(adminName, name) then return pwd end
  end
  return nil
end

-- ============================================================
-- ЖУРНАЛ / СДЕЛКИ
-- ============================================================
function logColor(kind)
  if kind == "BUY" then return C.green end
  if kind == "SELL" then return C.accent end
  if kind == "USER" then return C.purple end
  if kind == "BALANCE" then return C.yellow end
  if kind == "ADMIN" then return C.orange end
  if kind == "REPORT" then return C.red end
  if kind == "FEEDBACK" then return C.accent2 end
  if kind == "BAN" then return C.red end
  if kind == "ERROR" then return C.red end
  if kind == "SYSTEM" then return C.muted end
  return C.muted
end

function addLog(kind, text)
  local entry = {time = getRealDateTimeString(), kind = tostring(kind or "INFO"), text = tostring(text or "")}
  table.insert(eventLog, 1, entry)
  while #eventLog > 300 do table.remove(eventLog) end
  saveEvents()
  appendText(EVENTS_LOG_PATH, string.format("[%s] [%s] %s", entry.time, entry.kind, entry.text))
end

function addTransaction(t)
  t.time = t.time or getRealDateTimeString()
  table.insert(transactionHistory, 1, t)
  while #transactionHistory > 300 do table.remove(transactionHistory) end
  saveTransactions()
end

-- ============================================================
-- СЕССИИ / MARKET
-- ============================================================
owner = nil
sessions = {}
markets = {}
modemLastSeen = {}
marketConnected = false
shopPaused = false
exitRequested = false

function validateSession(name, token)
  local s = sessions[name]
  return s and s.token == token and nowEpoch() - (s.lastAction or 0) < SESSION_TIMEOUT
end

-- ============================================================
-- ТОПЫ
-- ============================================================
topCache = nil
function invalidateTopCache() topCache = nil end

function getOrCreatePlayer(name)
  if not players[name] then
    players[name] = {
      balance = 0.0, emaBalance = 0.0, transactions = 0,
      regDate = getRealDateTimeString(), agreed = false, banned = false, hasFeedback = false,
    }
    ensureStats()
    globalStats.newUsers = globalStats.newUsers + 1
    globalStats.today.newUsers = globalStats.today.newUsers + 1
    saveDB()
    saveStats()
    invalidateTopCache()
    addLog("USER", "Новый пользователь: " .. name)
  end
  return players[name]
end

function ensureTopEntry(name)
  if not topStats[name] then
    topStats[name] = {
      visits = 0, purchases = 0, sells = 0,
      spentCoin = 0, spentEma = 0, earnedCoin = 0, earnedEma = 0,
      lastVisit = "", lastVisitEpoch = 0,
    }
  end
  return topStats[name]
end

function topIncr(name, field, amount)
  if not name or name == "" then return end
  local s = ensureTopEntry(name)
  s[field] = (tonumber(s[field]) or 0) + (tonumber(amount) or 1)
  saveTopStats()
  invalidateTopCache()
end

TOP_CATS = {
  {key = "balance", label = "БАЛАНС"},
  {key = "visits", label = "ВИЗИТЫ"},
  {key = "purchases", label = "ПОКУПКИ"},
  {key = "sells", label = "ПРОДАЖИ"},
  {key = "spent", label = "ТРАТЫ"},
}

function buildTopList(category)
  topCache = topCache or {}
  if topCache[category] then return topCache[category] end
  local sorted = {}
  if category == "balance" then
    for name, p in pairs(players) do
      local coin = tonumber(p.balance) or 0
      local ema = tonumber(p.emaBalance) or 0
      table.insert(sorted, {
        name = name, value = coin + ema, coin = coin, ema = ema,
        spentCoin = 0, spentEma = 0, earnedCoin = 0, earnedEma = 0,
        visits = 0, purchases = 0, sells = 0,
      })
    end
  else
    for name, _ in pairs(players) do ensureTopEntry(name) end
    for name, s in pairs(topStats) do
      local p = players[name]
      local e = {
        name = name,
        visits = tonumber(s.visits) or 0,
        purchases = tonumber(s.purchases) or 0,
        sells = tonumber(s.sells) or 0,
        spentCoin = tonumber(s.spentCoin) or 0,
        spentEma = tonumber(s.spentEma) or 0,
        earnedCoin = tonumber(s.earnedCoin) or 0,
        earnedEma = tonumber(s.earnedEma) or 0,
        coin = tonumber(p and p.balance) or 0,
        ema = tonumber(p and p.emaBalance) or 0,
      }
      if category == "spent" then
        e.value = e.spentCoin + e.spentEma
      elseif category == "sells" then
        e.value = e.earnedCoin + e.earnedEma
      else
        e.value = tonumber(s[category]) or 0
      end
      table.insert(sorted, e)
    end
  end
  table.sort(sorted, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.name < b.name
  end)
  topCache[category] = sorted
  return sorted
end

function getTopList(category, page, perPage)
  local sorted = buildTopList(category)
  local total = #sorted
  local totalPages = math.max(1, math.ceil(total / perPage))
  if page > totalPages then page = totalPages end
  local startIndex = (page - 1) * perPage + 1
  local endIndex = math.min(startIndex + perPage - 1, total)
  local pageData = {}
  for i = startIndex, endIndex do table.insert(pageData, sorted[i]) end
  return pageData, totalPages, total
end

function topValueString(category, e)
  if category == "balance" then
    return string.format("%.2f COIN | %.2f EMA", e.coin or 0, e.ema or 0)
  elseif category == "spent" then
    return string.format("%.2f COIN | %.2f EMA", e.spentCoin or 0, e.spentEma or 0)
  elseif category == "sells" then
    return string.format("%.2f COIN | %.2f EMA", e.earnedCoin or 0, e.earnedEma or 0)
  else
    return tostring(math.floor(tonumber(e.value) or 0)) .. " шт"
  end
end

-- ============================================================
-- ОТЗЫВЫ: ЗВЁЗДЫ
-- ============================================================
function starsDraw(x, y, rating, bg)
  rating = math.floor(tonumber(rating) or 0)
  if rating < 0 then rating = 0 end
  if rating > 5 then rating = 5 end
  for i = 1, 5 do
    writeText(x + (i - 1) * 2, y, "★", i <= rating and C.yellow or C.starOff, bg)
  end
end

function feedbackStats()
  local rated, sum = 0, 0
  for _, f in ipairs(feedbacks) do
    local r = math.floor(tonumber(f.rating) or 0)
    if r > 0 then rated = rated + 1; sum = sum + r end
  end
  local avg = rated > 0 and (sum / rated) or 0
  return avg, rated, sum
end

function setFeedbackRating(index, rating)
  local f = feedbacks[index]
  if not f then return false end
  rating = math.floor(tonumber(rating) or 0)
  if rating < 0 then rating = 0 end
  if rating > 5 then rating = 5 end
  f.rating = rating
  saveFeedbacks()
  addLog("FEEDBACK", "Изменена оценка отзыва " .. tostring(f.name or "?") .. " -> " .. rating)
  setToast("Оценка изменена: " .. rating .. "/5", C.green, 2)
  return true
end

-- ============================================================
-- РЕПОРТЫ: ЗАКРЕПЛЕНИЕ
-- ============================================================
reportOrder = {}

function buildReportOrder()
  local order = {}
  for i = 1, #reports do
    if reports[i].pinned then order[#order + 1] = i end
  end
  for i = 1, #reports do
    if not reports[i].pinned then order[#order + 1] = i end
  end
  return order
end

function countPinned()
  local n = 0
  for _, r in ipairs(reports) do
    if r.pinned then n = n + 1 end
  end
  return n
end

function toggleReportPin(actualIndex)
  local r = reports[actualIndex]
  if not r then return end
  r.pinned = not r.pinned
  saveReports()
  addLog("REPORT", (r.pinned and "Закреплён" or "Откреплён") .. " репорт игрока " .. tostring(r.name or "?"))
  setToast(r.pinned and "Репорт закреплён ★" or "Репорт откреплён", r.pinned and C.yellow or C.muted, 2)
end

-- ============================================================
-- СРОК БАНА: 30s 30m 30h 30d 1mo 1y, пусто = навсегда
-- ============================================================
function parseBanDuration(raw)
  raw = trimPlayerName(tostring(raw or ""))
  if raw == "" then
    return nil, "навсегда"
  end
  local num, unit = raw:match("^(%d+)(%a*)$")
  if not num then
    return nil, raw
  end
  local n = tonumber(num)
  unit = string.lower(unit or "")
  local secs, label
  if unit == "" or unit == "m" then
    secs = n * 60; label = n .. " мин"
  elseif unit == "s" then
    secs = n; label = n .. " сек"
  elseif unit == "h" then
    secs = n * 3600; label = n .. " ч"
  elseif unit == "d" then
    secs = n * 86400; label = n .. " дн"
  elseif unit == "mo" then
    secs = n * 2592000; label = n .. " мес"
  elseif unit == "y" then
    secs = n * 31536000; label = n .. " год"
  else
    secs = n * 60; label = n .. " мин"
  end
  local untilTs = nowEpoch() + secs
  return untilTs, label .. " (до " .. os.date("%d.%m.%Y %H:%M", untilTs) .. ")"
end

-- ============================================================
-- GUI: СОСТОЯНИЕ
-- ============================================================
screenW, screenH = 80, 25
hitboxes = {}
currentScreen = "dev"
toastText = ""
toastColor = C.muted
toastUntil = 0
lastClock = ""
serverSession = nil
passwordBuffer = ""
adminPasswordInput = ""
adminField = 1
selectedPlayerIndex = 1
playerScroll = 0
playersSearch = ""
selectedAdminIndex = 1
adminScroll = 0
adminListScroll = 0
selectedReportIndex = 1
reportScroll = 0
selectedFeedbackIndex = 1
feedbackScroll = 0
logScroll = 0
logSearch = ""
topCategory = "balance"
topScroll = 0
topSelectedIndex = 1
txScroll = 0
txSearch = ""
editingPlayerName = nil
balanceFields = {coin = "", ema = ""}
balanceField = 1
adminInput = ""
feedbackEditText = ""
banReasonInput = ""
banDurationInput = ""
banField = 1
addItemFields = {internal = "", display = "", price = "", ema = "", damage = "0"}
addItemFieldOrder = {"internal", "display", "price", "ema", "damage"}
addItemField = 1
addItemMessage = ""
addItemMessageColor = C.muted
addItemDest = "buy"
pendingAddItem = nil
deleteItemInput = ""
pendingDelete = nil

function setToast(text, color, seconds)
  toastText = tostring(text or "")
  toastColor = color or C.muted
  toastUntil = computer.uptime() + (seconds or 3)
end

function isOwner()
  return serverSession ~= nil and serverSession.player ~= nil and samePlayerName(serverSession.player, OWNER)
end

function updateScreenSize()
  local curW, curH = gpu.getResolution()
  local ok, maxW, maxH = pcall(gpu.maxResolution)
  if ok and maxW and maxH and (curW ~= maxW or curH ~= maxH) then
    pcall(gpu.setResolution, maxW, maxH)
  end
  screenW, screenH = gpu.getResolution()
end

function setFG(color) gpu.setForeground(color) end
function setBG(color) gpu.setBackground(color) end

function clearScreen(color)
  setBG(color or C.bg)
  setFG(C.white)
  gpu.fill(1, 1, screenW, screenH, " ")
end

function fillRect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  setBG(bg)
  gpu.fill(x, y, w, h, " ")
end

function writeText(x, y, text, fg, bg, maxWidth)
  if y < 1 or y > screenH or x > screenW then return end
  text = tostring(text or "")
  if maxWidth then text = clip(text, maxWidth) end
  if bg then setBG(bg) end
  if fg then setFG(fg) end
  gpu.set(x, y, text)
end

function drawBox(x, y, w, h, title, border, bg)
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
    writeText(x + 2, y, " " .. clip(title, w - 6) .. " ", C.white, bg)
  end
end

function centerText(y, text, fg, bg)
  text = tostring(text or "")
  local x = math.floor((screenW - ulen(text)) / 2) + 1
  if x < 1 then x = 1 end
  writeText(x, y, text, fg, bg)
end

function resetHitboxes() hitboxes = {} end

function addHitbox(id, x, y, w, h, data)
  table.insert(hitboxes, {id = id, x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1, data = data})
end

function drawButton(id, x, y, w, label, bg, fg, data)
  bg = bg or C.button
  fg = fg or C.white
  fillRect(x, y, w, 1, bg)
  local text = clip(label, w - 2)
  local left = x + math.max(1, math.floor((w - ulen(text)) / 2))
  writeText(left, y, text, fg, bg)
  addHitbox(id, x, y, w, 1, data)
end

function hitTest(x, y)
  for i = #hitboxes, 1, -1 do
    local b = hitboxes[i]
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b end
  end
  return nil
end

function drawHeaderClock()
  local right2 = getRealDateTimeString()
  local fieldW = math.max(19, ulen(right2))
  local x = math.max(2, screenW - fieldW - 1)
  fillRect(x, 2, math.max(1, screenW - x), 1, C.panel2)
  writeText(math.max(2, screenW - ulen(right2) - 1), 2, right2, C.muted, C.panel2)
end

function drawHeader(title)
  fillRect(1, 1, screenW, 3, C.panel2)
  writeText(2, 1, "PIM MARKET SERVER", C.accent, C.panel2)
  writeText(2, 2, title or "Панель сервера", C.white, C.panel2)
  local status = marketConnected and "MARKET ONLINE" or "MARKET OFFLINE"
  local statusColor = marketConnected and C.green or C.red
  local right1 = status .. (shopPaused and "  [ТЕХ. РАБОТЫ]" or "")
  writeText(math.max(2, screenW - ulen(right1) - 1), 1, right1, shopPaused and C.yellow or statusColor, C.panel2)
  drawHeaderClock()
  fillRect(1, 3, screenW, 1, C.border)
end

function drawFooter(hint)
  fillRect(1, screenH, screenW, 1, C.panel2)
  local message = hint or ""
  if toastText ~= "" and computer.uptime() <= toastUntil then
    message = toastText
    writeText(2, screenH, clip(message, screenW - 3), toastColor, C.panel2)
  else
    writeText(2, screenH, clip(message, screenW - 3), C.muted, C.panel2)
  end
end

function activeSessionCount()
  local n = 0
  for _, s in pairs(sessions) do
    if type(s) == "table" and s.token then n = n + 1 end
  end
  return n
end

function sumBalances()
  local coin, ema = 0, 0
  for _, p in pairs(players) do
    coin = coin + (tonumber(p.balance) or 0)
    ema = ema + (tonumber(p.emaBalance) or 0)
  end
  return coin, ema
end

function sortedPlayers()
  local list = {}
  for name, data in pairs(players) do table.insert(list, {name = name, data = data}) end
  table.sort(list, function(a, b) return normalizeName(a.name) < normalizeName(b.name) end)
  return list
end

function filteredPlayersList()
  local all = sortedPlayers()
  local q = unicode.lower(trimPlayerName(playersSearch))
  if q == "" then return all end
  local res = {}
  for _, e in ipairs(all) do
    if unicode.lower(e.name):find(q, 1, true) then res[#res + 1] = e end
  end
  return res
end

function filteredLogs()
  local q = unicode.lower(trimPlayerName(logSearch))
  if q == "" then return eventLog end
  local res = {}
  for _, e in ipairs(eventLog) do
    local hay = unicode.lower(tostring(e.text or "") .. " " .. tostring(e.kind or ""))
    if hay:find(q, 1, true) then res[#res + 1] = e end
  end
  return res
end

function filteredTransactions()
  local q = unicode.lower(trimPlayerName(txSearch))
  if q == "" then return transactionHistory end
  local res = {}
  for _, t in ipairs(transactionHistory) do
    local hay = unicode.lower(tostring(t.player or "") .. " " .. tostring(t.item or "") .. " " .. tostring(t.type or ""))
    if hay:find(q, 1, true) then res[#res + 1] = t end
  end
  return res
end

-- ============================================================
-- БОЛЬШОЙ ШРИФТ (3x5)
-- ============================================================
BIG_FONT = {
  ["А"] = {" █ ", "█ █", "███", "█ █", "█ █"},
  ["Б"] = {"███", "█  ", "███", "█ █", "███"},
  ["В"] = {"███", "█ █", "███", "█ █", "███"},
  ["Г"] = {"███", "█  ", "█  ", "█  ", "█  "},
  ["Д"] = {"███", "█ █", "█ █", "█ █", "███"},
  ["Е"] = {"███", "█  ", "███", "█  ", "███"},
  ["Ё"] = {"███", "█  ", "███", "█  ", "███"},
  ["Ж"] = {"█ █", "█ █", "███", "█ █", "█ █"},
  ["З"] = {"███", "  █", " ██", "  █", "███"},
  ["И"] = {"█ █", "█▐█", "█ █", "█▌█", "█ █"},
  ["Й"] = {"█ █", "█▐█", "█ █", "█▌█", "█ █"},
  ["К"] = {"█ █", "█ █", "██ ", "█ █", "█ █"},
  ["Л"] = {" █ ", "█ █", "█ █", "█ █", "█ █"},
  ["М"] = {"█ █", "███", "█ █", "█ █", "█ █"},
  ["Н"] = {"█ █", "█ █", "███", "█ █", "█ █"},
  ["О"] = {"███", "█ █", "█ █", "█ █", "███"},
  ["П"] = {"███", "█ █", "█ █", "█ █", "█ █"},
  ["Р"] = {"███", "█ █", "███", "█  ", "█  "},
  ["С"] = {"███", "█  ", "█  ", "█  ", "███"},
  ["Т"] = {"███", " █ ", " █ ", " █ ", " █ "},
  ["У"] = {"█ █", "█ █", "███", "  █", "███"},
  ["Ф"] = {" █ ", "███", "███", "███", " █ "},
  ["Х"] = {"█ █", "█ █", "███", "█ █", "█ █"},
  ["Ц"] = {"█ █", "█ █", "█ █", "█ █", "██▀"},
  ["Ч"] = {"█ █", "█ █", "███", "  █", "  █"},
  ["Ш"] = {"█ █", "█ █", "█ █", "█ █", "███"},
  ["Щ"] = {"█ █", "█ █", "█ █", "█ █", "██▀"},
  ["Ъ"] = {"██ ", " █ ", " █ ", " █ ", "██ "},
  ["Ы"] = {"█ █", "█ █", "███", "█ █", "█ █"},
  ["Ь"] = {"█  ", "█  ", "███", "█ █", "███"},
  ["Э"] = {"███", "  █", "███", "  █", "███"},
  ["Ю"] = {"█ █", "█ █", "███", "█ █", "█ █"},
  ["Я"] = {"███", "█ █", "███", "  █", "  █"},
  [" "] = {"   ", "   ", "   ", "   ", "   "},
}

function drawBigLine(y, text, color)
  local width = ulen(text) * 4 - 1
  local sx = math.floor((screenW - width) / 2) + 1
  if sx < 1 then sx = 1 end
  for ci = 1, ulen(text) do
    local ch = usub(text, ci, ci)
    local glyph = BIG_FONT[ch] or BIG_FONT[" "]
    for r = 1, 5 do
      writeText(sx + (ci - 1) * 4, y + r - 1, glyph[r], color, C.bg)
    end
  end
end

-- ============================================================
-- ЭКРАН РАЗРАБОТКИ / ВХОД (АВТОРИЗАЦИЯ НЕ ТРОНУТА)
-- ============================================================
function drawDevScreen()
  currentScreen = "dev"
  resetHitboxes()
  clearScreen(C.bg)
  drawBigLine(math.floor(screenH * 0.30), "ЭКРАН", C.accent)
  drawBigLine(math.floor(screenH * 0.30) + 7, "РАЗРАБОТКИ", C.accent2)
  centerText(screenH - 3, "Встаньте на PIM для входа в панель", C.muted)
  centerText(screenH - 2, "PIM MARKET SERVER v2.3", C.muted)
end

function drawLoginScreen()
  if not serverSession then drawDevScreen(); return end
  currentScreen = "login"
  resetHitboxes()
  clearScreen(C.bg)
  centerText(7, "Добро пожаловать: " .. tostring(serverSession.player), C.white)
  centerText(9, "Введите пароль администратора", C.muted)
  local fieldW = 34
  local fieldX = math.floor((screenW - fieldW) / 2) + 1
  local fieldY = 12
  fillRect(fieldX, fieldY, fieldW, 1, C.input)
  local masked = string.rep("*", ulen(passwordBuffer))
  if ulen(masked) > fieldW - 2 then masked = usub(masked, -(fieldW - 2)) end
  writeText(fieldX + 1, fieldY, masked .. "_", C.accent, C.input)
  centerText(15, "Enter - войти", C.muted)
  centerText(16, "Неверный пароль ничего не открывает", C.muted)
  centerText(screenH - 2, "Сойдите с PIM для возврата на экран разработки", C.muted)
end

-- ============================================================
-- PIM
-- ============================================================
function findLocalPim()
  for addr in component.list("pim") do return addr end
  return nil
end
LOCAL_PIM = findLocalPim()

function handlePimEnter(nick)
  nick = trimPlayerName(tostring(nick or ""))
  if nick == "" then return end
  if serverSession and serverSession.authed then return end
  serverSession = {player = nick, authed = false}
  passwordBuffer = ""
  currentScreen = "login"
  redraw()
end

function handlePimLeave(nick)
  if not serverSession then return end
  nick = trimPlayerName(tostring(nick or ""))
  if nick ~= "" and not samePlayerName(nick, serverSession.player) then return end
  serverSession = nil
  passwordBuffer = ""
  currentScreen = "dev"
  redraw()
end

-- ============================================================
-- GUI: DASHBOARD
-- ============================================================
function drawDashboard()
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
    local line = "[" .. shortTime .. "] [" .. tostring(e.kind or "INFO") .. "] " .. tostring(e.text or "")
    writeText(3, bodyY + i, clip(line, leftW - 5), logColor(e.kind), C.panel)
  end
  if #eventLog == 0 then
    writeText(3, bodyY + 2, "Пока нет важных событий.", C.muted, C.panel)
  end
  drawBox(rightX, bodyY, rightW, bodyH, "СОСТОЯНИЕ", C.accent2, C.panel)
  local coin, ema = sumBalances()
  local autoOn = isAutorunEnabled()
  local info = {
    {"MARKET", marketConnected and "ONLINE" or "OFFLINE", marketConnected and C.green or C.red},
    {"Магазин", shopPaused and "ТЕХ. РАБОТЫ" or "РАБОТАЕТ", shopPaused and C.yellow or C.green},
    {"Баланс COIN", string.format("%.2f", coin), C.yellow},
    {"Баланс EMA", string.format("%.2f", ema), C.accent},
    {"Репортов", tostring(#reports) .. " (★" .. countPinned() .. ")", C.red},
    {"Отзывов", tostring(#feedbacks), C.accent2},
    {"До полуночи", timeToMidnight(), C.muted},
    {"Автозапуск", autoOn and "ВКЛ" or "ВЫКЛ", autoOn and C.green or C.red},
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

function drawDashboardLiveValues()
  if currentScreen ~= "dashboard" then return end
  local cardY = 5
  local cardH = 5
  local bodyY = cardY + cardH + 1
  local leftW = math.floor(screenW * 0.64)
  local rightX = leftW + 2
  local rightW = screenW - rightX
  local y = bodyY + 7
  local valueX = rightX + math.floor(rightW * 0.48)
  local valueW = math.max(1, math.floor(rightW * 0.48))
  fillRect(valueX, y, valueW, 1, C.panel)
  writeText(valueX, y, clip(timeToMidnight(), valueW), C.muted, C.panel)
end

-- ============================================================
-- GUI: АДМИН-МЕНЮ
-- ============================================================
function drawAdminMenu()
  currentScreen = "admin_menu"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Администрирование")
  local autoOn = isAutorunEnabled()
  local items = {
    {"players", "ИГРОКИ", "Балансы, бан, поиск", C.accent},
    {"top", "ТОП ИГРОКОВ", "Рейтинги и сброс", C.accent},
    {"tx", "СДЕЛКИ", "Поиск и журнал", C.accent},
    {"stats", "СТАТИСТИКА", "Оборот и итоги", C.accent2},
    {"logs", "ЖУРНАЛ", "Поиск по событиям", C.accent2},
    {"reports", "РЕПОРТЫ", "Закрепить ★, удалить", C.orange},
    {"feedbacks", "ОТЗЫВЫ", "Звёзды, правка", C.orange},
    {"add_item", "ДОБАВИТЬ ПРЕДМЕТ", "Продажа или пополнение", C.green},
    {"del_item", "УДАЛИТЬ ПРЕДМЕТ", "Из продажи/пополнения", C.red},
    {"pause", shopPaused and "СНЯТЬ ТЕХ. РАБОТЫ" or "ТЕХ. РАБОТЫ", "Доступ терминалов", shopPaused and C.green or C.red},
    {"admin_list", "СПИСОК АДМИНОВ", "Кто имеет доступ", C.purple},
  }
  if isOwner() then
    table.insert(items, {"admins", "АДМИНЫ", "Управление доступом", C.yellow})
    table.insert(items, {"autorun", autoOn and "АВТООТКРЫТИЕ: ВКЛ" or "АВТООТКРЫТИЕ: ВЫКЛ", "Автозапуск (.shrc)", autoOn and C.green or C.red})
    table.insert(items, {"update_server", "ОБНОВЛЕНИЕ СЕРВЕРА", "Запустить update.lua", C.yellow})
    table.insert(items, {"exit_shell", "ВЫХОД В SHELL", "Завершить сервер", C.red})
  end
  local cols = 3
  local rowsNeeded = math.ceil(#items / cols)
  if #items > 12 or (5 + rowsNeeded * 4 > screenH - 4) then
    cols = 4
  end
  local gapX = 1
  local gapY = 1
  local boxW = math.floor((screenW - 4 - gapX * (cols - 1)) / cols)
  local boxH = 3
  local startY = 5
  for i = 1, #items do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = 2 + col * (boxW + gapX)
    local y = startY + row * (boxH + gapY)
    drawBox(x, y, boxW, boxH, items[i][2], items[i][4], C.panel)
    writeText(x + 2, y + 1, clip(items[i][3], boxW - 4), C.muted, C.panel)
    addHitbox(items[i][1], x, y, boxW, boxH)
  end
  drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
  drawFooter("Esc - назад | выберите раздел мышкой")
end

-- ============================================================
-- GUI: ИГРОКИ (+ КАРТОЧКА БАНА: кто/когда/разбан/причина)
-- ============================================================
function drawPlayersPage()
  currentScreen = "players"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Игроки")
  local list = filteredPlayersList()
  if selectedPlayerIndex < 1 then selectedPlayerIndex = 1 end
  if selectedPlayerIndex > #list then selectedPlayerIndex = math.max(1, #list) end
  writeText(2, 4, "ПОИСК НИКА:", C.accent, C.bg)
  fillRect(14, 4, 26, 1, C.input)
  writeText(15, 4, clip(playersSearch .. "_", 24), C.white, C.input)
  addHitbox("players_search", 14, 4, 26, 1)
  fillRect(41, 4, 3, 1, C.red)
  writeText(42, 4, "X", C.white, C.red)
  addHitbox("players_clear", 41, 4, 3, 1)
  writeText(46, 4, "НАЙДЕНО: " .. #list, C.green, C.bg)
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
  if #list > visible then
    local barH = visible
    local thumb = math.max(1, math.floor(barH * visible / math.max(1, #list)))
    local pos = math.floor((playerScroll) * (barH - thumb) / math.max(1, #list - visible)) + 1
    fillRect(leftW - 1, listY + 2, 1, barH, C.panel3)
    fillRect(leftW - 1, listY + 1 + pos, 1, thumb, C.accent)
  end
  local rightX = leftW + 1
  local rightW = screenW - rightX
  drawBox(rightX, listY, rightW, listH, "УПРАВЛЕНИЕ", C.accent, C.panel)
  local selected = list[selectedPlayerIndex]
  if selected then
    local p = selected.data
    local by = listY + listH - 6
    local y = listY + 2
    local function line(text, color)
      if y > by - 1 then return end
      writeText(rightX + 2, y, clip(text, rightW - 4), color, C.panel)
      y = y + 1
    end
    line("Игрок: " .. selected.name, C.white)
    y = y + 1
    line("COIN: " .. string.format("%.2f", tonumber(p.balance) or 0), C.yellow)
    line("EMA:  " .. string.format("%.2f", tonumber(p.emaBalance) or 0), C.accent)
    line("Транзакций: " .. tostring(p.transactions or 0), C.text)
    line("Регистрация: " .. tostring(p.regDate or "?"), C.muted)
    if p.banned then
      line("Статус: ЗАБЛОКИРОВАН", C.red)
      local bi = p.banInfo or {}
      line("Кто забанил: " .. tostring(bi.admin or "?"), C.orange)
      line("Когда: " .. tostring(bi.date or "?"), C.muted)
      local unban = "никогда (навсегда)"
      if p.banUntil then
        unban = os.date("%d.%m.%Y %H:%M", tonumber(p.banUntil) or 0)
      end
      line("Разбан: " .. unban, C.yellow)
      line("Причина: " .. tostring(bi.reason or "?"), C.text)
    else
      line("Статус: АКТИВЕН", C.green)
    end
    local bw = math.max(14, rightW - 4)
    drawButton("edit_balance", rightX + 2, by, bw, "РЕДАКТИРОВАТЬ БАЛАНС", C.buttonHot, C.white)
    drawButton("toggle_ban", rightX + 2, by + 2, bw, p.banned and "РАЗБЛОКИРОВАТЬ" or "ЗАБЛОКИРОВАТЬ", p.banned and C.green or C.red, C.white)
    drawButton("reset_transactions", rightX + 2, by + 4, bw, "СБРОСИТЬ СЧЁТЧИК ТРАНЗАКЦИЙ", C.button, C.white)
  else
    writeText(rightX + 2, listY + 2, "Игроков пока нет.", C.muted, C.panel)
  end
  drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
  drawFooter("печать - поиск | [X] - стереть | ↑/↓ колёсико | Enter - баланс | B - бан | Esc - назад")
end

-- ============================================================
-- GUI: РЕДАКТОР БАЛАНСА
-- ============================================================
function drawBalanceEditor()
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
    local cursor = balanceField == i and "█" or ""
    writeText(x + 4, fy + 1, clip(balanceFields[fields[i].key] .. cursor, inputW - 2), C.white, bg)
    addHitbox("balance_field", x + 3, fy, inputW, 2, i)
  end
  local bw = math.floor((w - 8) / 2)
  drawButton("balance_save", x + 3, y + h - 2, bw, "СОХРАНИТЬ", C.green, C.bg)
  drawButton("back", x + 5 + bw, y + h - 2, bw, "НАЗАД", C.button, C.white)
  drawFooter("Tab - следующее поле | Enter - сохранить | Esc - назад")
end

-- ============================================================
-- GUI: БАН-РЕДАКТОР
-- ============================================================
function drawBanEditor()
  currentScreen = "edit_ban"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Блокировка игрока")
  local w = math.min(76, screenW - 6)
  local h = 16
  local x = math.floor((screenW - w) / 2) + 1
  local y = math.max(5, math.floor((screenH - h) / 2))
  drawBox(x, y, w, h, "БАН: " .. tostring(editingPlayerName or "?"), C.red, C.panel)
  writeText(x + 3, y + 2, "Причина наказания:", C.red, C.panel)
  local bg1 = banField == 1 and C.select or C.input
  fillRect(x + 3, y + 3, w - 6, 1, bg1)
  writeText(x + 4, y + 3, clip(banReasonInput .. (banField == 1 and "█" or ""), w - 8), C.white, bg1)
  addHitbox("ban_field", x + 3, y + 2, w - 6, 2, 1)
  writeText(x + 3, y + 5, "Срок: 30s 30m 30h 30d 1mo 1y | ПУСТО = навсегда:", C.yellow, C.panel)
  local bg2 = banField == 2 and C.select or C.input
  fillRect(x + 3, y + 6, w - 6, 1, bg2)
  writeText(x + 4, y + 6, clip(banDurationInput .. (banField == 2 and "█" or ""), w - 8), C.white, bg2)
  addHitbox("ban_field", x + 3, y + 5, w - 6, 2, 2)
  writeText(x + 3, y + 8, "s=сек m=мин h=час d=день mo=месяц y=год", C.muted, C.panel)
  writeText(x + 3, y + 9, "Администратор: " .. tostring(serverSession and serverSession.player or "?"), C.muted, C.panel)
  local bw = math.floor((w - 8) / 2)
  drawButton("ban_save", x + 3, y + h - 2, bw, "ЗАБЛОКИРОВАТЬ", C.red, C.white)
  drawButton("ban_cancel", x + 5 + bw, y + h - 2, bw, "ОТМЕНА", C.button, C.white)
  drawFooter("Tab - поля | Enter - забанить | Esc - отмена")
end

-- ============================================================
-- GUI: ТОП ИГРОКОВ
-- ============================================================
function topVisibleRows() return math.max(4, (screenH - 8) - 5) end

function drawTopPage()
  currentScreen = "top"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Топ игроков")
  local x, y, w, h = 2, 5, screenW - 4, screenH - 8
  drawBox(x, y, w, h, "ТОП ИГРОКОВ СЕРВЕРА", C.yellow, C.panel)
  local bx = x + 2
  for i, cat in ipairs(TOP_CATS) do
    local bw = 15
    local active = topCategory == cat.key
    drawButton("top_cat", bx, y + 1, bw, (i .. " " .. cat.label), active and C.select or C.button, active and C.white or C.muted, cat.key)
    bx = bx + bw + 1
    if bx + 15 > x + w - 2 then break end
  end
  writeText(x + 2, y + 3, padRight("#", 5) .. padRight("ИГРОК", 20) .. "ЗНАЧЕНИЕ", C.muted, C.panel)
  local list = buildTopList(topCategory)
  local visible = topVisibleRows()
  local maxScroll = math.max(0, #list - visible)
  topScroll = clamp(topScroll, 0, maxScroll)
  if topSelectedIndex < 1 then topSelectedIndex = 1 end
  if topSelectedIndex > #list then topSelectedIndex = math.max(1, #list) end
  for row = 1, visible do
    local idx = topScroll + row
    local e = list[idx]
    if not e then break end
    local yy = y + 3 + row
    local bg = (idx == topSelectedIndex) and C.select or C.panel
    fillRect(x + 2, yy, w - 4, 1, bg)
    local rankColor = C.muted
    if idx == 1 then rankColor = C.yellow
    elseif idx == 2 then rankColor = C.white
    elseif idx == 3 then rankColor = C.orange end
    writeText(x + 2, yy, padRight(idx .. ".", 5), rankColor, bg)
    writeText(x + 7, yy, padRight(clip(e.name, 18), 20), idx == topSelectedIndex and C.white or C.text, bg)
    writeText(x + 27, yy, clip(topValueString(topCategory, e), w - 29), C.accent2, bg)
    addHitbox("top_select", x + 2, yy, w - 4, 1, idx)
  end
  if #list == 0 then
    writeText(x + 2, y + 5, "Пока нет данных.", C.muted, C.panel)
  end
  if #list > visible then
    local barH = visible
    local thumb = math.max(1, math.floor(barH * visible / math.max(1, #list)))
    local pos = math.floor(topScroll * (barH - thumb) / math.max(1, #list - visible)) + 1
    fillRect(x + w - 2, y + 4, 1, barH, C.panel3)
    fillRect(x + w - 2, y + 3 + pos, 1, thumb, C.accent)
  end
  drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
  drawButton("top_reset", 20, screenH - 2, 26, "СБРОСИТЬ ТОП ИГРОКА", C.red, C.white)
  writeText(48, screenH - 2, "Всего в топе: " .. #list, C.muted, C.bg)
  drawFooter("1-5 категория | ↑/↓ колёсико | клик - выбор | сброс обнуляет топ выбранного")
end

-- ============================================================
-- GUI: СДЕЛКИ
-- ============================================================
function txVisibleRows() return math.max(4, (screenH - 8) - 4) end

function drawTransactionsPage()
  currentScreen = "tx"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Сделки")
  local x, y, w, h = 2, 5, screenW - 4, screenH - 8
  drawBox(x, y, w, h, "ЖУРНАЛ СДЕЛОК: " .. #transactionHistory, C.accent, C.panel)
  writeText(x + 2, y + 1, "ПОИСК:", C.accent, C.panel)
  fillRect(x + 9, y + 1, 30, 1, C.input)
  writeText(x + 10, y + 1, clip(txSearch .. "_", 28), C.white, C.input)
  addHitbox("tx_search", x + 9, y + 1, 30, 1)
  fillRect(x + 40, y + 1, 3, 1, C.red)
  writeText(x + 41, y + 1, "X", C.white, C.red)
  addHitbox("tx_clear", x + 40, y + 1, 3, 1)
  local list = filteredTransactions()
  writeText(x + 45, y + 1, "НАЙДЕНО: " .. #list, C.green, C.panel)
  writeText(x + 2, y + 2, padRight("ВРЕМЯ", 10) .. padRight("ТИП", 6) .. padRight("ИГРОК", 18) .. padRight("ПРЕДМЕТ", 24) .. "СУММА", C.muted, C.panel)
  local visible = txVisibleRows()
  local maxScroll = math.max(0, #list - visible)
  txScroll = clamp(txScroll, 0, maxScroll)
  for row = 1, visible do
    local idx = txScroll + row
    local t = list[idx]
    if not t then break end
    local yy = y + 2 + row
    local bg = C.panel
    fillRect(x + 2, yy, w - 4, 1, bg)
    local tm = tostring(t.time or ""):match("(%d%d:%d%d:%d%d)$") or tostring(t.time or "")
    local isBuy = (t.type == "buy")
    writeText(x + 2, yy, padRight(tm, 10), C.muted, bg)
    writeText(x + 12, yy, padRight(isBuy and "BUY" or "SELL", 6), isBuy and C.green or C.accent, bg)
    writeText(x + 18, yy, padRight(clip(t.player or "?", 16), 18), C.text, bg)
    writeText(x + 36, yy, padRight(clip(tostring(t.item or "?") .. " x" .. tostring(t.qty or 0), 22), 24), C.text, bg)
    local sum = ""
    local coin = tonumber(t.coin) or 0
    local ema = tonumber(t.ema) or 0
    if coin > 0 then sum = sum .. (isBuy and "-" or "+") .. string.format("%.2f C ", coin) end
    if ema > 0 then sum = sum .. (isBuy and "-" or "+") .. string.format("%.2f E", ema) end
    writeText(x + 60, yy, clip(sum, w - 62), C.yellow, bg)
  end
  if #list == 0 then
    writeText(x + 2, y + 4, "Сделок не найдено.", C.muted, C.panel)
  end
  if #list > visible then
    local barH = visible
    local thumb = math.max(1, math.floor(barH * visible / math.max(1, #list)))
    local pos = math.floor(txScroll * (barH - thumb) / math.max(1, #list - visible)) + 1
    fillRect(x + w - 2, y + 3, 1, barH, C.panel3)
    fillRect(x + w - 2, y + 2 + pos, 1, thumb, C.accent)
  end
  drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
  drawFooter("печать - поиск | [X] - стереть | ↑/↓ колёсико - прокрутка | Esc - назад")
end

-- ============================================================
-- GUI: СПИСОК АДМИНОВ
-- ============================================================
function adminListVisibleRows() return math.max(4, (screenH - 8) - 3) end

function drawAdminListPage()
  currentScreen = "admin_list"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Список администраторов")
  local list = sortedAdminsOwnerFirst()
  local w = math.min(80, screenW - 6)
  local x = math.floor((screenW - w) / 2) + 1
  local y = 5
  local h = screenH - 8
  drawBox(x, y, w, h, "ДОСТУП К ПАНЕЛИ: " .. #list, C.purple, C.panel)
  writeText(x + 3, y + 1, padRight("#", 5) .. padRight("ПРЕФИКС", 12) .. padRight("НИК", 22) .. "РОЛЬ", C.muted, C.panel)
  local visible = adminListVisibleRows()
  local maxScroll = math.max(0, #list - visible)
  adminListScroll = clamp(adminListScroll, 0, maxScroll)
  for row = 1, visible do
    local idx = adminListScroll + row
    local name = list[idx]
    if not name then break end
    local yy = y + 1 + row
    fillRect(x + 2, yy, w - 4, 1, C.panel)
    local isOwn = samePlayerName(name, OWNER)
    local prefix, pcolor = adminPrefix(name)
    writeText(x + 3, yy, padRight(tostring(idx), 5), C.muted, C.panel)
    writeText(x + 8, yy, padRight(prefix, 12), pcolor, C.panel)
    writeText(x + 20, yy, padRight(clip(name, 20), 22), isOwn and C.white or C.text, C.panel)
    writeText(x + 42, yy, isOwn and "создатель сервера" or "администратор", C.muted, C.panel)
  end
  if #list > visible then
    local barH = visible
    local thumb = math.max(1, math.floor(barH * visible / math.max(1, #list)))
    local pos = math.floor(adminListScroll * (barH - thumb) / math.max(1, #list - visible)) + 1
    fillRect(x + w - 2, y + 2, 1, barH, C.panel3)
    fillRect(x + w - 2, y + 1 + pos, 1, thumb, C.accent)
  end
  drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
  drawFooter("↑/↓ или колёсико - прокрутка | Esc - назад")
end

-- ============================================================
-- GUI: АДМИНЫ (УПРАВЛЕНИЕ)
-- ============================================================
function drawAdminsPage()
  currentScreen = "admins"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Администраторы")
  local list = sortedAdmins()
  local w = math.min(90, screenW - 6)
  local x = math.floor((screenW - w) / 2) + 1
  local y = 5
  local h = screenH - 8
  drawBox(x, y, w, h, "УПРАВЛЕНИЕ ДОСТУПОМ", C.orange, C.panel)
  local visible = h - 7
  if selectedAdminIndex < 1 then selectedAdminIndex = 1 end
  if selectedAdminIndex > #list then selectedAdminIndex = math.max(1, #list) end
  if selectedAdminIndex <= adminScroll then adminScroll = selectedAdminIndex - 1 end
  if selectedAdminIndex > adminScroll + visible then adminScroll = selectedAdminIndex - visible end
  if adminScroll < 0 then adminScroll = 0 end
  for row = 1, visible do
    local idx = adminScroll + row
    local name = list[idx]
    if not name then break end
    local yy = y + row
    local bg = idx == selectedAdminIndex and C.select or C.panel
    fillRect(x + 2, yy, w - 4, 1, bg)
    local idxText = tostring(idx) .. ". "
    local prefix, pcolor = adminPrefix(name)
    writeText(x + 3, yy, idxText, idx == selectedAdminIndex and C.white or C.muted, bg)
    writeText(x + 3 + ulen(idxText), yy, prefix, pcolor, bg)
    writeText(x + 3 + ulen(idxText) + ulen(prefix), yy, name, idx == selectedAdminIndex and C.white or C.text, bg)
    addHitbox("admin_select", x + 2, yy, w - 4, 1, idx)
  end
  local bw = math.floor((w - 8) / 3)
  local by = y + h - 3
  if isOwner() then
    drawButton("admin_add", x + 2, by, bw, "+ ДОБАВИТЬ", C.green, C.bg)
    drawButton("admin_delete", x + 4 + bw, by, bw, "- УДАЛИТЬ", C.red, C.white)
    drawButton("back", x + 6 + bw * 2, by, bw, "НАЗАД", C.button, C.white)
    drawFooter("↑/↓ - выбор | Insert - добавить | Delete - удалить | Esc - назад")
  else
    drawButton("back", x + 2, by, bw, "НАЗАД", C.button, C.white)
    writeText(x + 4 + bw, by, "Управление админами - только владелец", C.muted, C.panel)
    drawFooter("Добавлять и удалять администраторов может только " .. OWNER)
  end
end

function drawAdminAddPage()
  currentScreen = "admin_add"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Добавить администратора")
  local w = math.min(70, screenW - 6)
  local h = 13
  local x = math.floor((screenW - w) / 2) + 1
  local y = math.max(6, math.floor((screenH - h) / 2))
  drawBox(x, y, w, h, "НОВЫЙ АДМИНИСТРАТОР", C.green, C.panel)
  writeText(x + 3, y + 2, "Ник игрока:", C.text, C.panel)
  local bg1 = adminField == 1 and C.select or C.input
  fillRect(x + 3, y + 3, w - 6, 1, bg1)
  writeText(x + 4, y + 3, clip(adminInput .. (adminField == 1 and "█" or ""), w - 8), C.white, bg1)
  addHitbox("admin_input", x + 3, y + 2, w - 6, 2, 1)
  writeText(x + 3, y + 5, "Пароль для входа:", C.text, C.panel)
  local bg2 = adminField == 2 and C.select or C.input
  fillRect(x + 3, y + 6, w - 6, 1, bg2)
  local masked = string.rep("*", ulen(adminPasswordInput))
  writeText(x + 4, y + 6, clip(masked .. (adminField == 2 and "█" or ""), w - 8), C.white, bg2)
  addHitbox("admin_input", x + 3, y + 5, w - 6, 2, 2)
  local bw = math.floor((w - 8) / 2)
  drawButton("admin_add_confirm", x + 3, y + h - 2, bw, "ДОБАВИТЬ", C.green, C.bg)
  drawButton("back", x + 5 + bw, y + h - 2, bw, "НАЗАД", C.button, C.white)
  drawFooter("Tab - следующее поле | Enter - добавить | Esc - назад")
end

-- ============================================================
-- GUI: РЕПОРТЫ
-- ============================================================
function drawReportsPage()
  currentScreen = "reports"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Репорты")
  local w = screenW - 4
  local h = screenH - 8
  local x, y = 2, 5
  drawBox(x, y, w, h, "РЕПОРТЫ: " .. tostring(#reports) .. " | ЗАКРЕПЛЕНО: " .. tostring(countPinned()), C.red, C.panel)
  reportOrder = buildReportOrder()
  local visible = h - 5
  if selectedReportIndex < 1 then selectedReportIndex = 1 end
  if selectedReportIndex > #reportOrder then selectedReportIndex = math.max(1, #reportOrder) end
  if selectedReportIndex <= reportScroll then reportScroll = selectedReportIndex - 1 end
  if selectedReportIndex > reportScroll + visible then reportScroll = selectedReportIndex - visible end
  if reportScroll < 0 then reportScroll = 0 end
  writeText(x + 2, y + 1, padRight("★", 3) .. padRight("#", 5) .. padRight("ВРЕМЯ", 21) .. padRight("ИГРОК", 18) .. "ТЕКСТ", C.muted, C.panel)
  for row = 1, visible do
    local pos = reportScroll + row
    local actual = reportOrder[pos]
    local r = actual and reports[actual]
    if not r then break end
    local yy = y + 1 + row
    local bg = pos == selectedReportIndex and C.select or C.panel
    fillRect(x + 2, yy, w - 4, 1, bg)
    writeText(x + 2, yy, "★", r.pinned and C.yellow or C.starOff, bg)
    addHitbox("report_pin", x + 2, yy, 2, 1, actual)
    writeText(x + 4, yy, padRight(tostring(pos), 5), pos == selectedReportIndex and C.white or C.muted, bg)
    writeText(x + 9, yy, padRight(tostring(r.time or "?"), 20), C.muted, bg)
    writeText(x + 29, yy, padRight(clip(r.name or "?", 16), 18), C.text, bg)
    writeText(x + 47, yy, clip(r.text or "", w - 49), C.text, bg)
    addHitbox("report_select", x + 4, yy, w - 6, 1, pos)
  end
  if #reportOrder == 0 then
    writeText(x + 2, y + 3, "Репортов пока нет.", C.muted, C.panel)
  end
  local bw = math.max(12, math.floor((w - 10) / 4))
  local by = y + h - 2
  drawButton("report_open", x + 2, by, bw, "ОТКРЫТЬ", C.buttonHot, C.white)
  drawButton("report_pin_sel", x + 4 + bw, by, bw, "★ ЗАКРЕПИТЬ", C.yellow, C.bg)
  drawButton("report_delete", x + 6 + bw * 2, by, bw, "УДАЛИТЬ", C.red, C.white)
  drawButton("back", x + 8 + bw * 3, by, math.max(10, w - (8 + bw * 3) - 1), "НАЗАД", C.button, C.white)
  drawFooter("↑/↓ колёсико | клик по ★ или P - закрепить | Enter открыть | Del удалить | Esc назад")
end

function drawReportView()
  currentScreen = "report_view"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Просмотр репорта")
  local actual = reportOrder[selectedReportIndex]
  local r = actual and reports[actual]
  if not r then
    currentScreen = "reports"
    drawReportsPage()
    return
  end
  local x, y, w, h = 3, 5, screenW - 6, screenH - 8
  drawBox(x, y, w, h, (r.pinned and "★ ЗАКРЕПЛЁННЫЙ РЕПОРТ ОТ " or "РЕПОРТ ОТ ") .. tostring(r.name or "?"), C.red, C.panel)
  writeText(x + 2, y + 2, "Время: " .. tostring(r.time or "?"), C.muted, C.panel)
  writeText(x + 2, y + 3, "Игрок: " .. tostring(r.name or "?"), C.white, C.panel)
  writeText(x + 2, y + 5, "Сообщение:", C.red, C.panel)
  local lines = wrapText(r.text or "", w - 4)
  for i = 1, math.min(#lines, h - 8) do
    writeText(x + 2, y + 5 + i, lines[i], C.text, C.panel)
  end
  local bw = math.floor((w - 9) / 3)
  drawButton("report_pin_sel", x + 2, y + h - 2, bw, r.pinned and "★ ОТКРЕПИТЬ" or "☆ ЗАКРЕПИТЬ", C.yellow, C.bg)
  drawButton("report_delete", x + 4 + bw, y + h - 2, bw, "УДАЛИТЬ РЕПОРТ", C.red, C.white)
  drawButton("back", x + 6 + bw * 2, y + h - 2, bw, "НАЗАД К СПИСКУ", C.button, C.white)
  drawFooter("P или кнопка - закрепить | Delete - удалить | Esc - назад")
end

-- ============================================================
-- GUI: ОТЗЫВЫ
-- ============================================================
function drawFeedbacksPage()
  currentScreen = "feedbacks"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Отзывы")
  local w = screenW - 4
  local h = screenH - 8
  local x, y = 2, 5
  drawBox(x, y, w, h, "ОТЗЫВЫ: " .. tostring(#feedbacks), C.accent2, C.panel)
  local avg, rated, sum = feedbackStats()
  writeText(x + 2, y + 1, "СРЕДНЯЯ ОЦЕНКА:", C.muted, C.panel)
  starsDraw(x + 18, y + 1, math.floor(avg + 0.5), C.panel)
  writeText(x + 29, y + 1, string.format("%.2f / 5 | оценок: %d | отзывов: %d", avg, rated, #feedbacks), C.accent2, C.panel)
  writeText(x + 2, y + 2, padRight("#", 4) .. padRight("ЗВЁЗДЫ", 11) .. padRight("ИГРОК", 16) .. "ТЕКСТ", C.muted, C.panel)
  local visible = h - 6
  if selectedFeedbackIndex < 1 then selectedFeedbackIndex = 1 end
  if selectedFeedbackIndex > #feedbacks then selectedFeedbackIndex = math.max(1, #feedbacks) end
  if selectedFeedbackIndex <= feedbackScroll then feedbackScroll = selectedFeedbackIndex - 1 end
  if selectedFeedbackIndex > feedbackScroll + visible then feedbackScroll = selectedFeedbackIndex - visible end
  if feedbackScroll < 0 then feedbackScroll = 0 end
  for row = 1, visible do
    local idx = feedbackScroll + row
    local f = feedbacks[idx]
    if not f then break end
    local yy = y + 2 + row
    local bg = idx == selectedFeedbackIndex and C.select or C.panel
    fillRect(x + 2, yy, w - 4, 1, bg)
    writeText(x + 2, yy, padRight(tostring(idx), 4), idx == selectedFeedbackIndex and C.white or C.muted, bg)
    starsDraw(x + 6, yy, f.rating, bg)
    writeText(x + 16, yy, padRight(clip(f.name or "?", 14), 16), idx == selectedFeedbackIndex and C.white or C.text, bg)
    writeText(x + 32, yy, clip(f.text or "", w - 34), idx == selectedFeedbackIndex and C.white or C.text, bg)
    addHitbox("feedback_select", x + 2, yy, w - 4, 1, idx)
  end
  if #feedbacks == 0 then
    writeText(x + 2, y + 4, "Отзывов пока нет.", C.muted, C.panel)
  end
  local bw = math.max(12, math.floor((w - 10) / 4))
  local by = y + h - 2
  drawButton("feedback_open", x + 2, by, bw, "ОТКРЫТЬ", C.buttonHot, C.white)
  drawButton("feedback_edit_text", x + 4 + bw, by, bw, "ТЕКСТ", C.button, C.white)
  drawButton("feedback_delete", x + 6 + bw * 2, by, bw, "УДАЛИТЬ", C.red, C.white)
  drawButton("back", x + 8 + bw * 3, by, math.max(10, w - (8 + bw * 3) - 1), "НАЗАД", C.button, C.white)
  drawFooter("↑/↓ колёсико - выбор | Enter открыть | 1-5 оценка | Del удалить | Esc назад")
end

function drawFeedbackView()
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
  writeText(x + 2, y + 5, "Оценка:", C.muted, C.panel)
  local rating = math.floor(tonumber(f.rating) or 0)
  for i = 1, 5 do
    local sx = x + 10 + (i - 1) * 2
    writeText(sx, y + 5, "★", i <= rating and C.yellow or C.starOff, C.panel)
    addHitbox("feedback_star", sx, y + 5, 2, 1, i)
  end
  writeText(x + 21, y + 5, "(" .. rating .. "/5)  клик по звезде или клавиши 1-5", C.muted, C.panel)
  writeText(x + 2, y + 7, "Текст отзыва:", C.accent2, C.panel)
  local lines = wrapText(f.text or "", w - 4)
  for i = 1, math.min(#lines, h - 11) do
    writeText(x + 2, y + 7 + i, lines[i], C.text, C.panel)
  end
  local bw = math.floor((w - 8) / 3)
  local by = y + h - 2
  drawButton("feedback_edit_text", x + 2, by, bw, "ИЗМЕНИТЬ ТЕКСТ", C.button, C.white)
  drawButton("feedback_delete", x + 4 + bw, by, bw, "УДАЛИТЬ ОТЗЫВ", C.red, C.white)
  drawButton("back", x + 6 + bw * 2, by, bw, "НАЗАД К СПИСКУ", C.button, C.white)
  drawFooter("1-5 / клик по звезде - оценка | Del удалить | Esc назад")
end

function drawFeedbackEditText()
  currentScreen = "feedback_edit_text"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Редактирование текста отзыва")
  local f = feedbacks[selectedFeedbackIndex]
  if not f then
    currentScreen = "feedbacks"
    drawFeedbacksPage()
    return
  end
  local w = math.min(90, screenW - 6)
  local h = math.min(16, screenH - 8)
  local x = math.floor((screenW - w) / 2) + 1
  local y = math.max(5, math.floor((screenH - h) / 2))
  drawBox(x, y, w, h, "ТЕКСТ ОТЗЫВА " .. tostring(f.name or "?"), C.accent2, C.panel)
  local lines = wrapText(feedbackEditText .. "█", w - 6)
  for i = 1, math.min(#lines, h - 6) do
    writeText(x + 3, y + 2 + i, lines[i], C.white, C.panel)
  end
  local bw = math.floor((w - 8) / 2)
  local by = y + h - 2
  drawButton("feedback_edit_save", x + 3, by, bw, "СОХРАНИТЬ", C.green, C.bg)
  drawButton("back", x + 5 + bw, by, bw, "ОТМЕНА", C.button, C.white)
  drawFooter("Ввод - текст | Backspace стереть | Enter сохранить | Esc отмена")
end

-- ============================================================
-- GUI: СТАТИСТИКА
-- ============================================================
function topItems(txType, limit)
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

function drawStatsPage()
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
  drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
  writeText(20, screenH - 2, string.format("Суммарные балансы: %.2f COIN | %.2f EMA", coinBalance, emaBalance), C.muted, C.bg)
  drawFooter("Статистика денежных сумм накапливается с этой версии сервера")
end

-- ============================================================
-- GUI: ЖУРНАЛ
-- ============================================================
function logsVisibleRows() return math.max(4, (screenH - 7) - 4) end

function drawLogsPage()
  currentScreen = "logs"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Журнал важных событий")
  local x, y, w, h = 2, 4, screenW - 4, screenH - 7
  drawBox(x, y, w, h, "ПОКУПКИ / ПРОДАЖИ / БАЛАНСЫ / ПОЛЬЗОВАТЕЛИ / АДМИН", C.yellow, C.panel)
  writeText(x + 2, y + 1, "ПОИСК:", C.accent, C.panel)
  fillRect(x + 9, y + 1, 30, 1, C.input)
  writeText(x + 10, y + 1, clip(logSearch .. "_", 28), C.white, C.input)
  addHitbox("logs_search", x + 9, y + 1, 30, 1)
  fillRect(x + 40, y + 1, 3, 1, C.red)
  writeText(x + 41, y + 1, "X", C.white, C.red)
  addHitbox("logs_clear", x + 40, y + 1, 3, 1)
  local list = filteredLogs()
  writeText(x + 45, y + 1, "НАЙДЕНО: " .. #list, C.green, C.panel)
  local visible = logsVisibleRows()
  local maxScroll = math.max(0, #list - visible)
  logScroll = clamp(logScroll, 0, maxScroll)
  for row = 1, visible do
    local idx = logScroll + row
    local e = list[idx]
    if not e then break end
    local line = string.format("[%s] [%-8s] %s", tostring(e.time or "?"), tostring(e.kind or "INFO"), tostring(e.text or ""))
    writeText(x + 2, y + 1 + row, clip(line, w - 5), logColor(e.kind), C.panel)
  end
  if #list == 0 then
    writeText(x + 2, y + 3, "Ничего не найдено.", C.muted, C.panel)
  end
  if #list > visible then
    local barH = visible
    local thumb = math.max(1, math.floor(barH * visible / math.max(1, #list)))
    local pos = math.floor(logScroll * (barH - thumb) / math.max(1, #list - visible)) + 1
    fillRect(x + w - 2, y + 2, 1, barH, C.panel3)
    fillRect(x + w - 2, y + 1 + pos, 1, thumb, C.accent)
  end
  drawButton("back", 2, screenH - 2, 16, "< НАЗАД", C.button, C.white)
  drawFooter("печать - поиск | [X] - стереть | ↑/↓ колёсико | Esc - назад | файл: /home/market_server.log")
end

-- ============================================================
-- GUI: ДОБАВЛЕНИЕ ПРЕДМЕТА
-- ============================================================
function resetAddItemFields()
  addItemFields = {internal = "", display = "", price = "", ema = "", damage = "0"}
  addItemField = 1
  addItemMessage = ""
  addItemMessageColor = C.muted
end

function drawAddItemPage()
  currentScreen = "add_item"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Добавить предмет в каталог")
  local w = math.min(86, screenW - 6)
  local h = math.min(24, screenH - 6)
  local x = math.floor((screenW - w) / 2) + 1
  local y = 5
  drawBox(x, y, w, h, "НОВЫЙ ПРЕДМЕТ", C.accent, C.panel)
  local destLabel = addItemDest == "buy" and "КУДА: МАГАЗИН (ПРОДАЖА)" or "КУДА: ПОПОЛНЕНИЕ (СКУПКА)"
  drawButton("item_dest", x + 3, y + 1, 34, destLabel, addItemDest == "buy" and C.buttonHot or C.green, C.white)
  local labels = {
    internal = "Internal Name (например minecraft:diamond)",
    display = "Название для магазина",
    price = "Цена COIN",
    ema = "Цена EMA (только для продажи)",
    damage = "Damage / Meta",
  }
  for i, key in ipairs(addItemFieldOrder) do
    local fy = y + 3 + (i - 1) * 3
    if fy + 2 < y + h - 4 then
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
  drawFooter("Tab - поля | кнопка КУДА - назначение | Enter - отправить | Esc - назад")
end

-- ============================================================
-- GUI: УДАЛЕНИЕ ПРЕДМЕТА
-- ============================================================
function drawDeleteItemPage()
  currentScreen = "delete_item"
  resetHitboxes()
  clearScreen(C.bg)
  drawHeader("Удалить предмет из каталога")
  local w = math.min(76, screenW - 6)
  local h = 12
  local x = math.floor((screenW - w) / 2) + 1
  local y = math.max(5, math.floor((screenH - h) / 2))
  drawBox(x, y, w, h, "УДАЛЕНИЕ ПРЕДМЕТА", C.red, C.panel)
  writeText(x + 3, y + 2, "Internal Name предмета:", C.text, C.panel)
  fillRect(x + 3, y + 3, w - 6, 1, C.input)
  writeText(x + 4, y + 3, clip(deleteItemInput .. "█", w - 8), C.white, C.input)
  addHitbox("delete_field", x + 3, y + 2, w - 6, 2)
  writeText(x + 3, y + 5, "Удаляется во всех терминалах по всему имени", C.muted, C.panel)
  writeText(x + 3, y + 6, "(все damage-варианты предмета)", C.muted, C.panel)
  local bw = math.floor((w - 10) / 3)
  drawButton("del_buy", x + 3, y + h - 3, bw, "ИЗ ПРОДАЖИ", C.red, C.white)
  drawButton("del_sell", x + 5 + bw, y + h - 3, bw, "ИЗ ПОПОЛНЕНИЯ", C.orange, C.white)
  drawButton("back", x + 7 + bw * 2, y + h - 3, bw, "НАЗАД", C.button, C.white)
  drawFooter("Введите имя | кнопка - откуда удалить | Esc - назад")
end

-- ============================================================
-- ПЕРЕРИСОВКА С ТРОТТЛИНГОМ
-- ============================================================
lastDrawAt = 0
needRedraw = false

function redrawNow()
  updateScreenSize()
  if currentScreen == "dev" then drawDevScreen()
  elseif currentScreen == "login" then drawLoginScreen()
  elseif currentScreen == "dashboard" then drawDashboard()
  elseif currentScreen == "admin_menu" then drawAdminMenu()
  elseif currentScreen == "players" then drawPlayersPage()
  elseif currentScreen == "edit_balance" then drawBalanceEditor()
  elseif currentScreen == "edit_ban" then drawBanEditor()
  elseif currentScreen == "top" then drawTopPage()
  elseif currentScreen == "tx" then drawTransactionsPage()
  elseif currentScreen == "admin_list" then drawAdminListPage()
  elseif currentScreen == "admins" then drawAdminsPage()
  elseif currentScreen == "admin_add" then drawAdminAddPage()
  elseif currentScreen == "reports" then drawReportsPage()
  elseif currentScreen == "report_view" then drawReportView()
  elseif currentScreen == "feedbacks" then drawFeedbacksPage()
  elseif currentScreen == "feedback_view" then drawFeedbackView()
  elseif currentScreen == "feedback_edit_text" then drawFeedbackEditText()
  elseif currentScreen == "stats" then drawStatsPage()
  elseif currentScreen == "logs" then drawLogsPage()
  elseif currentScreen == "add_item" then drawAddItemPage()
  elseif currentScreen == "delete_item" then drawDeleteItemPage()
  else
    currentScreen = "dev"
    drawDevScreen()
  end
end

function redraw()
  local now = computer.uptime()
  if now - lastDrawAt < 0.05 then
    needRedraw = true
    return
  end
  lastDrawAt = now
  needRedraw = false
  redrawNow()
end

function flushRedraw()
  if needRedraw and computer.uptime() - lastDrawAt >= 0.03 then
    lastDrawAt = computer.uptime()
    needRedraw = false
    redrawNow()
  end
end

function goBack()
  if currentScreen == "dashboard" or currentScreen == "dev" or currentScreen == "login" then return end
  if currentScreen == "logs" then logSearch = ""; logScroll = 0
  elseif currentScreen == "players" then playersSearch = ""
  elseif currentScreen == "tx" then txSearch = ""; txScroll = 0 end
  if currentScreen == "feedback_edit_text" then currentScreen = "feedback_view"
  elseif currentScreen == "report_view" then currentScreen = "reports"
  elseif currentScreen == "feedback_view" then currentScreen = "feedbacks"
  elseif currentScreen == "edit_balance" then currentScreen = "players"
  elseif currentScreen == "edit_ban" then editingPlayerName = nil; currentScreen = "players"
  elseif currentScreen == "admin_add" then currentScreen = "admins"
  elseif currentScreen == "stats" or currentScreen == "logs" or currentScreen == "top"
    or currentScreen == "tx" or currentScreen == "delete_item"
    or currentScreen == "admin_list" then currentScreen = "admin_menu"
  elseif currentScreen == "players" or currentScreen == "admins" or currentScreen == "reports"
    or currentScreen == "feedbacks" or currentScreen == "add_item" then currentScreen = "admin_menu"
  elseif currentScreen == "admin_menu" then currentScreen = "dashboard"
  else currentScreen = "dashboard" end
  redraw()
end

function adminGuard(player)
  if serverSession and serverSession.authed and isAdmin(serverSession.player) then return true end
  setToast("Нет прав администратора", C.red, 2)
  if serverSession then currentScreen = "login" else currentScreen = "dev" end
  redraw()
  return false
end

-- ============================================================
-- ДЕЙСТВИЯ GUI
-- ============================================================
function getSelectedPlayer()
  local list = filteredPlayersList()
  return list[selectedPlayerIndex]
end

function saveBalanceEdit()
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
  invalidateTopCache()
  addLog("BALANCE", string.format("%s: COIN %.2f -> %.2f | EMA %.2f -> %.2f", editingPlayerName, oldCoin, coin, oldEma, ema))
  setToast("Баланс сохранён", C.green, 3)
  currentScreen = "players"
  redraw()
  return true
end

function deleteSelectedReport()
  local actual = reportOrder[selectedReportIndex]
  local r = actual and reports[actual]
  if not r then
    setToast("Репорт не выбран", C.red, 2)
    return
  end
  local name = tostring(r.name or "?")
  table.remove(reports, actual)
  reportOrder = buildReportOrder()
  if selectedReportIndex > #reportOrder then selectedReportIndex = math.max(1, #reportOrder) end
  saveReports()
  addLog("REPORT", "Удалён репорт игрока " .. name)
  setToast("Репорт удалён", C.green, 2)
  currentScreen = "reports"
  redraw()
end

function deleteSelectedFeedback()
  local f = feedbacks[selectedFeedbackIndex]
  if not f then
    setToast("Отзыв не выбран", C.red, 2)
    return
  end
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

function submitAddItem()
  local priceCoin = tonumber(addItemFields.price)
  local priceEma = tonumber(addItemFields.ema)
  local damage = tonumber(addItemFields.damage)
  if addItemFields.internal == "" then setToast("Введите Internal Name", C.red, 3); return end
  if addItemFields.display == "" then setToast("Введите название предмета", C.red, 3); return end
  if damage == nil or damage < 0 then setToast("Damage должен быть числом >= 0", C.red, 3); return end
  if next(markets) == nil then setToast("Нет подключённых терминалов", C.red, 3); return end
  local data
  if addItemDest == "sell" then
    if priceCoin == nil or priceCoin <= 0 then setToast("Для пополнения цена COIN должна быть > 0", C.red, 3); return end
    data = {
      op = "add_sell_item",
      internalName = addItemFields.internal,
      displayName = addItemFields.display,
      price = priceCoin,
      qty = 1310720,
      damage = damage,
    }
  else
    if priceCoin == nil or priceCoin < 0 then setToast("Цена COIN должна быть числом >= 0", C.red, 3); return end
    if priceEma == nil or priceEma < 0 then setToast("Цена EMA должна быть числом >= 0", C.red, 3); return end
    if priceCoin <= 0 and priceEma <= 0 then setToast("Укажите цену COIN или EMA больше 0", C.red, 3); return end
    data = {
      op = "add_buy_item",
      internalName = addItemFields.internal,
      displayName = addItemFields.display,
      price_coin = priceCoin,
      price_ema = priceEma,
      price = priceCoin,
      damage = damage,
    }
  end
  local sent = 0
  for addr in pairs(markets) do
    modem.send(addr, PORT_MARKET, serialization.serialize(data))
    sent = sent + 1
  end
  pendingAddItem = {deadline = computer.uptime() + 5, item = addItemFields.display, sent = sent, kind = addItemDest}
  addItemMessage = "Отправлено на " .. sent .. " терминал(ов). Ожидание ответа..."
  addItemMessageColor = C.yellow
  redraw()
end

function submitDeleteItem(kind)
  local name = trimPlayerName(deleteItemInput)
  if name == "" then
    setToast("Введите Internal Name предмета", C.red, 3)
    redraw()
    return
  end
  if next(markets) == nil then
    setToast("Нет подключённых терминалов", C.red, 3)
    redraw()
    return
  end
  local op = (kind == "buy") and "remove_buy_item" or "remove_sell_item"
  local sent = 0
  for addr in pairs(markets) do
    modem.send(addr, PORT_MARKET, serialization.serialize({op = op, internalName = name}))
    sent = sent + 1
  end
  pendingDelete = {deadline = computer.uptime() + 5, name = name, kind = kind, sent = sent}
  setToast("Команда удаления отправлена: " .. name, C.yellow, 3)
  addLog("ADMIN", "Запрошено удаление предмета " .. name .. " (" .. (kind == "buy" and "продажа" or "пополнение") .. ") администратором " .. tostring(serverSession and serverSession.player or "?"))
  redraw()
end

function resetSelectedTopPlayer()
  local list = buildTopList(topCategory)
  local e = list[topSelectedIndex]
  if not e then
    setToast("Игрок не выбран", C.red, 2)
    redraw()
    return
  end
  local s = topStats[e.name]
  if not s then
    setToast("У игрока нет топ-статистики", C.red, 2)
    redraw()
    return
  end
  s.visits = 0; s.purchases = 0; s.sells = 0
  s.spentCoin = 0; s.spentEma = 0; s.earnedCoin = 0; s.earnedEma = 0
  saveTopStats()
  invalidateTopCache()
  addLog("ADMIN", "Сброшен топ игрока " .. e.name .. " администратором " .. tostring(serverSession and serverSession.player or "?"))
  setToast("Топ сброшен: " .. e.name, C.green, 3)
  redraw()
end

function processAction(id, data, player)
  if id == "refresh" then redraw(); return end
  if id == "exit_shell" then
    if not isOwner() then
      setToast("Выход в shell только для владельца", C.red, 3)
      redraw()
      return
    end
    flushSaves(true)
    addLog("ADMIN", "Владелец " .. OWNER .. " завершил сервер (выход в shell)")
    exitRequested = true
    updateScreenSize()
    gpu.setBackground(0x000000)
    gpu.setForeground(0x000000)
    gpu.fill(1, 1, screenW, screenH, " ")
    return
  end
  if id == "update_server" then
    if not isOwner() then
      setToast("Обновление сервера — только владелец", C.red, 3)
      redraw()
      return
    end
    if not filesystem.exists("/home/update.lua") then
      setToast("Файл /home/update.lua не найден", C.red, 3)
      redraw()
      return
    end
    flushSaves(true)
    addLog("ADMIN", "Запуск обновления сервера (update.lua): " .. tostring(player))
    redrawNow()
    os.execute("/home/update.lua")
    setToast("update.lua завершил работу, перезагрузки не было", C.muted, 4)
    redraw()
    return
  end
  if id == "autorun" then
    if not isOwner() then
      setToast("Автооткрытие — только владелец", C.red, 3)
      redraw()
      return
    end
    local enable = not isAutorunEnabled()
    local ok, err = setAutorun(enable)
    if ok then
      addLog("ADMIN", "Автооткрытие " .. (enable and "включено" or "выключено") .. " администратором " .. tostring(player) .. " | строка: " .. AUTORUN_LINE)
      setToast(enable and "Автооткрытие ВКЛ: строка добавлена в .shrc" or "Автооткрытие ВЫКЛ: строка убрана из .shrc", enable and C.green or C.yellow, 4)
    else
      setToast("Ошибка записи .shrc: " .. tostring(err), C.red, 4)
    end
    redraw(); return
  end
  if id == "stats" and currentScreen == "dashboard" then
    if not adminGuard(player) then return end
    currentScreen = "stats"; redraw(); return
  end
  if id == "logs" and currentScreen == "dashboard" then
    if not adminGuard(player) then return end
    logScroll = 0
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
  if id == "players" then
    playerScroll = 0; selectedPlayerIndex = 1
    currentScreen = "players"; redraw(); return
  end
  if id == "players_search" then redraw(); return end
  if id == "players_clear" then
    playersSearch = ""; playerScroll = 0; selectedPlayerIndex = 1
    redraw(); return
  end
  if id == "top" then
    topScroll = 0; topSelectedIndex = 1
    currentScreen = "top"; redraw(); return
  end
  if id == "tx" then
    txScroll = 0; txSearch = ""
    currentScreen = "tx"; redraw(); return
  end
  if id == "tx_search" then redraw(); return end
  if id == "tx_clear" then
    txSearch = ""; txScroll = 0
    redraw(); return
  end
  if id == "top_cat" then
    topCategory = tostring(data or "balance")
    topScroll = 0
    topSelectedIndex = 1
    redraw(); return
  end
  if id == "top_select" then
    topSelectedIndex = tonumber(data) or topSelectedIndex
    redraw(); return
  end
  if id == "top_reset" then resetSelectedTopPlayer(); return end
  if id == "stats" then currentScreen = "stats"; redraw(); return end
  if id == "reports" then
    reportScroll = 0; selectedReportIndex = 1
    currentScreen = "reports"; redraw(); return
  end
  if id == "feedbacks" then
    feedbackScroll = 0; selectedFeedbackIndex = 1
    currentScreen = "feedbacks"; redraw(); return
  end
  if id == "admin_list" then
    adminListScroll = 0
    currentScreen = "admin_list"; redraw(); return
  end
  if id == "admins" then
    if not isOwner() then
      setToast("Управление админами — только владелец", C.red, 3)
      redraw(); return
    end
    currentScreen = "admins"; redraw(); return
  end
  if id == "add_item" then
    resetAddItemFields()
    currentScreen = "add_item"; redraw(); return
  end
  if id == "item_dest" then
    addItemDest = (addItemDest == "buy") and "sell" or "buy"
    redraw(); return
  end
  if id == "del_item" then
    deleteItemInput = ""
    currentScreen = "delete_item"; redraw(); return
  end
  if id == "delete_field" then redraw(); return end
  if id == "del_buy" then submitDeleteItem("buy"); return end
  if id == "del_sell" then submitDeleteItem("sell"); return end
  if id == "logs" then
    logScroll = 0
    currentScreen = "logs"; redraw(); return
  end
  if id == "logs_search" then redraw(); return end
  if id == "logs_clear" then
    logSearch = ""; logScroll = 0
    redraw(); return
  end
  if id == "admin_add" then
    if not isOwner() then
      setToast("Только владелец может добавлять администраторов", C.red, 3)
      redraw(); return
    end
    adminInput = ""; adminPasswordInput = ""; adminField = 1
    currentScreen = "admin_add"; redraw(); return
  end
  if id == "admin_add_confirm" then
    if not isOwner() then
      setToast("Только владелец может добавлять администраторов", C.red, 3)
      redraw(); return
    end
    local nick = trimPlayerName(adminInput)
    local pwd = adminPasswordInput
    if nick == "" then setToast("Введите ник игрока", C.red, 3); redraw(); return end
    if ulen(pwd) < 4 then setToast("Пароль минимум 4 символа", C.red, 3); redraw(); return end
    if isAdmin(nick) then setToast("Этот игрок уже администратор", C.red, 3); redraw(); return end
    admins[nick] = pwd
    saveAdmins()
    addLog("ADMIN", "Владелец " .. OWNER .. " добавил администратора " .. nick)
    setToast("Администратор добавлен: " .. nick, C.green, 3)
    adminInput = ""; adminPasswordInput = ""; adminField = 1
    currentScreen = "admins"; redraw(); return
  end
  if id == "admin_delete" then
    if not isOwner() then
      setToast("Только владелец может удалять администраторов", C.red, 3)
      redraw(); return
    end
    local list = sortedAdmins()
    local name = list[selectedAdminIndex]
    if not name then setToast("Администратор не выбран", C.red, 2); redraw(); return end
    if samePlayerName(name, OWNER) then
      setToast("Нельзя удалить владельца", C.red, 3)
      redraw(); return
    end
    admins[name] = nil
    saveAdmins()
    if selectedAdminIndex > #sortedAdmins() then selectedAdminIndex = math.max(1, #sortedAdmins()) end
    addLog("ADMIN", "Владелец " .. OWNER .. " удалил администратора " .. name)
    setToast("Администратор удалён: " .. name, C.green, 3)
    redraw(); return
  end
  if id == "pause" then
    if not adminGuard(player) then return end
    shopPaused = not shopPaused
    addLog("ADMIN", "Тех. работы " .. (shopPaused and "включены" or "сняты") .. " администратором " .. tostring(player))
    setToast(shopPaused and "Включены ТЕХ. РАБОТЫ" or "ТЕХ. РАБОТЫ сняты", shopPaused and C.yellow or C.green, 3)
    redraw(); return
  end
  if id == "player_select" then
    selectedPlayerIndex = tonumber(data) or selectedPlayerIndex
    redraw(); return
  end
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
    if p.data.banned then
      p.data.banned = false
      p.data.banInfo = nil
      p.data.banUntil = nil
      saveDB()
      addLog("BAN", p.name .. " разблокирован администратором " .. tostring(player))
      setToast("Игрок разблокирован", C.green, 2)
      redraw(); return
    end
    editingPlayerName = p.name
    banReasonInput = ""
    banDurationInput = ""
    banField = 1
    currentScreen = "edit_ban"
    redraw(); return
  end
  if id == "ban_field" then banField = tonumber(data) or banField; redraw(); return end
  if id == "ban_cancel" then
    editingPlayerName = nil
    currentScreen = "players"
    redraw(); return
  end
  if id == "ban_save" then
    local name = editingPlayerName
    local p = name and players[name] or nil
    if not p then setToast("Игрок не найден", C.red, 3); redraw(); return end
    local reason = banReasonInput
    if reason == "" then reason = "Можно спросить у Администрации" end
    local banUntil, display = parseBanDuration(banDurationInput)
    p.banned = true
    p.banUntil = banUntil
    p.banInfo = {admin = tostring(player), date = getRealDateTimeString(), reason = reason, duration = display}
    saveDB()
    addLog("BAN", name .. " заблокирован администратором " .. tostring(player) .. " | причина: " .. reason .. " | срок: " .. display)
    setToast("Игрок заблокирован: " .. name, C.red, 3)
    editingPlayerName = nil
    currentScreen = "players"
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
  if id == "admin_input" then adminField = tonumber(data) or adminField; redraw(); return end
  if id == "report_select" then selectedReportIndex = tonumber(data) or selectedReportIndex; redraw(); return end
  if id == "report_pin" then
    toggleReportPin(tonumber(data) or 0)
    redraw(); return
  end
  if id == "report_pin_sel" then
    local actual = reportOrder[selectedReportIndex]
    if actual then toggleReportPin(actual) end
    redraw(); return
  end
  if id == "report_open" then
    if reportOrder[selectedReportIndex] then currentScreen = "report_view"; redraw() end
    return
  end
  if id == "report_delete" then deleteSelectedReport(); return end
  if id == "feedback_select" then selectedFeedbackIndex = tonumber(data) or selectedFeedbackIndex; redraw(); return end
  if id == "feedback_open" then
    if feedbacks[selectedFeedbackIndex] then currentScreen = "feedback_view"; redraw() end
    return
  end
  if id == "feedback_delete" then deleteSelectedFeedback(); return end
  if id == "feedback_star" then
    setFeedbackRating(selectedFeedbackIndex, tonumber(data) or 0)
    redraw(); return
  end
  if id == "feedback_edit_text" then
    local f = feedbacks[selectedFeedbackIndex]
    if f then
      feedbackEditText = tostring(f.text or "")
      currentScreen = "feedback_edit_text"
      redraw()
    end
    return
  end
  if id == "feedback_edit_save" then
    local f = feedbacks[selectedFeedbackIndex]
    if f then
      f.text = feedbackEditText
      saveFeedbacks()
      addLog("FEEDBACK", "Изменён текст отзыва " .. tostring(f.name or "?"))
      setToast("Текст отзыва сохранён", C.green, 2)
      currentScreen = "feedback_view"
      redraw()
    end
    return
  end
  if id == "item_field" then addItemField = tonumber(data) or addItemField; redraw(); return end
  if id == "item_submit" then submitAddItem(); return end
end

-- ============================================================
-- КЛАВИАТУРА (АВТОРИЗАЦИЯ НЕ ТРОНУТА)
-- ============================================================
function asciiKey(char)
  if type(char) ~= "number" or char < 1 or char > 255 then return nil end
  return string.lower(string.char(char))
end

function appendInput(current, char, numeric, allowDot)
  if type(char) ~= "number" or char < 32 then return current end
  local c = unicode.char(char)
  if numeric then
    if c:match("%d") then return current .. c end
    if allowDot and (c == "." or c == ",") and not current:find("[.,]") then return current .. "." end
    return current
  end
  return current .. c
end

function handleKey(char, code, player)
  if currentScreen == "dev" then return end
  if currentScreen == "login" then
    if not serverSession then currentScreen = "dev"; redraw(); return end
    if player and trimPlayerName(player) ~= "" and not samePlayerName(player, serverSession.player) then return end
    if char == 13 then
      local stored = getAdminPassword(serverSession.player)
      if stored and stored ~= "" and passwordBuffer == stored then
        serverSession.authed = true
        passwordBuffer = ""
        currentScreen = "dashboard"
        addLog("ADMIN", "Вход в панель сервера: " .. serverSession.player)
        setToast("Доступ разрешён: " .. serverSession.player, C.green, 2)
      else
        passwordBuffer = ""
      end
      redraw(); return
    end
    if char == 8 then passwordBuffer = eraseLastChar(passwordBuffer); redraw(); return end
    if char >= 32 and char <= 0x10FFFF then
      if ulen(passwordBuffer) < 32 then passwordBuffer = passwordBuffer .. unicode.char(char) end
      redraw(); return
    end
    return
  end
  if not serverSession or not serverSession.authed then
    currentScreen = serverSession and "login" or "dev"
    redraw(); return
  end
  player = serverSession.player
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
    local list = filteredPlayersList()
    if char == 8 then
      playersSearch = eraseLastChar(playersSearch)
      selectedPlayerIndex = 1
      redraw(); return
    end
    if char >= 32 and char <= 0x10FFFF then
      if ulen(playersSearch) < 20 then playersSearch = playersSearch .. unicode.char(char) end
      selectedPlayerIndex = 1
      redraw(); return
    end
    if code == 200 then
      if selectedPlayerIndex > 1 then selectedPlayerIndex = selectedPlayerIndex - 1; redraw() end
      return
    end
    if code == 208 then
      if selectedPlayerIndex < #list then selectedPlayerIndex = selectedPlayerIndex + 1; redraw() end
      return
    end
    if char == 13 then processAction("edit_balance", nil, player); return end
    if key == "b" then processAction("toggle_ban", nil, player); return end
    return
  end

  if currentScreen == "top" then
    if char >= 49 and char <= 53 then
      local cat = TOP_CATS[char - 48]
      if cat then
        topCategory = cat.key
        topScroll = 0
        topSelectedIndex = 1
        redraw()
      end
      return
    end
    local list = buildTopList(topCategory)
    if code == 200 then
      if topSelectedIndex > 1 then topSelectedIndex = topSelectedIndex - 1; redraw() end
      return
    end
    if code == 208 then
      if topSelectedIndex < #list then topSelectedIndex = topSelectedIndex + 1; redraw() end
      return
    end
    return
  end

  if currentScreen == "tx" then
    if char == 8 then
      txSearch = eraseLastChar(txSearch)
      txScroll = 0
      redraw(); return
    end
    if char >= 32 and char <= 0x10FFFF then
      if ulen(txSearch) < 30 then txSearch = txSearch .. unicode.char(char) end
      txScroll = 0
      redraw(); return
    end
    local list = filteredTransactions()
    if code == 200 then
      if txScroll > 0 then txScroll = txScroll - 1; redraw() end
      return
    end
    if code == 208 then
      local maxScroll = math.max(0, #list - txVisibleRows())
      if txScroll < maxScroll then txScroll = txScroll + 1; redraw() end
      return
    end
    return
  end

  if currentScreen == "logs" then
    if char == 8 then
      logSearch = eraseLastChar(logSearch)
      logScroll = 0
      redraw(); return
    end
    if char >= 32 and char <= 0x10FFFF then
      if ulen(logSearch) < 30 then logSearch = logSearch .. unicode.char(char) end
      logScroll = 0
      redraw(); return
    end
    local list = filteredLogs()
    if code == 200 then
      if logScroll > 0 then logScroll = logScroll - 1; redraw() end
      return
    end
    if code == 208 then
      local maxScroll = math.max(0, #list - logsVisibleRows())
      if logScroll < maxScroll then logScroll = logScroll + 1; redraw() end
      return
    end
    return
  end

  if currentScreen == "admin_list" then
    local list = sortedAdminsOwnerFirst()
    if code == 200 then
      if adminListScroll > 0 then adminListScroll = adminListScroll - 1; redraw() end
      return
    end
    if code == 208 then
      local maxScroll = math.max(0, #list - adminListVisibleRows())
      if adminListScroll < maxScroll then adminListScroll = adminListScroll + 1; redraw() end
      return
    end
    return
  end

  if currentScreen == "reports" then
    if code == 200 then
      if selectedReportIndex > 1 then selectedReportIndex = selectedReportIndex - 1; redraw() end
      return
    end
    if code == 208 then
      if selectedReportIndex < #reportOrder then selectedReportIndex = selectedReportIndex + 1; redraw() end
      return
    end
    if key == "p" then
      local actual = reportOrder[selectedReportIndex]
      if actual then toggleReportPin(actual); redraw() end
      return
    end
    if char == 13 then processAction("report_open", nil, player); return end
    if code == 211 or char == 127 then processAction("report_delete", nil, player); return end
    return
  end

  if currentScreen == "report_view" then
    if key == "p" then
      local actual = reportOrder[selectedReportIndex]
      if actual then toggleReportPin(actual); redraw() end
      return
    end
    if code == 211 or char == 127 then processAction("report_delete", nil, player); return end
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

  if currentScreen == "edit_ban" then
    if char == 9 then banField = banField % 2 + 1; redraw(); return end
    if char == 13 then processAction("ban_save", nil, player); return end
    if char == 8 then
      if banField == 1 then banReasonInput = eraseLastChar(banReasonInput)
      else banDurationInput = eraseLastChar(banDurationInput) end
      redraw(); return
    end
    if char >= 32 and char <= 0x10FFFF then
      local c = unicode.char(char)
      if banField == 1 then
        if ulen(banReasonInput) < 60 then banReasonInput = banReasonInput .. c end
      else
        if c:match("[0-9smhdoySMHDOY]") then
          if ulen(banDurationInput) < 12 then banDurationInput = banDurationInput .. string.lower(c) end
        end
      end
      redraw(); return
    end
    return
  end

  if currentScreen == "admins" then
    local list = sortedAdmins()
    if code == 200 then
      if selectedAdminIndex > 1 then selectedAdminIndex = selectedAdminIndex - 1; redraw() end
      return
    end
    if code == 208 then
      if selectedAdminIndex < #list then selectedAdminIndex = selectedAdminIndex + 1; redraw() end
      return
    end
    if code == 210 then processAction("admin_add", nil, player); return end
    if code == 211 or char == 127 then processAction("admin_delete", nil, player); return end
    return
  end

  if currentScreen == "admin_add" then
    if char == 9 then adminField = (adminField == 1) and 2 or 1; redraw(); return end
    if char == 13 then processAction("admin_add_confirm", nil, player); return end
    if char == 8 then
      if adminField == 1 then adminInput = eraseLastChar(adminInput)
      else adminPasswordInput = eraseLastChar(adminPasswordInput) end
      redraw(); return
    end
    if char >= 32 and char <= 0x10FFFF then
      if adminField == 1 then
        if ulen(adminInput) < 24 then adminInput = adminInput .. unicode.char(char) end
      else
        if ulen(adminPasswordInput) < 32 then adminPasswordInput = adminPasswordInput .. unicode.char(char) end
      end
      redraw(); return
    end
    return
  end

  if currentScreen == "feedbacks" then
    if code == 200 then
      if selectedFeedbackIndex > 1 then selectedFeedbackIndex = selectedFeedbackIndex - 1; redraw() end
      return
    end
    if code == 208 then
      if selectedFeedbackIndex < #feedbacks then selectedFeedbackIndex = selectedFeedbackIndex + 1; redraw() end
      return
    end
    if key and key >= "1" and key <= "5" then
      setFeedbackRating(selectedFeedbackIndex, tonumber(key))
      redraw(); return
    end
    if char == 13 then processAction("feedback_open", nil, player); return end
    if code == 211 or char == 127 then processAction("feedback_delete", nil, player); return end
    return
  end

  if currentScreen == "feedback_view" then
    if key and key >= "1" and key <= "5" then
      setFeedbackRating(selectedFeedbackIndex, tonumber(key))
      redraw(); return
    end
    if code == 211 or char == 127 then processAction("feedback_delete", nil, player); return end
    return
  end

  if currentScreen == "feedback_edit_text" then
    if char == 13 then processAction("feedback_edit_save", nil, player); return end
    if char == 8 then feedbackEditText = eraseLastChar(feedbackEditText); redraw(); return end
    if char >= 32 then
      if ulen(feedbackEditText) < 500 then feedbackEditText = feedbackEditText .. unicode.char(char); redraw() end
      return
    end
    return
  end

  if currentScreen == "add_item" then
    if char == 9 then addItemField = addItemField % #addItemFieldOrder + 1; redraw(); return end
    if char == 13 then submitAddItem(); return end
    local fieldKey = addItemFieldOrder[addItemField]
    if char == 8 then
      addItemFields[fieldKey] = eraseLastChar(addItemFields[fieldKey])
    else
      local numeric = fieldKey == "price" or fieldKey == "ema" or fieldKey == "damage"
      local allowDecimal = fieldKey == "price" or fieldKey == "ema"
      addItemFields[fieldKey] = appendInput(addItemFields[fieldKey], char, numeric, allowDecimal)
    end
    redraw(); return
  end

  if currentScreen == "delete_item" then
    if char == 8 then
      deleteItemInput = eraseLastChar(deleteItemInput)
      redraw(); return
    end
    if char >= 32 and char <= 0x10FFFF then
      if ulen(deleteItemInput) < 60 then deleteItemInput = deleteItemInput .. unicode.char(char) end
      redraw(); return
    end
    return
  end
end

-- ============================================================
-- TOUCH / SCROLL
-- ============================================================
function handleTouch(x, y, player)
  if currentScreen == "dev" or currentScreen == "login" then return end
  if not serverSession or not serverSession.authed then
    currentScreen = serverSession and "login" or "dev"
    redraw(); return
  end
  local b = hitTest(x, y)
  if not b then return end
  processAction(b.id, b.data, serverSession.player)
end

function handleScrollDelta(delta)
  if currentScreen == "dev" or currentScreen == "login" then return end
  if not serverSession or not serverSession.authed then return end
  if delta == 0 then return end
  local changed = false
  if currentScreen == "top" then
    local list = buildTopList(topCategory)
    local ns = clamp(topScroll + delta, 0, math.max(0, #list - topVisibleRows()))
    if ns ~= topScroll then topScroll = ns; changed = true end
  elseif currentScreen == "tx" then
    local list = filteredTransactions()
    local ns = clamp(txScroll + delta, 0, math.max(0, #list - txVisibleRows()))
    if ns ~= txScroll then txScroll = ns; changed = true end
  elseif currentScreen == "logs" then
    local list = filteredLogs()
    local ns = clamp(logScroll + delta, 0, math.max(0, #list - logsVisibleRows()))
    if ns ~= logScroll then logScroll = ns; changed = true end
  elseif currentScreen == "players" then
    local list = filteredPlayersList()
    local ns = clamp(selectedPlayerIndex + delta, 1, math.max(1, #list))
    if ns ~= selectedPlayerIndex then selectedPlayerIndex = ns; changed = true end
  elseif currentScreen == "reports" then
    local ns = clamp(selectedReportIndex + delta, 1, math.max(1, #reportOrder))
    if ns ~= selectedReportIndex then selectedReportIndex = ns; changed = true end
  elseif currentScreen == "feedbacks" then
    local ns = clamp(selectedFeedbackIndex + delta, 1, math.max(1, #feedbacks))
    if ns ~= selectedFeedbackIndex then selectedFeedbackIndex = ns; changed = true end
  elseif currentScreen == "admins" then
    local list = sortedAdmins()
    local ns = clamp(selectedAdminIndex + delta, 1, math.max(1, #list))
    if ns ~= selectedAdminIndex then selectedAdminIndex = ns; changed = true end
  elseif currentScreen == "admin_list" then
    local list = sortedAdminsOwnerFirst()
    local ns = clamp(adminListScroll + delta, 0, math.max(0, #list - adminListVisibleRows()))
    if ns ~= adminListScroll then adminListScroll = ns; changed = true end
  end
  if changed then redraw() end
end

-- ============================================================
-- MODEM
-- ============================================================
function sendMessage(to, data)
  modem.send(to, PORT_MARKET, serialization.serialize(data))
end

lastUsefulRedraw = 0
function redrawIfUseful()
  local now = computer.uptime()
  if now - lastUsefulRedraw < 0.5 then return end
  lastUsefulRedraw = now
  if currentScreen == "dashboard" or currentScreen == "stats" or currentScreen == "logs"
    or currentScreen == "players" or currentScreen == "reports" or currentScreen == "feedbacks"
    or currentScreen == "top" or currentScreen == "tx" then
    redraw()
  end
end

function handleModemMessage(from, port, raw)
  local ok, msg = pcall(serialization.unserialize, raw)
  if not ok or type(msg) ~= "table" then return end
  if port == PORT_MARKET and from then
    if not markets[from] then markets[from] = true end
    if not owner then owner = from end
    marketConnected = true
  end
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

  if msg.op == "pim_leave" then
    if not LOCAL_PIM then handlePimLeave(msg.name) end
    return
  end

  if msg.op == "enter" then
    if shopPaused then
      sendMessage(from, {op = "error", message = "Технические работы"})
      return
    end
    local playerName = msg.name
    if not playerName or playerName == "" then return end
    local player = getOrCreatePlayer(playerName)
    if player.banned and player.banUntil and nowEpoch() >= (tonumber(player.banUntil) or 0) then
      player.banned = false
      player.banInfo = nil
      player.banUntil = nil
      saveDB()
      addLog("BAN", playerName .. " разблокирован автоматически (срок истёк)")
    end
    if player.banned then
      sendMessage(from, {op = "error", message = "Вы забанены", banInfo = player.banInfo or
        {admin = OWNER, duration = "навсегда", reason = "Можно спросить у Администрации", date = player.regDate}})
      return
    end
    if not LOCAL_PIM then handlePimEnter(playerName) end
    local ts = ensureTopEntry(playerName)
    local ne = nowEpoch()
    if ne - (tonumber(ts.lastVisitEpoch) or 0) >= 30 then
      ts.visits = (tonumber(ts.visits) or 0) + 1
      ts.lastVisitEpoch = ne
      ts.lastVisit = getRealDateTimeString()
      saveTopStats()
      invalidateTopCache()
    end
    local existing = sessions[playerName]
    local token
    if existing and ne - (existing.lastAction or 0) < SESSION_TIMEOUT then
      token = existing.token
      existing.lastAction = ne
    else
      token = tostring(math.floor(math.random() * 900000000 + 100000000))
      sessions[playerName] = {token = token, lastAction = ne}
    end
    sendMessage(from, {
      op = "welcome", status = "ok", token = token,
      balance = player.balance or 0.0, emaBalance = player.emaBalance or 0.0,
      transactions = player.transactions or 0, regDate = player.regDate,
      agreed = player.agreed or false, shopPaused = shopPaused,
      banned = player.banned or false, banInfo = player.banInfo or nil,
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
    sessions[msg.name].lastAction = nowEpoch()
    sendMessage(from, {
      op = "accountData",
      data = {
        balance = player.balance or 0.0, emaBalance = player.emaBalance or 0.0,
        transactions = player.transactions or 0, regDate = player.regDate,
        agreed = player.agreed, shopPaused = shopPaused,
        banned = player.banned or false, banInfo = player.banInfo or nil,
      },
    })
    return
  end

  if msg.op == "sell" then
    if shopPaused then sendMessage(from, {op = "error", message = "Технические работы"}); return end
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
    sessions[msg.name].lastAction = nowEpoch()
    ensureStats()
    globalStats.totalSells = globalStats.totalSells + 1
    globalStats.totalSellItems = globalStats.totalSellItems + qty
    globalStats.totalSellCoin = globalStats.totalSellCoin + coinValue
    globalStats.totalSellEma = globalStats.totalSellEma + emaValue
    globalStats.today.sells = globalStats.today.sells + 1
    globalStats.today.sellItems = globalStats.today.sellItems + qty
    globalStats.today.sellCoin = globalStats.today.sellCoin + coinValue
    globalStats.today.sellEma = globalStats.today.sellEma + emaValue
    topIncr(msg.name, "sells", 1)
    if emaValue > 0 then topIncr(msg.name, "earnedEma", emaValue) end
    if coinValue > 0 then topIncr(msg.name, "earnedCoin", coinValue) end
    saveDB()
    saveStats()
    invalidateTopCache()
    addTransaction({type = "sell", player = msg.name, item = msg.item, qty = qty, coin = coinValue, ema = emaValue})
    addLog("SELL", string.format("%s продал '%s' x%d | +%.2f COIN +%.2f EMA", msg.name, tostring(msg.item or "?"), qty, coinValue, emaValue))
    redrawIfUseful()
    return
  end

  if msg.op == "buy" then
    if shopPaused then sendMessage(from, {op = "error", message = "Технические работы"}); return end
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
    sessions[msg.name].lastAction = nowEpoch()
    ensureStats()
    globalStats.totalBuys = globalStats.totalBuys + 1
    globalStats.totalBuyItems = globalStats.totalBuyItems + qty
    globalStats.totalBuyCoin = globalStats.totalBuyCoin + valueCoin
    globalStats.totalBuyEma = globalStats.totalBuyEma + valueEma
    globalStats.today.buys = globalStats.today.buys + 1
    globalStats.today.buyItems = globalStats.today.buyItems + qty
    globalStats.today.buyCoin = globalStats.today.buyCoin + valueCoin
    globalStats.today.buyEma = globalStats.today.buyEma + valueEma
    topIncr(msg.name, "purchases", 1)
    topIncr(msg.name, "spentCoin", valueCoin)
    topIncr(msg.name, "spentEma", valueEma)
    saveDB()
    saveStats()
    invalidateTopCache()
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
    table.insert(reports, 1, {time = msg.time or getRealDateTimeString(), name = msg.name or "?", text = msg.text or "", pinned = false})
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
      sessions[msg.name].lastAction = nowEpoch()
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
    sendMessage(from, {op = "feedbacks_list", feedbacks = feedbacks, hasFeedback = player and player.hasFeedback or false})
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
    table.insert(feedbacks, 1, {
      name = msg.name, text = msg.text or "",
      rating = math.floor(tonumber(msg.rating) or 0),
      time = msg.time or getRealDateTimeString(),
    })
    while #feedbacks > 500 do table.remove(feedbacks) end
    saveFeedbacks()
    player.hasFeedback = true
    saveDB()
    sendMessage(from, {op = "add_feedback_response", success = true})
    addLog("FEEDBACK", "Новый отзыв от " .. tostring(msg.name) .. " (" .. tostring(math.floor(tonumber(msg.rating) or 0)) .. "/5)")
    redrawIfUseful()
    return
  end

  if msg.op == "update_stats" then return end

  if msg.op == "get_top" then
    local category = msg.category or "balance"
    local valid = {balance = true, visits = true, spent = true, earned = true, purchases = true, sells = true}
    if not valid[category] then category = "balance" end
    local page = math.max(1, tonumber(msg.page) or 1)
    local perPage = math.max(1, tonumber(msg.perPage) or 10)
    local list, totalPages, total = getTopList(category, page, perPage)
    sendMessage(from, {op = "top_data", list = list, totalPages = totalPages, total = total, category = category, page = page})
    return
  end

  if msg.op == "add_buy_item_response" then
    if pendingAddItem then
      if msg.success then
        if pendingAddItem.kind == "buy" then
          for addr in pairs(markets) do sendMessage(addr, {op = "reload_buy_items"}) end
        end
        addItemMessage = "Предмет добавлен (" .. (pendingAddItem.kind == "buy" and "продажа" or "пополнение") .. "). Каталог обновляется."
        addItemMessageColor = C.green
        addLog("ADMIN", "Добавлен предмет в каталог (" .. pendingAddItem.kind .. "): " .. tostring(pendingAddItem.item))
        resetAddItemFields()
      else
        addItemMessage = "Ошибка добавления предмета: " .. tostring(msg.error or "неизвестно")
        addItemMessageColor = C.red
      end
      pendingAddItem = nil
      if currentScreen == "add_item" then redraw() end
      return
    end
    if pendingDelete then
      if msg.success then
        setToast("Предмет удалён: " .. pendingDelete.name, C.green, 3)
        addLog("ADMIN", "Предмет удалён из каталога: " .. pendingDelete.name)
      else
        setToast("Ошибка удаления: " .. tostring(msg.error or "?"), C.red, 3)
      end
      pendingDelete = nil
      redrawIfUseful()
      return
    end
  end
end

-- ============================================================
-- БЕЗОПАСНЫЙ EVENT.PULL
-- ============================================================
function safeEventPull(timeout)
  local result = {pcall(event.pull, timeout)}
  if not result[1] then return nil end
  table.remove(result, 1)
  return table.unpack(result)
end

-- ============================================================
-- ОБРАБОТКА СОБЫТИЙ
-- ============================================================
function processEvent(etype, a2, a3, a4, a5, a6)
  if etype == "player_on" or etype == "pim" or etype == "pim_player_enter" then
    handlePimEnter(a2)
  elseif etype == "player_off" or etype == "pim_player_leave" then
    handlePimLeave(a2)
  elseif etype == "key_down" then
    handleKey(a3, a4, a5)
  elseif etype == "touch" then
    handleTouch(a3, a4, a6)
  elseif etype == "modem_message" then
    handleModemMessage(a3, a4, a6)
  elseif etype == "screen_resized" then
    redraw()
  end
end

-- ============================================================
-- ОСНОВНОЙ ЦИКЛ
-- ============================================================
function main()
  updateScreenSize()
  addLog("SYSTEM", "Сервер запущен")
  flushSaves()
  currentScreen = "dev"
  redrawNow()
  local carry = nil
  while true do
    if exitRequested then return end
    ensureStats()
    if computer.uptime() - lastFlush >= 2 then flushSaves() end
    if pendingAddItem and computer.uptime() >= pendingAddItem.deadline then
      addItemMessage = "Ответ не получен за 5 сек. Предмет мог быть добавлен — проверьте каталог."
      addItemMessageColor = C.yellow
      pendingAddItem = nil
      if currentScreen == "add_item" then redraw() end
    end
    if pendingDelete and computer.uptime() >= pendingDelete.deadline then
      setToast("Терминалы не ответили на удаление", C.red, 3)
      pendingDelete = nil
    end
    local e1, a2, a3, a4, a5, a6
    if carry then
      e1, a2, a3, a4, a5, a6 = carry[1], carry[2], carry[3], carry[4], carry[5], carry[6]
      carry = nil
    else
      e1, a2, a3, a4, a5, a6 = safeEventPull(0.5)
    end
    if e1 == "scroll" then
      local delta = (a5 == -1) and 1 or -1
      while true do
        local nxt = {safeEventPull(0)}
        if nxt[1] == nil then break end
        if nxt[1] == "scroll" then
          delta = delta + ((nxt[5] == -1) and 1 or -1)
        else
          carry = nxt
          break
        end
      end
      handleScrollDelta(delta)
    elseif e1 then
      processEvent(e1, a2, a3, a4, a5, a6)
    end
    flushRedraw()
    local clock = getRealTimeString()
    if clock ~= lastClock then
      lastClock = clock
      if currentScreen ~= "dev" and currentScreen ~= "login" then
        drawHeaderClock()
      end
      if currentScreen == "dashboard" then
        drawDashboardLiveValues()
      end
    end
  end
end

-- ============================================================
-- ЗАПУСК + АВТОПЕРЕЗАПУСК + ВЫХОД В SHELL
-- ============================================================
while not exitRequested do
  local ok, err = pcall(main)
  if exitRequested then break end
  if not ok then
    pcall(flushSaves)
    appendText(EVENTS_LOG_PATH, string.format("[%s] [ERROR] %s", getRealDateTimeString(), tostring(err)))
    pcall(function()
      updateScreenSize()
      clearScreen(C.bg)
      centerText(math.floor(screenH / 2), "Ошибка: " .. clip(tostring(err), screenW - 10), C.red, C.bg)
      centerText(math.floor(screenH / 2) + 2, "Перезапуск через 3 секунды...", C.yellow, C.bg)
    end)
    os.sleep(3)
  end
end
pcall(flushSaves)
gpu.setBackground(0x000000)
gpu.setForeground(0x000000)
do
  local w, h = gpu.getResolution()
  gpu.fill(1, 1, w, h, " ")
end
