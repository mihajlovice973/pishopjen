-- ============================================================
-- PIMSERVER.LUA v2.0 — СЕРВЕР МАГАЗИНА (PC SHOP)
-- + ТОПЫ ИГРОКОВ ХРАНЯТСЯ НА СЕРВЕРЕ (в базе игроков, файл shop_db.json)
-- + скорость: отложенные сохранения (раз в 5 сек), кэш топов,
--   перерисовка GUI только при изменениях, пакетная обработка событий
-- + новые разделы: Экономика, Транзакции, Отзывы(удаление), Репорты,
--   Админы, Настройки(пауза/сохранить), поиск по игрокам, скролл списков
-- + авто-разбан по сроку (минуты), бан с причиной/админом/датой
-- + GUI в твоём стиле: боксы, шапка/подвал, тосты, мышь + клавиатура
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
local screenW, screenH = gpu.getResolution()
local mw, mh = gpu.maxResolution()
if mw > screenW or mh > screenH then gpu.setResolution(mw, mh); screenW, screenH = mw, mh end

-- ============================================================
-- ПУТИ ФАЙЛОВ (ВСЁ ХРАНИТСЯ НА СЕРВЕРНОМ ПК)
-- ============================================================
local DB_PATH    = "/home/shop_db.json"        -- игроки + их топы
local TX_PATH    = "/home/transactions.json"   -- журнал сделок
local FB_PATH    = "/home/feedbacks.json"      -- отзывы
local REP_PATH   = "/home/reports.json"        -- репорты
local ADM_PATH   = "/home/admins.json"         -- администраторы
local CFG_PATH   = "/home/shop_config.json"    -- настройки (пауза и т.д.)
local LOG_PATH   = "/home/shop_log.txt"        -- текстовый лог
local OWNER = "KaRMa__"
local ACCESS_PASSWORD = "yVGF7wT"
local SAVE_INTERVAL = 5.0
local VISIT_COOLDOWN = 30

local C = {
  bg = 0x0E0E14, panel = 0x16161F, panel2 = 0x1E1E2A, button = 0x2A2A3A,
  sel = 0x5A189A, accent = 0x9D4EDD, border = 0x6A0DAD,
  text = 0xB8B8C8, white = 0xE8E8F0, muted = 0x6A6A7A,
  green = 0x00D9A3, red = 0xFF4D6D, yellow = 0xFFB700,
  gold = 0xFFD700, coin = 0xFFCE7A, ema = 0x7FB6FF, input = 0x101016,
}

-- ============================================================
-- УТИЛИТЫ
-- ============================================================
local function timeStr() return os.date("%d.%m.%Y %H:%M:%S") end
local function trim(s) s = tostring(s or ""); return (s:match("^%s*(.-)%s*$") or s) end
local function clip(s, w) s = tostring(s or ""); if unicode.len(s) <= w then return s end return unicode.sub(s, 1, w - 1) .. "…" end
local function loadJSON(path, def)
  if fs.exists(path) then
    local f = io.open(path, "r")
    if f then
      local raw = f:read("*a"); f:close()
      local ok, data = pcall(serialization.unserialize, raw)
      if ok and type(data) == type(def) then return data end
    end
  end
  return def
end
local function saveJSON(path, obj)
  local f = io.open(path, "w")
  if f then f:write(serialization.serialize(obj)); f:close() end
end
local function logLine(msg)
  local f = io.open(LOG_PATH, "a")
  if f then f:write(timeStr() .. " " .. msg .. "\n"); f:close() end
end

-- ============================================================
-- СОСТОЯНИЕ СЕРВЕРА
-- ============================================================
local players      = loadJSON(DB_PATH, {})
local transactions = loadJSON(TX_PATH, {})
local feedbacks    = loadJSON(FB_PATH, {})
local reports      = loadJSON(REP_PATH, {})
local admins       = loadJSON(ADM_PATH, {})
local config       = loadJSON(CFG_PATH, { paused = false })
if type(config) ~= "table" then config = { paused = false } end
if not admins[OWNER] then admins[OWNER] = ACCESS_PASSWORD end

local saveDirty = {}
local SAVE_OBJECTS = {
  [DB_PATH]  = function() return players end,
  [TX_PATH]  = function() return transactions end,
  [FB_PATH]  = function() return feedbacks end,
  [REP_PATH] = function() return reports end,
  [ADM_PATH] = function() return admins end,
  [CFG_PATH] = function() return config end,
}
local function markDirty(path) saveDirty[path] = true end
local lastSaveAt = computer.uptime()
local function flushSaves(force)
  local nowU = computer.uptime()
  if not force and (nowU - lastSaveAt) < SAVE_INTERVAL then return end
  for path in pairs(saveDirty) do
    local getter = SAVE_OBJECTS[path]
    if getter then saveJSON(path, getter()) end
  end
  saveDirty = {}
  lastSaveAt = nowU
end

local sessions = {}   -- token -> nick
local function makeToken(name)
  local t = name .. "-" .. tostring(os.time()) .. "-" .. tostring(math.floor(computer.uptime() * 100))
  sessions[t] = name
  return t
end
local function sessionName(token) return token and sessions[token] or nil end

-- ============================================================
-- ТОПЫ: КЭШ + СБОР ИЗ БАЗЫ ИГРОКОВ
-- ============================================================
local topCache = {}
local function invalidateTops() topCache = {} end
local CATEGORY_GET = {
  balance   = function(p) return (p.balance or 0) + (p.emaBalance or 0) end,
  visits    = function(p) return p.visits or 0 end,
  spent     = function(p) return (p.spentCoin or 0) + (p.spentEma or 0) end,
  purchases = function(p) return p.purchases or 0 end,
  sells     = function(p) return (p.earnedCoin or 0) + (p.earnedEma or 0) end,
  earned    = function(p) return (p.earnedCoin or 0) + (p.earnedEma or 0) end,
}
local function buildTop(category)
  if topCache[category] then return topCache[category] end
  local get = CATEGORY_GET[category] or CATEGORY_GET.balance
  local list = {}
  for name, p in pairs(players) do
    list[#list + 1] = {
      name = name, value = get(p),
      coin = p.balance or 0, ema = p.emaBalance or 0,
      spentCoin = p.spentCoin or 0, spentEma = p.spentEma or 0,
      earnedCoin = p.earnedCoin or 0, earnedEma = p.earnedEma or 0,
      visits = p.visits or 0, purchases = p.purchases or 0, sells = p.sells or 0,
    }
  end
  table.sort(list, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.name < b.name
  end)
  topCache[category] = list
  return list
end

-- ============================================================
-- ИГРОКИ / СДЕЛКИ
-- ============================================================
local function getOrCreatePlayer(name)
  local p = players[name]
  if not p then
    p = {
      balance = 0, emaBalance = 0, transactions = 0, regDate = timeStr(),
      agreed = false, banned = false, banInfo = nil, banUntil = nil,
      visits = 0, purchases = 0, sells = 0,
      spentCoin = 0, spentEma = 0, earnedCoin = 0, earnedEma = 0,
      lastVisit = "", lastVisitTime = 0,
    }
    players[name] = p
    markDirty(DB_PATH); invalidateTops()
  end
  return p
end
local function addTransaction(name, kind, item, qty, coin, ema)
  transactions[#transactions + 1] = { time = timeStr(), player = name, kind = kind, item = item, qty = qty, coin = coin, ema = ema }
  while #transactions > 500 do table.remove(transactions, 1) end
  markDirty(TX_PATH)
end
local function checkBanExpiry(p, name)
  if p.banned and p.banUntil and os.time() >= (tonumber(p.banUntil) or 0) then
    p.banned = false; p.banInfo = nil; p.banUntil = nil
    markDirty(DB_PATH); logLine("BAN auto-unban " .. name)
    return true
  end
  return false
end

-- ============================================================
-- СЕТЬ: ОТВЕТ ТЕРМИНАЛАМ
-- ============================================================
local function send(addr, msg) modem.send(addr, 0xffef, serialization.serialize(msg)) end
local dirty = true
local toasts = {}
local function setToast(text, color, secs)
  toasts[#toasts + 1] = { text = text, color = color or C.white, untilU = computer.uptime() + (secs or 3) }
  dirty = true
end
local function handleModem(addr, msg)
  if type(msg) ~= "table" or not msg.op then return end
  if msg.op == "register" then
    if msg.password == ACCESS_PASSWORD then send(addr, { op = "register_ok" }) end
  elseif msg.op == "enter" then
    local name = trim(msg.name)
    if name == "" then return end
    if config.paused then send(addr, { op = "error", message = "Магазин на паузе: тех. работы" }); return end
    local p = getOrCreatePlayer(name)
    checkBanExpiry(p, name)
    if p.banned then send(addr, { op = "error", message = "Вы забанены", banInfo = p.banInfo }); return end
    local t = os.time()
    if t - (p.lastVisitTime or 0) >= VISIT_COOLDOWN then
      p.visits = (p.visits or 0) + 1
      p.lastVisitTime = t; p.lastVisit = timeStr()
      markDirty(DB_PATH); invalidateTops()
    end
    local token = makeToken(name)
    send(addr, {
      op = "welcome", token = token,
      balance = p.balance or 0, emaBalance = p.emaBalance or 0,
      transactions = p.transactions or 0, regDate = p.regDate or "",
      agreed = p.agreed or false, banned = p.banned or false, banInfo = p.banInfo,
    })
  elseif msg.op == "getAccount" then
    local name = sessionName(msg.token)
    if not name then send(addr, { op = "accountData", error = true }); return end
    local p = players[name]
    send(addr, { op = "accountData", data = {
      name = name, balance = p.balance, emaBalance = p.emaBalance,
      transactions = p.transactions, regDate = p.regDate,
      agreed = p.agreed, banned = p.banned, banInfo = p.banInfo,
    }})
  elseif msg.op == "agree" then
    local name = sessionName(msg.token)
    if not name then send(addr, { op = "agree", error = true, message = "Токен устарел" }); return end
    local p = players[name]; p.agreed = true
    markDirty(DB_PATH)
    send(addr, { op = "agree", success = true })
  elseif msg.op == "buy" then
    local name = sessionName(msg.token)
    if not name then send(addr, { op = "error", message = "Токен устарел" }); return end
    local p = players[name]; if not p then return end
    local vc = tonumber(msg.value_coin) or 0; local ve = tonumber(msg.value_ema) or 0
    if (p.balance or 0) < vc or (p.emaBalance or 0) < ve then
      send(addr, { op = "error", message = "Недостаточно средств" }); return
    end
    p.balance = (p.balance or 0) - vc
    p.emaBalance = (p.emaBalance or 0) - ve
    p.transactions = (p.transactions or 0) + 1
    p.purchases = (p.purchases or 0) + 1
    p.spentCoin = (p.spentCoin or 0) + vc
    p.spentEma = (p.spentEma or 0) + ve
    markDirty(DB_PATH); invalidateTops()
    addTransaction(name, "buy", msg.item or "?", tonumber(msg.qty) or 0, vc, ve)
    logLine("BUY " .. name .. " " .. tostring(msg.item) .. " x" .. tostring(msg.qty))
    send(addr, { op = "buy_ok", balance = p.balance, emaBalance = p.emaBalance })
  elseif msg.op == "sell" then
    local name = sessionName(msg.token)
    if not name then send(addr, { op = "error", message = "Токен устарел" }); return end
    local p = players[name]; if not p then return end
    local v = tonumber(msg.value) or 0
    local isEma = (msg.internalName == "customnpcs:npcMoney")
    if isEma then p.emaBalance = (p.emaBalance or 0) + v; p.earnedEma = (p.earnedEma or 0) + v
    else p.balance = (p.balance or 0) + v; p.earnedCoin = (p.earnedCoin or 0) + v end
    p.transactions = (p.transactions or 0) + 1
    p.sells = (p.sells or 0) + 1
    markDirty(DB_PATH); invalidateTops()
    addTransaction(name, "sell", msg.item or "?", tonumber(msg.qty) or 0, isEma and 0 or v, isEma and v or 0)
    logLine("SELL " .. name .. " " .. tostring(msg.item) .. " x" .. tostring(msg.qty))
    send(addr, { op = "sell_ok", balance = p.balance, emaBalance = p.emaBalance })
  elseif msg.op == "get_top" then
    local cat = msg.category or "balance"
    local per = math.max(1, math.min(100, tonumber(msg.perPage) or 10))
    local page = math.max(1, tonumber(msg.page) or 1)
    local list = buildTop(cat)
    local total = #list
    local pages = math.max(1, math.ceil(total / per))
    if page > pages then page = pages end
    local slice = {}
    for i = (page - 1) * per + 1, math.min(page * per, total) do slice[#slice + 1] = list[i] end
    send(addr, { op = "top_data", list = slice, totalPages = pages, total = total, category = cat, page = page })
  elseif msg.op == "get_feedbacks" then
    local name = sessionName(msg.token) or msg.name
    local has = false
    for _, fb in ipairs(feedbacks) do if fb.name == name then has = true; break end end
    send(addr, { op = "feedbacks_list", feedbacks = feedbacks, hasFeedback = has })
  elseif msg.op == "add_feedback" then
    local name = sessionName(msg.token)
    if not name then send(addr, { op = "add_feedback_response", success = false, error = "Токен устарел" }); return end
    for _, fb in ipairs(feedbacks) do
      if fb.name == name then send(addr, { op = "add_feedback_response", success = false, error = "Уже есть отзыв" }); return end
    end
    feedbacks[#feedbacks + 1] = { name = name, text = tostring(msg.text or ""):sub(1, 200), rating = tonumber(msg.rating) or 0, time = msg.time or timeStr() }
    markDirty(FB_PATH)
    setToast("Новый отзыв: " .. name, C.green, 3)
    send(addr, { op = "add_feedback_response", success = true })
  elseif msg.op == "report" then
    local name = sessionName(msg.token) or "?"
    reports[#reports + 1] = { time = msg.time or timeStr(), player = name, text = tostring(msg.text or ""):sub(1, 300) }
    markDirty(REP_PATH)
    setToast("Репорт от " .. name, C.yellow, 4)
    logLine("REPORT " .. name .. ": " .. tostring(msg.text))
    send(addr, { op = "report_ok" })
  elseif msg.op == "scan_report" or msg.op == "selector_status" or msg.op == "update_stats" then
    -- служебные: игнорируем (сервер сам источник статистики)
  end
end

-- ============================================================
-- GUI: БАЗА
-- ============================================================
local currentScreen = "login"
local serverSession = { player = nil, authed = false }
local hitboxes = {}
local function resetHitboxes() hitboxes = {} end
local function addHitbox(id, x, y, w, h, data) hitboxes[#hitboxes + 1] = { id = id, x = x, y = y, w = w, h = h, data = data } end
local function hitAt(x, y)
  for i = #hitboxes, 1, -1 do
    local b = hitboxes[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b end
  end
  return nil
end
local function clearScreen(bg) gpu.setBackground(bg or C.bg); gpu.fill(1, 1, screenW, screenH, " ") end
local function writeText(x, y, text, fg, bg) if bg then gpu.setBackground(bg) end gpu.setForeground(fg or C.text); gpu.set(x, y, text) end
local function fillRect(x, y, w, h, bg) gpu.setBackground(bg); gpu.fill(x, y, w, h, " ") end
local function drawHeader(title)
  fillRect(1, 1, screenW, 1, C.panel)
  writeText(2, 1, "◈ PC SHOP SERVER ◈", C.accent, C.panel)
  local t = title or ""
  writeText(math.floor((screenW - unicode.len(t)) / 2) + 1, 1, t, C.white, C.panel)
  writeText(screenW - 20, 1, os.date("%H:%M:%S"), C.muted, C.panel)
end
local function drawFooter(hint)
  fillRect(1, screenH, screenW, 1, C.panel)
  writeText(2, screenH, hint or "", C.muted, C.panel)
  if serverSession.authed then writeText(screenW - 22, screenH, "админ: " .. serverSession.player, C.accent, C.panel) end
end
local function drawBox(x, y, w, h, title, color, bg)
  fillRect(x, y, w, h, bg or C.panel)
  gpu.setForeground(color or C.border)
  gpu.fill(x, y, w, 1, "─"); gpu.fill(x, y + h - 1, w, 1, "─")
  for i = 1, h - 2 do gpu.set(x, y + i, "│"); gpu.set(x + w - 1, y + i, "│") end
  gpu.set(x, y, "┌"); gpu.set(x + w - 1, y, "┐"); gpu.set(x, y + h - 1, "└"); gpu.set(x + w - 1, y + h - 1, "┘")
  if title and title ~= "" then writeText(x + 2, y, " " .. title .. " ", color or C.border, bg or C.panel) end
end
local function drawButton(id, x, y, w, text, bg, fg, data)
  addHitbox(id, x, y, w, 1, data)
  fillRect(x, y, w, 1, bg or C.button)
  writeText(x + math.floor((w - unicode.len(text)) / 2), y, text, fg or C.white, bg or C.button)
end
local function drawToasts()
  local y = 2
  for i = #toasts, 1, -1 do
    local t = toasts[i]
    if computer.uptime() > t.untilU then table.remove(toasts, i); dirty = true
    else
      local w = math.min(screenW - 4, unicode.len(t.text) + 4)
      fillRect(screenW - w - 1, y, w, 1, C.panel2)
      writeText(screenW - w, y, clip(t.text, w - 2), t.color, C.panel2)
      y = y + 1
    end
  end
end
local function isAdmin(nick) return nick == OWNER or admins[nick] ~= nil end
local function isOwner() return serverSession.player == OWNER end
local function sortedPlayers()
  local list = {}
  for name in pairs(players) do list[#list + 1] = name end
  table.sort(list, function(a, b) return unicode.lower(a) < unicode.lower(b) end)
  return list
end
local function filteredPlayers(search)
  local all = sortedPlayers()
  local s = unicode.lower(trim(search))
  if s == "" then return all end
  local res = {}
  for _, n in ipairs(all) do if unicode.lower(n):find(s, 1, true) then res[#res + 1] = n end end
  return res
end

-- ============================================================
-- GUI: ЭКРАНЫ
-- ============================================================
local loginNick, loginPass = "", ""
local loginField = 1
local playersScroll, playersSearch = 1, ""
local txScroll, fbScroll, repScroll = 1, 1, 1
local editingPlayerName = nil
local editCoinInput, editEmaInput = "", ""
local banReasonInput, banDurationInput, banField = "", "навсегда", 1
local adminNickInput, adminPassInput, adminField = "", "", 1

local function drawLogin()
  currentScreen = "login"
  resetHitboxes(); clearScreen()
  local w, h = 46, 11
  local x = math.floor((screenW - w) / 2) + 1
  local y = math.floor((screenH - h) / 2)
  drawBox(x, y, w, h, "ВХОД В АДМИН-ПАНЕЛЬ", C.accent, C.panel)
  writeText(x + 3, y + 2, "Ник:", C.text, C.panel)
  local bg1 = loginField == 1 and C.sel or C.input
  fillRect(x + 3, y + 3, w - 6, 1, bg1)
  writeText(x + 4, y + 3, clip(loginNick .. (loginField == 1 and "█" or ""), w - 8), C.white, bg1)
  addHitbox("field_login_nick", x + 3, y + 2, w - 6, 2, 1)
  writeText(x + 3, y + 5, "Пароль:", C.text, C.panel)
  local bg2 = loginField == 2 and C.sel or C.input
  fillRect(x + 3, y + 6, w - 6, 1, bg2)
  writeText(x + 4, y + 6, clip(string.rep("*", unicode.len(loginPass)) .. (loginField == 2 and "█" or ""), w - 8), C.white, bg2)
  addHitbox("field_login_pass", x + 3, y + 5, w - 6, 2, 2)
  drawButton("login_submit", x + 3, y + 8, w - 6, "ВОЙТИ", C.sel, C.white)
  drawFooter("Tab - поле | Enter - вход | владелец: " .. OWNER)
end

local function drawDashboard()
  currentScreen = "dashboard"
  resetHitboxes(); clearScreen()
  drawHeader("ЭКОНОМИКА")
  local totalCoin, totalEma, totalTx = 0, 0, 0
  for _, p in pairs(players) do
    totalCoin = totalCoin + (p.balance or 0)
    totalEma = totalEma + (p.emaBalance or 0)
    totalTx = totalTx + (p.transactions or 0)
  end
  local nPlayers = 0; for _ in pairs(players) do nPlayers = nPlayers + 1 end
  local x, y = 2, 3
  local w = math.floor((screenW - 6) / 2)
  drawBox(x, y, w, 9, "ПОКАЗАТЕЛИ", C.border, C.panel)
  writeText(x + 2, y + 2, "Игроков:        " .. nPlayers, C.white, C.panel)
  writeText(x + 2, y + 3, "Монет в экономике: ", C.white, C.panel)
  writeText(x + 20, y + 3, string.format("%.2f", totalCoin) .. " ☄", C.coin, C.panel)
  writeText(x + 2, y + 4, "Эм в экономике:   ", C.white, C.panel)
  writeText(x + 20, y + 4, string.format("%.2f", totalEma) .. " ⛭", C.ema, C.panel)
  writeText(x + 2, y + 5, "Всего транзакций: " .. totalTx, C.white, C.panel)
  writeText(x + 2, y + 6, "Сделок в журнале:  " .. #transactions, C.white, C.panel)
  writeText(x + 2, y + 7, (config.paused and "Магазин: ПАУЗА" or "Магазин: работает"), config.paused and C.red or C.green, C.panel)
  local x2 = x + w + 2
  drawBox(x2, y, screenW - x2 - 1, 9, "ТОП-3 БАЛАНС", C.border, C.panel)
  local topB = buildTop("balance")
  for i = 1, math.min(3, #topB) do
    local e = topB[i]
    writeText(x2 + 2, y + 1 + i * 2, (i .. ". " .. clip(e.name, 14)), C.white, C.panel)
    writeText(x2 + 2, y + 2 + i * 2, string.format("%.1f ☄ / %.1f ⛭", e.coin, e.ema), C.muted, C.panel)
  end
  local by = y + 11
  local bw = math.floor((screenW - 8) / 4)
  drawButton("nav_players", 2, by, bw, "ИГРОКИ", C.button, C.white)
  drawButton("nav_tx", 3 + bw, by, bw, "СДЕЛКИ", C.button, C.white)
  drawButton("nav_fb", 4 + bw * 2, by, bw, "ОТЗЫВЫ", C.button, C.white)
  drawButton("nav_rep", 5 + bw * 3, by, bw, "РЕПОРТЫ", C.button, C.white)
  drawButton("nav_admins", 2, by + 2, bw, "АДМИНЫ", C.button, C.white)
  drawButton("nav_settings", 3 + bw, by + 2, bw, "НАСТРОЙКИ", C.button, C.white)
  drawButton("pause_toggle", 4 + bw * 2, by + 2, bw, config.paused and "СНЯТЬ ПАУЗУ" or "ПАУЗА", config.paused and C.green or C.red, C.white)
  drawButton("logout", 5 + bw * 3, by + 2, bw, "ВЫХОД", C.button, C.red)
  drawFooter("мышь - разделы | топ и баланс хранятся на этом ПК")
end

local function drawPlayers()
  currentScreen = "players"
  resetHitboxes(); clearScreen()
  drawHeader("ИГРОКИ")
  local list = filteredPlayers(playersSearch)
  local sx, sw = 2, math.min(30, screenW - 30)
  fillRect(sx, 3, sw, 1, C.input)
  writeText(sx + 1, 3, clip(playersSearch == "" and "поиск ника..." or playersSearch, sw - 2), playersSearch == "" and C.muted or C.white, C.input)
  addHitbox("players_search", sx, 3, sw, 1)
  writeText(sx + sw + 2, 3, "найдено: " .. #list, C.muted)
  local rowY, rows = 5, math.max(4, screenH - 9)
  if #list == 0 then
    writeText(sx, rowY + 1, "Игроков не найдено", C.muted)
  end
  for i = 1, rows do
    local idx = playersScroll + i - 1
    local name = list[idx]
    if not name then break end
    local p = players[name]
    local bg = (i % 2 == 0) and C.panel or C.panel2
    fillRect(sx, rowY, screenW - sx - 1, 1, bg)
    addHitbox("select_player", sx, rowY, screenW - sx - 1, 1, name)
    writeText(sx + 1, rowY, clip(name, 18), p.banned and C.red or C.white, bg)
    writeText(sx + 21, rowY, string.format("%.1f ☄", p.balance or 0), C.coin, bg)
    writeText(sx + 34, rowY, string.format("%.1f ⛭", p.emaBalance or 0), C.ema, bg)
    writeText(sx + 47, rowY, "виз:" .. (p.visits or 0), C.muted, bg)
    writeText(screenW - 12, rowY, p.banned and "БАН" or (p.agreed and "ок" or "нет"), p.banned and C.red or (p.agreed and C.green or C.yellow), bg)
    rowY = rowY + 1
  end
  if #list > rows then
    local barH = rows; local thumb = math.max(1, math.floor(barH * rows / #list))
    local pos = math.floor((playersScroll - 1) * (barH - thumb) / math.max(1, #list - rows)) + 1
    fillRect(screenW - 2, 5, 1, barH, C.panel2)
    fillRect(screenW - 2, 5 + pos - 1, 1, thumb, C.accent)
  end
  drawButton("back", 2, screenH - 2, 14, "< НАЗАД", C.button, C.white)
  drawFooter("клик по строке - карточка | колёсико - список | печать - поиск")
end

local function drawPlayerEditor()
  currentScreen = "editor"
  resetHitboxes(); clearScreen()
  local p = players[editingPlayerName]
  if not p then drawPlayers(); return end
  drawHeader("КАРТОЧКА: " .. editingPlayerName)
  local w = math.min(76, screenW - 6)
  local x = math.floor((screenW - w) / 2) + 1
  local y = 3
  drawBox(x, y, w, 16, "ИНФОРМАЦИЯ", C.border, C.panel)
  writeText(x + 2, y + 2, "Регистрация: " .. (p.regDate or "-"), C.muted, C.panel)
  writeText(x + 2, y + 3, "Последний визит: " .. (p.lastVisit or "-"), C.muted, C.panel)
  writeText(x + 2, y + 5, "Баланс: ", C.text, C.panel)
  writeText(x + 12, y + 5, string.format("%.2f ☄", p.balance or 0), C.coin, C.panel)
  writeText(x + 28, y + 5, string.format("%.2f ⛭", p.emaBalance or 0), C.ema, C.panel)
  writeText(x + 2, y + 6, "Визиты: " .. (p.visits or 0) .. "  Покупки: " .. (p.purchases or 0) .. "  Продажи: " .. (p.sells or 0), C.white, C.panel)
  writeText(x + 2, y + 7, "Потрачено: " .. string.format("%.1f ☄ / %.1f ⛭", p.spentCoin or 0, p.spentEma or 0), C.white, C.panel)
  writeText(x + 2, y + 8, "Заработано: " .. string.format("%.1f ☄ / %.1f ⛭", p.earnedCoin or 0, p.earnedEma or 0), C.white, C.panel)
  writeText(x + 2, y + 9, p.banned and ("БАН: " .. (p.banInfo and p.banInfo.duration or "?") .. " | админ: " .. (p.banInfo and p.banInfo.admin or "?")) or "Не забанен", p.banned and C.red or C.green, C.panel)
  -- поля правки баланса
  writeText(x + 2, y + 11, "Новый баланс ☄:", C.text, C.panel)
  fillRect(x + 18, y + 11, 14, 1, C.input)
  writeText(x + 19, y + 11, clip(editCoinInput .. "_", 12), C.coin, C.input)
  addHitbox("edit_field_coin", x + 18, y + 11, 14, 1)
  writeText(x + 36, y + 11, "Новый баланс ⛭:", C.text, C.panel)
  fillRect(x + 52, y + 11, 14, 1, C.input)
  writeText(x + 53, y + 11, clip(editEmaInput .. "_", 12), C.ema, C.input)
  addHitbox("edit_field_ema", x + 52, y + 11, 14, 1)
  local bw = math.floor((w - 8) / 3)
  drawButton("edit_save_bal", x + 2, y + 13, bw, "СОХР. БАЛАНС", C.sel, C.white)
  drawButton("edit_toggle_agree", x + 4 + bw, y + 13, bw, p.agreed and "СОГЛ: ДА" or "СОГЛ: НЕТ", C.button, C.white)
  drawButton("edit_reset", x + 6 + bw * 2, y + 13, bw, "СБРОС СТАТОВ", C.button, C.yellow)
  drawButton("edit_ban", x + 2, y + 15, bw, "ЗАБАНИТЬ", C.red, C.white)
  drawButton("edit_unban", x + 4 + bw, y + 15, bw, "РАЗБАНИТЬ", C.green, C.white)
  drawButton("back", x + 6 + bw * 2, y + 15, bw, "< НАЗАД", C.button, C.white)
  drawFooter("цифры/точка - ввод баланса | Enter - сохранить баланс")
end

local function drawBanEditor()
  currentScreen = "edit_ban"
  resetHitboxes(); clearScreen()
  local w = math.min(76, screenW - 6)
  local h = 15
  local x = math.floor((screenW - w) / 2) + 1
  local y = math.max(4, math.floor((screenH - h) / 2))
  drawBox(x, y, w, h, "БАН: " .. tostring(editingPlayerName), C.red, C.panel)
  writeText(x + 3, y + 2, "Причина наказания:", C.red, C.panel)
  local bg1 = banField == 1 and C.sel or C.input
  fillRect(x + 3, y + 3, w - 6, 1, bg1)
  writeText(x + 4, y + 3, clip(banReasonInput .. (banField == 1 and "█" or ""), w - 8), C.white, bg1)
  addHitbox("ban_field", x + 3, y + 2, w - 6, 2, 1)
  writeText(x + 3, y + 5, "Срок (число = минуты, или текстом):", C.yellow, C.panel)
  local bg2 = banField == 2 and C.sel or C.input
  fillRect(x + 3, y + 6, w - 6, 1, bg2)
  writeText(x + 4, y + 6, clip(banDurationInput .. (banField == 2 and "█" or ""), w - 8), C.white, bg2)
  addHitbox("ban_field", x + 3, y + 5, w - 6, 2, 2)
  writeText(x + 3, y + 8, "Примеры: навсегда | 60 | 1440 | 7 дней", C.muted, C.panel)
  writeText(x + 3, y + 9, "Администратор: " .. tostring(serverSession.player), C.muted, C.panel)
  local bw = math.floor((w - 8) / 2)
  drawButton("ban_save", x + 3, y + h - 3, bw, "ЗАБЛОКИРОВАТЬ", C.red, C.white)
  drawButton("ban_cancel", x + 5 + bw, y + h - 3, bw, "ОТМЕНА", C.button, C.white)
  drawFooter("Tab - поле | Enter - забанить | Esc - отмена")
end

local function drawTransactions()
  currentScreen = "tx"
  resetHitboxes(); clearScreen()
  drawHeader("ЖУРНАЛ СДЕЛОК")
  local rows = math.max(4, screenH - 7)
  local y = 4
  fillRect(2, y, screenW - 4, 1, C.panel2)
  writeText(3, y, "Время", C.muted, C.panel2)
  writeText(23, y, "Игрок", C.muted, C.panel2)
  writeText(41, y, "Тип", C.muted, C.panel2)
  writeText(48, y, "Предмет", C.muted, C.panel2)
  writeText(screenW - 26, y, "Сумма", C.muted, C.panel2)
  y = y + 1
  for i = 1, rows do
    local idx = #transactions - txScroll - i + 1
    local t = transactions[idx]
    if not t then break end
    local bg = (i % 2 == 0) and C.panel or C.panel2
    fillRect(2, y, screenW - 4, 1, bg)
    writeText(3, y, clip(t.time or "", 18), C.muted, bg)
    writeText(23, y, clip(t.player or "?", 16), C.white, bg)
    writeText(41, y, t.kind == "buy" and "куп" or "прод", t.kind == "buy" and C.coin or C.green, bg)
    writeText(48, y, clip(t.item or "?", screenW - 76), C.text, bg)
    local sum = string.format("%.1f☄ %.1f⛭", t.coin or 0, t.ema or 0)
    writeText(screenW - 26, y, sum, C.white, bg)
    y = y + 1
  end
  drawButton("back", 2, screenH - 2, 14, "< НАЗАД", C.button, C.white)
  drawFooter("колёсико - прокрутка журнала (новые сверху)")
end

local function drawFeedbacks()
  currentScreen = "fb"
  resetHitboxes(); clearScreen()
  drawHeader("ОТЗЫВЫ ИГРОКОВ")
  local rows = math.max(3, screenH - 8)
  local y = 4
  for i = 1, rows do
    local idx = fbScroll + i - 1
    local fb = feedbacks[idx]
    if not fb then break end
    local bg = (i % 2 == 0) and C.panel or C.panel2
    fillRect(2, y, screenW - 4, 2, bg)
    local stars = ""
    for s = 1, 5 do stars = stars .. ((fb.rating or 0) >= s and "★" or "☆") end
    writeText(3, y, clip(fb.name or "?", 16), C.accent, bg)
    writeText(21, y, stars, C.gold, bg)
    writeText(29, y, clip(fb.time or "", 19), C.muted, bg)
    writeText(3, y + 1, clip(fb.text or "", screenW - 12), C.white, bg)
    addHitbox("fb_delete", screenW - 8, y, 6, 2, idx)
    writeText(screenW - 8, y, "[del]", C.red, bg)
    y = y + 3
  end
  drawButton("back", 2, screenH - 2, 14, "< НАЗАД", C.button, C.white)
  drawFooter("колёсико - прокрутка | [del] - удалить отзыв")
end

local function drawReports()
  currentScreen = "rep"
  resetHitboxes(); clearScreen()
  drawHeader("РЕПОРТЫ ИГРОКОВ")
  local rows = math.max(3, screenH - 8)
  local y = 4
  for i = 1, rows do
    local idx = #reports - repScroll - i + 1
    local r = reports[idx]
    if not r then break end
    local bg = (i % 2 == 0) and C.panel or C.panel2
    fillRect(2, y, screenW - 4, 2, bg)
    writeText(3, y, clip(r.player or "?", 16), C.yellow, bg)
    writeText(21, y, clip(r.time or "", 19), C.muted, bg)
    writeText(3, y + 1, clip(r.text or "", screenW - 6), C.white, bg)
    y = y + 3
  end
  drawButton("back", 2, screenH - 2, 14, "< НАЗАД", C.button, C.white)
  drawFooter("колёсико - прокрутка (новые сверху)")
end

local function drawAdmins()
  currentScreen = "admins"
  resetHitboxes(); clearScreen()
  drawHeader("АДМИНИСТРАТОРЫ")
  local y = 4
  writeText(3, y, "Ник", C.muted); writeText(25, y, "Роль", C.muted); writeText(45, y, "Действие", C.muted)
  y = y + 1
  local list = sortedAdminsList()
  for i, nick in ipairs(list) do
    local bg = (i % 2 == 0) and C.panel or C.panel2
    fillRect(2, y, screenW - 4, 1, bg)
    writeText(3, y, clip(nick, 20), nick == OWNER and C.gold or C.white, bg)
    writeText(25, y, nick == OWNER and "владелец" or "админ", nick == OWNER and C.gold or C.accent, bg)
    if nick ~= OWNER and isOwner() then
      addHitbox("admin_delete", 45, y, 12, 1, nick)
      writeText(45, y, "[удалить]", C.red, bg)
    end
    y = y + 1
  end
  if isOwner() then
    local w = math.min(70, screenW - 6)
    local x = math.floor((screenW - w) / 2) + 1
    local by = math.min(screenH - 7, y + 2)
    drawBox(x, by, w, 5, "НОВЫЙ АДМИН", C.green, C.panel)
    local bg1 = adminField == 1 and C.sel or C.input
    fillRect(x + 2, by + 2, 24, 1, bg1)
    writeText(x + 3, by + 2, clip(adminNickInput .. (adminField == 1 and "█" or ""), 22), C.white, bg1)
    addHitbox("admin_field", x + 2, by + 2, 24, 1, 1)
    local bg2 = adminField == 2 and C.sel or C.input
    fillRect(x + 28, by + 2, 20, 1, bg2)
    writeText(x + 29, by + 2, clip(adminPassInput .. (adminField == 2 and "█" or ""), 18), C.white, bg2)
    addHitbox("admin_field", x + 28, by + 2, 20, 1, 2)
    drawButton("admin_add", x + 50, by + 2, 16, "ДОБАВИТЬ", C.green, C.white)
  end
  drawButton("back", 2, screenH - 2, 14, "< НАЗАД", C.button, C.white)
  drawFooter("добавлять/удалять может только владелец")
end
function sortedAdminsList()
  local list = {}
  for nick in pairs(admins) do list[#list + 1] = nick end
  table.sort(list)
  return list
end

local function drawSettings()
  currentScreen = "settings"
  resetHitboxes(); clearScreen()
  drawHeader("НАСТРОЙКИ СЕРВЕРА")
  local w = math.min(70, screenW - 6)
  local x = math.floor((screenW - w) / 2) + 1
  local y = 4
  drawBox(x, y, w, 12, "ПАРАМЕТРЫ", C.border, C.panel)
  writeText(x + 2, y + 2, "Пауза магазина: " .. (config.paused and "ВКЛ" or "ВЫКЛ"), config.paused and C.red or C.green, C.panel)
  writeText(x + 2, y + 3, "Автосохранение: каждые " .. SAVE_INTERVAL .. " сек", C.muted, C.panel)
  writeText(x + 2, y + 4, "Файлы: shop_db / transactions / feedbacks / reports", C.muted, C.panel)
  drawButton("pause_toggle", x + 2, y + 6, 24, config.paused and "СНЯТЬ ПАУЗУ" or "ПАУЗА МАГАЗИНА", config.paused and C.green or C.red, C.white)
  drawButton("save_now", x + 28, y + 6, 24, "СОХРАНИТЬ СЕЙЧАС", C.sel, C.white)
  drawButton("clear_tx", x + 2, y + 8, 24, "ОЧИСТИТЬ ЖУРНАЛ", C.button, C.yellow)
  drawButton("back", x + 28, y + 8, 24, "< НАЗАД", C.button, C.white)
  drawFooter("топы и балансы живут в /home/shop_db.json")
end

local function redraw()
  if currentScreen == "login" then drawLogin()
  elseif currentScreen == "dashboard" then drawDashboard()
  elseif currentScreen == "players" then drawPlayers()
  elseif currentScreen == "editor" then drawPlayerEditor()
  elseif currentScreen == "edit_ban" then drawBanEditor()
  elseif currentScreen == "tx" then drawTransactions()
  elseif currentScreen == "fb" then drawFeedbacks()
  elseif currentScreen == "rep" then drawReports()
  elseif currentScreen == "admins" then drawAdmins()
  elseif currentScreen == "settings" then drawSettings()
  else drawLogin() end
  drawToasts()
end

-- ============================================================
-- ДЕЙСТВИЯ GUI
-- ============================================================
local function processAction(id, data)
  if currentScreen == "login" then
    if id == "field_login_nick" then loginField = 1; dirty = true; return end
    if id == "field_login_pass" then loginField = 2; dirty = true; return end
    if id == "login_submit" then
      local nick = trim(loginNick)
      if isAdmin(nick) and admins[nick] == loginPass then
        serverSession.player = nick; serverSession.authed = true
        currentScreen = "dashboard"; logLine("ADMIN login " .. nick)
        setToast("Добро пожаловать, " .. nick, C.green, 3)
      else
        setToast("Неверный ник или пароль", C.red, 3)
      end
      dirty = true; return
    end
  end
  if not serverSession.authed then return end
  if id == "logout" then serverSession.authed = false; serverSession.player = nil; loginPass = ""; currentScreen = "login"; dirty = true; return end
  if id == "back" then
    if currentScreen == "editor" or currentScreen == "edit_ban" then currentScreen = "players"
    else currentScreen = "dashboard" end
    dirty = true; return
  end
  if id == "nav_players" then currentScreen = "players"; dirty = true; return end
  if id == "nav_tx" then currentScreen = "tx"; txScroll = 0; dirty = true; return end
  if id == "nav_fb" then currentScreen = "fb"; fbScroll = 1; dirty = true; return end
  if id == "nav_rep" then currentScreen = "rep"; repScroll = 0; dirty = true; return end
  if id == "nav_admins" then currentScreen = "admins"; dirty = true; return end
  if id == "nav_settings" then currentScreen = "settings"; dirty = true; return end
  if id == "pause_toggle" then
    config.paused = not config.paused
    markDirty(CFG_PATH)
    setToast(config.paused and "Магазин на ПАУЗЕ" or "Магазин работает", config.paused and C.red or C.green, 3)
    logLine("PAUSE " .. tostring(config.paused))
    dirty = true; return
  end
  if id == "save_now" then flushSaves(true); setToast("Сохранено", C.green, 2); dirty = true; return end
  if id == "clear_tx" then if isOwner() then transactions = {}; markDirty(TX_PATH); setToast("Журнал очищен", C.yellow, 2) end dirty = true; return end
  if id == "players_search" then dirty = true; return end
  if id == "select_player" then
    editingPlayerName = data
    local p = players[data]
    editCoinInput = string.format("%.2f", p and p.balance or 0)
    editEmaInput = string.format("%.2f", p and p.emaBalance or 0)
    currentScreen = "editor"; dirty = true; return
  end
  if id == "edit_field_coin" or id == "edit_field_ema" then dirty = true; return end
  if id == "edit_save_bal" then
    local p = players[editingPlayerName]
    if p then
      p.balance = tonumber(editCoinInput) or p.balance
      p.emaBalance = tonumber(editEmaInput) or p.emaBalance
      markDirty(DB_PATH); invalidateTops()
      setToast("Баланс обновлён", C.green, 2)
      logLine("ADMIN set balance " .. editingPlayerName .. " " .. tostring(p.balance) .. "/" .. tostring(p.emaBalance))
    end
    dirty = true; return
  end
  if id == "edit_toggle_agree" then
    local p = players[editingPlayerName]
    if p then p.agreed = not p.agreed; markDirty(DB_PATH); setToast("Соглашение: " .. tostring(p.agreed), C.yellow, 2) end
    dirty = true; return
  end
  if id == "edit_reset" then
    local p = players[editingPlayerName]
    if p then
      p.visits = 0; p.purchases = 0; p.sells = 0
      p.spentCoin = 0; p.spentEma = 0; p.earnedCoin = 0; p.earnedEma = 0
      markDirty(DB_PATH); invalidateTops(); setToast("Статистика сброшена", C.yellow, 2)
    end
    dirty = true; return
  end
  if id == "edit_ban" then
    banReasonInput = ""; banDurationInput = "навсегда"; banField = 1
    currentScreen = "edit_ban"; dirty = true; return
  end
  if id == "edit_unban" then
    local p = players[editingPlayerName]
    if p then p.banned = false; p.banInfo = nil; p.banUntil = nil; markDirty(DB_PATH)
      setToast("Разбанен: " .. editingPlayerName, C.green, 3); logLine("BAN unban " .. editingPlayerName) end
    dirty = true; return
  end
  if id == "ban_field" then banField = tonumber(data) or banField; dirty = true; return end
  if id == "ban_cancel" then currentScreen = "editor"; dirty = true; return end
  if id == "ban_save" then
    local p = players[editingPlayerName]
    if p then
      local reason = trim(banReasonInput); if reason == "" then reason = "Можно спросить у Администрации" end
      local durRaw = trim(banDurationInput); if durRaw == "" then durRaw = "навсегда" end
      local banUntil, display = nil, durRaw
      local mins = tonumber(durRaw)
      if mins then
        banUntil = os.time() + math.floor(mins * 60)
        display = math.floor(mins) .. " мин (до " .. os.date("%d.%m.%Y %H:%M", banUntil) .. ")"
      end
      p.banned = true
      p.banUntil = banUntil
      p.banInfo = { admin = tostring(serverSession.player), date = timeStr(), reason = reason, duration = display }
      markDirty(DB_PATH)
      setToast("Забанен: " .. editingPlayerName, C.red, 3)
      logLine("BAN " .. editingPlayerName .. " by " .. tostring(serverSession.player) .. " | " .. reason .. " | " .. display)
      currentScreen = "editor"
    end
    dirty = true; return
  end
  if id == "admin_field" then adminField = tonumber(data) or adminField; dirty = true; return end
  if id == "admin_add" then
    if not isOwner() then setToast("Только владелец", C.red, 2); dirty = true; return end
    local nick = trim(adminNickInput)
    if nick == "" or trim(adminPassInput) == "" then setToast("Заполни ник и пароль", C.red, 2); dirty = true; return end
    if isAdmin(nick) then setToast("Уже администратор", C.red, 2); dirty = true; return end
    admins[nick] = trim(adminPassInput)
    markDirty(ADM_PATH)
    adminNickInput = ""; adminPassInput = ""
    setToast("Админ добавлен: " .. nick, C.green, 3)
    logLine("ADMIN add " .. nick .. " by " .. tostring(serverSession.player))
    dirty = true; return
  end
  if id == "admin_delete" then
    if not isOwner() then setToast("Только владелец", C.red, 2); dirty = true; return end
    if data and admins[data] and data ~= OWNER then
      admins[data] = nil; markDirty(ADM_PATH)
      setToast("Админ удалён: " .. data, C.yellow, 3)
      logLine("ADMIN delete " .. data)
    end
    dirty = true; return
  end
  if id == "fb_delete" then
    local idx = tonumber(data)
    if idx and feedbacks[idx] then
      local name = feedbacks[idx].name
      table.remove(feedbacks, idx)
      markDirty(FB_PATH)
      setToast("Отзыв удалён: " .. tostring(name), C.yellow, 2)
    end
    dirty = true; return
  end
end

-- ============================================================
-- КЛАВИАТУРА / СКРОЛЛ
-- ============================================================
local function handleKey(char, code)
  if currentScreen == "login" then
    if char == 9 then loginField = loginField % 2 + 1; dirty = true; return end
    if char == 13 then processAction("login_submit"); return end
    if char == 8 then
      if loginField == 1 then loginNick = unicode.sub(loginNick, 1, -2) else loginPass = unicode.sub(loginPass, 1, -2) end
      dirty = true; return
    end
    if char >= 32 and char <= 0x10FFFF then
      if loginField == 1 then if unicode.len(loginNick) < 24 then loginNick = loginNick .. unicode.char(char) end
      else if unicode.len(loginPass) < 24 then loginPass = loginPass .. unicode.char(char) end end
      dirty = true
    end
    return
  end
  if not serverSession.authed then return end
  if code == keyboard.keys.escape then
    if currentScreen == "edit_ban" then currentScreen = "editor"
    elseif currentScreen == "editor" then currentScreen = "players"
    elseif currentScreen ~= "dashboard" and currentScreen ~= "login" then currentScreen = "dashboard"
    else return end
    dirty = true; return
  end
  if currentScreen == "players" then
    if char == 8 then playersSearch = unicode.sub(playersSearch, 1, -2); playersScroll = 1; dirty = true; return end
    if char >= 32 and char <= 0x10FFFF then
      if unicode.len(playersSearch) < 20 then playersSearch = playersSearch .. unicode.char(char) end
      playersScroll = 1; dirty = true
    end
    return
  end
  if currentScreen == "editor" then
    if char == 13 then processAction("edit_save_bal"); return end
    if char == 8 then editCoinInput = unicode.sub(editCoinInput, 1, -2); dirty = true; return end
    if char == 9 then editCoinInput, editEmaInput = editEmaInput, editCoinInput; dirty = true; return end
    if (char >= 48 and char <= 57) or char == 46 then
      if unicode.len(editCoinInput) < 12 then editCoinInput = editCoinInput .. unicode.char(char) end
      dirty = true
    end
    return
  end
  if currentScreen == "edit_ban" then
    if char == 9 then banField = banField % 2 + 1; dirty = true; return end
    if char == 13 then processAction("ban_save"); return end
    if char == 8 then
      if banField == 1 then banReasonInput = unicode.sub(banReasonInput, 1, -2) else banDurationInput = unicode.sub(banDurationInput, 1, -2) end
      dirty = true; return
    end
    if char >= 32 and char <= 0x10FFFF then
      if banField == 1 then if unicode.len(banReasonInput) < 60 then banReasonInput = banReasonInput .. unicode.char(char) end
      else if unicode.len(banDurationInput) < 40 then banDurationInput = banDurationInput .. unicode.char(char) end end
      dirty = true
    end
    return
  end
  if currentScreen == "admins" then
    if char == 9 then adminField = adminField % 2 + 1; dirty = true; return end
    if char == 13 then processAction("admin_add"); return end
    if char == 8 then
      if adminField == 1 then adminNickInput = unicode.sub(adminNickInput, 1, -2) else adminPassInput = unicode.sub(adminPassInput, 1, -2) end
      dirty = true; return
    end
    if char >= 32 and char <= 0x10FFFF then
      if adminField == 1 then if unicode.len(adminNickInput) < 24 then adminNickInput = adminNickInput .. unicode.char(char) end
      else if unicode.len(adminPassInput) < 24 then adminPassInput = adminPassInput .. unicode.char(char) end end
      dirty = true
    end
    return
  end
end

local function handleScroll(dir)
  if not serverSession.authed then return end
  if currentScreen == "players" then
    local list = filteredPlayers(playersSearch)
    local rows = math.max(4, screenH - 9)
    local maxScroll = math.max(1, #list - rows + 1)
    playersScroll = math.max(1, math.min(playersScroll + (dir == -1 and 1 or -1), maxScroll))
    dirty = true
  elseif currentScreen == "tx" then
    local rows = math.max(4, screenH - 7)
    local maxScroll = math.max(0, #transactions - rows)
    txScroll = math.max(0, math.min(txScroll + (dir == -1 and 1 or -1), maxScroll))
    dirty = true
  elseif currentScreen == "fb" then
    local rows = math.max(3, screenH - 8)
    local per = rows and math.max(1, math.floor(rows / 3)) or 1
    local maxScroll = math.max(1, #feedbacks - per + 1)
    fbScroll = math.max(1, math.min(fbScroll + (dir == -1 and 1 or -1), maxScroll))
    dirty = true
  elseif currentScreen == "rep" then
    local rows = math.max(3, screenH - 8)
    local per = math.max(1, math.floor(rows / 3))
    local maxScroll = math.max(0, #reports - per)
    repScroll = math.max(0, math.min(repScroll + (dir == -1 and 1 or -1), maxScroll))
    dirty = true
  end
end

-- ============================================================
-- ГЛАВНЫЙ ЦИКЛ (БЫСТРЫЙ: перерисовка только по dirty)
-- ============================================================
local function main()
  logLine("SERVER start")
  while true do
    local ok, ev = pcall(event.pull, 0.2)
    if ok and ev then
      local e = ev[1]
      if e == "modem_message" then
        local sender = ev[3]
        local data = ev[6]
        local ok2, msg = pcall(serialization.unserialize, data)
        if ok2 and type(msg) == "table" then handleModem(sender, msg) end
      elseif e == "touch" then
        local b = hitAt(ev[3], ev[4])
        if b then processAction(b.id, b.data) end
      elseif e == "key_down" then
        handleKey(ev[3], ev[4])
      elseif e == "scroll" then
        handleScroll(ev[5])
      end
    end
    flushSaves(false)
    if dirty then redraw(); dirty = false end
  end
end
gpu.setBackground(C.bg)
while true do
  local ok, err = pcall(main)
  if not ok then
    gpu.setBackground(C.bg); gpu.setForeground(C.red)
    gpu.set(2, 2, "ОШИБКА СЕРВЕРА: " .. tostring(err))
    gpu.setForeground(C.yellow)
    gpu.set(2, 3, "Перезапуск через 5 сек...")
    os.sleep(5)
    flushSaves(true)
    dirty = true
  end
end
