-- ============================================================
-- STATS.LUA v2.2 — ЭКРАН СТАТИСТИКИ МАГАЗИНА
-- + ИСПРАВЛЕНО: Ctrl+G / Ctrl+H (неверный разбор key_down)
-- + Простые рамки ┌─┐│└─┘, убрана бегущая строка
-- + ТОП COIN / ТОП EMA / ТОП ОБОРОТ — раздельные и компактные
-- + НОВЫЕ ИГРОКИ — с датой+временем, без цветных рангов
-- + График 7 дней подписан "покупки"
-- + By KaRMa__
-- ============================================================
local component = require("component")
local event = require("event")
local serialization = require("serialization")
local unicode = require("unicode")
local computer = require("computer")
local fs = require("filesystem")
local gpu = component.gpu
local modem = component.modem
modem.open(0xffef)

local SERVER = "a7096c74-1bc4-43a6-8dff-2d4394d22c0e"
local OWNER = "KaRMa__"
local AUTORUN_LINE = "lua /home/stats.lua"
local RC_PATHS = {"/home/.shrc", "/.shrc"}
local REFRESH = 20

local C = {
  bg = 0x0D0B14, band = 0x150F22, panel = 0x171322, panel2 = 0x201A2E,
  border = 0x6A0DAD, accent = 0x9D4EDD, accent2 = 0xC792EA,
  coin = 0xFFCE7A, ema = 0x7FB6FF,
  green = 0x00D9A3, red = 0xFF4D6D, orange = 0xFF9F43, yellow = 0xFFD166,
  white = 0xF2F0F8, text = 0xD9D2EA, muted = 0x8A7FA8, dim = 0x3A3350,
  gold = 0xFFD700, silver = 0xC0C0C0, bronze = 0xCD7F32,
}

local W, H = gpu.maxResolution()
gpu.setResolution(W, H)

-- ============================================================
-- ХЕЛПЕРЫ
-- ============================================================
local function ulen(t) return unicode.len(tostring(t or "")) end
local function clip(t, w)
  t = tostring(t or "")
  if ulen(t) <= w then return t end
  if w <= 1 then return unicode.sub(t, 1, w) end
  return unicode.sub(t, 1, w - 1) .. "…"
end
local function writeText(x, y, t, fg, bg)
  if y < 1 or y > H or x > W or x < 1 then return end
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.set(x, y, t)
end
local function writeRight(x, y, w, t, fg, bg)
  t = tostring(t or "")
  local xx = x + w - 2 - ulen(t)
  if xx < x + 1 then xx = x + 1 end
  writeText(xx, y, t, fg, bg)
end
local function fillRect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  gpu.setBackground(bg)
  gpu.fill(x, y, w, h, " ")
end

-- Простая рамка ┌─┐ │ └─┘, заголовок в верхней границе
local function drawBox(x, y, w, h, color, title)
  if w < 4 or h < 3 then return end
  fillRect(x, y, w, h, C.panel)
  local top
  if title and ulen(title) > 0 then
    local maxT = math.max(1, w - 6)
    local t = title
    if ulen(t) > maxT then t = unicode.sub(t, 1, maxT - 1) .. "…" end
    local fc = math.max(0, w - 5 - ulen(t))
    top = "┌─ " .. t .. " " .. string.rep("─", fc) .. "┐"
  else
    top = "┌" .. string.rep("─", w - 2) .. "┐"
  end
  writeText(x, y, top, color, C.panel)
  for i = 1, h - 2 do
    writeText(x, y + i, "│", color, C.panel)
    writeText(x + w - 1, y + i, "│", color, C.panel)
  end
  writeText(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘", color, C.panel)
end

local function groupNum(n, dec)
  dec = dec or 0
  local fmt = string.format("%." .. dec .. "f", tonumber(n) or 0)
  local int, frac = fmt:match("^([^%.]+)(%.?.*)$")
  local sign = ""
  if int:sub(1, 1) == "-" then sign = "-"; int = int:sub(2) end
  local out = ""
  while #int > 3 do
    out = "," .. int:sub(-3) .. out
    int = int:sub(1, #int - 3)
  end
  return sign .. int .. out .. (frac or "")
end

local function trimName(s)
  s = tostring(s or "")
  return s:match("^%s*(.-)%s*$") or s
end
local function samePlayerName(a, b)
  a, b = trimName(a), trimName(b)
  if a == "" or b == "" then return false end
  return unicode.lower(a) == unicode.lower(b)
end

-- Форматирование даты новых игроков: "2024-05-12 14:30" -> "12.05 14:30"
local function fmtDate(s)
  s = tostring(s or "")
  local y, m, d, hh, mm = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d)")
  if y then return d .. "." .. m .. " " .. hh .. ":" .. mm end
  y, m, d = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if y then return d .. "." .. m .. "." .. y:sub(3) end
  local ts = tonumber(s)
  if ts and ts > 0 then return os.date("%d.%m %H:%M", ts) end
  return clip(s, 11)
end

local tmpfs = component.proxy(computer.tmpAddress())
local function getRealTimestamp()
  local ok, r = pcall(function()
    local h = tmpfs.open("/time", "w")
    tmpfs.write(h, "time")
    tmpfs.close(h)
    return tmpfs.lastModified("/time") / 1000 + 3 * 3600
  end)
  if ok and r then return r end
  return os.time() + 3 * 3600
end
local function currentTimeStr()
  if view and view.time and (computer.uptime() - lastDataAt) < 45 then
    return tostring(view.time)
  end
  return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end

-- ============================================================
-- АВТОЗАПУСК (.shrc)
-- ============================================================
local function readWholeFile(p)
  local f = io.open(p, "r")
  if not f then return nil end
  local d = f:read("*a"); f:close()
  return d or ""
end
local function writeWholeFile(p, t)
  local f = io.open(p, "w")
  if not f then return false end
  f:write(t); f:close()
  return true
end
local function trimLine(s) return s:gsub("^%s+", ""):gsub("%s+$", "") end
local function autorunEnabled()
  for _, p in ipairs(RC_PATHS) do
    local d = readWholeFile(p)
    if d then
      for line in d:gmatch("[^\n]+") do
        if trimLine(line) == AUTORUN_LINE then return true end
      end
    end
  end
  return false
end
local function setAutorun(on)
  for _, p in ipairs(RC_PATHS) do
    local d = readWholeFile(p)
    if on then
      if d == nil then d = "" end
      local found = false
      for line in d:gmatch("[^\n]+") do
        if trimLine(line) == AUTORUN_LINE then found = true; break end
      end
      if not found then
        if d ~= "" and not d:find("\n$") then d = d .. "\n" end
        writeWholeFile(p, d .. AUTORUN_LINE .. "\n")
      end
    else
      if d then
        local out = {}
        for line in d:gmatch("[^\n]+") do
          if trimLine(line) ~= AUTORUN_LINE then out[#out + 1] = line end
        end
        writeWholeFile(p, (#out > 0 and table.concat(out, "\n") .. "\n" or ""))
      end
    end
  end
end

-- ============================================================
-- СОСТОЯНИЕ
-- ============================================================
view = nil
lastDataAt = 0
lastReqAt = -100
dashEver = false
toastText, toastColor, toastUntil = "", C.muted, 0
lastClock = ""

local function toast(t, c, s)
  toastText, toastColor, toastUntil = tostring(t or ""), c or C.muted, computer.uptime() + (s or 3)
end

-- ============================================================
-- ЛОГОТИП
-- ============================================================
local BIG = {
  P = {"███", "█ █", "███", "█  ", "█  "},
  I = {"███", " █ ", " █ ", " █ ", "███"},
  S = {"███", "█  ", "███", "  █", "███"},
  H = {"█ █", "█ █", "███", "█ █", "█ █"},
  O = {"███", "█ █", "█ █", "█ █", "███"},
  [" "] = {"   ", "   ", "   ", "   ", "   "},
}
local function drawLogo(x, y)
  local word = "PI SHOP"
  for ci = 1, ulen(word) do
    local g = BIG[unicode.sub(word, ci, ci)]
    if g then
      for r = 1, 5 do
        writeText(x + (ci - 1) * 4 + 1, y + r, g[r], C.border, C.band)
        writeText(x + (ci - 1) * 4, y + r - 1, g[r], C.white, C.band)
      end
    end
  end
end

local function rankColor(i)
  if i == 1 then return C.gold end
  if i == 2 then return C.silver end
  if i == 3 then return C.bronze end
  return C.text
end

local function drawKpi(x, y, w, h, icon, label, value, sub, color, dec)
  drawBox(x, y, w, h, color, icon .. " " .. label)
  local val = groupNum(value, dec or 0)
  writeText(x + math.max(1, math.floor((w - ulen(val)) / 2)), y + 2, val, C.white, C.panel)
  local st = tostring(sub)
  writeText(x + math.max(1, math.floor((w - ulen(st)) / 2)), y + h - 2, st, C.muted, C.panel)
end

-- ============================================================
-- РАСКЛАДКА ПАНЕЛЕЙ
-- ============================================================
local function layoutCols(n, gap)
  gap = gap or 1
  local w = math.floor((W - (n - 1) * gap) / n)
  local xs = {}
  for i = 1, n do xs[i] = 1 + (i - 1) * (w + gap) end
  return w, xs
end

-- ============================================================
-- ОТРИСОВКА ВСЕГО ЭКРАНА
-- ============================================================
local function drawAll()
  local d = view or {}
  gpu.setBackground(C.bg); gpu.setForeground(C.text)
  gpu.fill(1, 1, W, H, " ")

  -- ШАПКА
  fillRect(1, 1, W, 8, C.band)
  drawLogo(3, 2)
  writeText(32, 3, "MARKET STATISTICS", C.accent2, C.band)
  writeText(32, 5, "рейтинг игроков • экономика • активность", C.muted, C.band)
  local online = lastDataAt > 0 and (computer.uptime() - lastDataAt) < 45
  local bcol = online and C.green or C.red
  writeText(W - 14, 3, online and "● ONLINE" or "● OFFLINE", bcol, C.band)
  writeText(W - 22, 6, currentTimeStr(), C.muted, C.band)
  -- градиентный разделитель под шапкой
  local shades = {0x6A0DAD, 0x7B2CBF, 0x9D4EDD, 0xC792EA, 0x9D4EDD, 0x7B2CBF, 0x6A0DAD}
  for i = 1, W do
    gpu.setBackground(shades[((i - 1) % #shades) + 1])
    gpu.fill(i, 9, 1, 1, " ")
  end

  -- KPI (4 карточки)
  local ky = 10
  local kh = 6
  local pw4, xs4 = layoutCols(4, 1)
  drawKpi(xs4[1], ky, pw4, kh, "◉", "ИГРОКОВ", d.totalPlayers or 0, "всего", C.accent)
  drawKpi(xs4[2], ky, pw4, kh, "≡", "ТРАНЗАКЦИЙ", d.txTotal or 0, "сегодня: " .. tostring(d.txToday or 0), C.orange)
  drawKpi(xs4[3], ky, pw4, kh, "☄", "COINA", d.coinTotal or 0, "в обращении", C.coin, 1)
  drawKpi(xs4[4], ky, pw4, kh, "⛭", "EMA", d.emaTotal or 0, "в обращении", C.ema, 1)

  -- РАСКЛАДКА
  local contentTop = ky + kh + 2
  local contentBottom = H - 1
  local total = contentBottom - contentTop
  local row2H = math.max(10, math.floor(total * 0.42))
  local row2Y = contentTop
  local row3Y = row2Y + row2H + 2
  local row3H = contentBottom - row3Y + 1
  local pw3, xs3 = layoutCols(3, 1)

  -- ============ ROW 2: ТОП COIN | ТОП EMA | ТОП ОБОРОТ | НОВЫЕ ============
  -- ТОП COIN
  local px = xs4[1]
  drawBox(px, row2Y, pw4, row2H, C.coin, "ТОП COIN")
  writeText(px + 2, row2Y + 1, "#", C.muted, C.panel)
  writeText(px + 4, row2Y + 1, "ИГРОК", C.muted, C.panel)
  writeRight(px + 1, row2Y + 1, pw4, "COIN", C.muted, C.panel)
  local tc = d.topCoin or {}
  local maxRows2 = row2H - 3
  for i = 1, math.min(#tc, maxRows2) do
    local yy = row2Y + 1 + i
    writeText(px + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(px + 4, yy, clip(tc[i].name, pw4 - 14), C.text, C.panel)
    writeRight(px + 1, yy, pw4, groupNum(tc[i].v or 0, 1), C.coin, C.panel)
  end
  if #tc == 0 then writeText(px + 2, row2Y + 2, "Нет данных", C.dim, C.panel) end

  -- ТОП EMA
  px = xs4[2]
  drawBox(px, row2Y, pw4, row2H, C.ema, "ТОП EMA")
  writeText(px + 2, row2Y + 1, "#", C.muted, C.panel)
  writeText(px + 4, row2Y + 1, "ИГРОК", C.muted, C.panel)
  writeRight(px + 1, row2Y + 1, pw4, "EMA", C.muted, C.panel)
  local te = d.topEma or {}
  for i = 1, math.min(#te, maxRows2) do
    local yy = row2Y + 1 + i
    writeText(px + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(px + 4, yy, clip(te[i].name, pw4 - 14), C.text, C.panel)
    writeRight(px + 1, yy, pw4, groupNum(te[i].v or 0, 1), C.ema, C.panel)
  end
  if #te == 0 then writeText(px + 2, row2Y + 2, "Нет данных", C.dim, C.panel) end

  -- ТОП ОБОРОТ (coin+ema) — дополнительный «интересный» топ
  px = xs4[3]
  drawBox(px, row2Y, pw4, row2H, C.accent2, "ТОП ОБОРОТ")
  writeText(px + 2, row2Y + 1, "#", C.muted, C.panel)
  writeText(px + 4, row2Y + 1, "ИГРОК", C.muted, C.panel)
  writeRight(px + 1, row2Y + 1, pw4, "СУММА", C.muted, C.panel)
  local cmap = {}
  for _, e in ipairs(tc) do cmap[e.name] = (cmap[e.name] or 0) + (e.v or 0) end
  for _, e in ipairs(te) do cmap[e.name] = (cmap[e.name] or 0) + (e.v or 0) end
  local combined = {}
  for n, v in pairs(cmap) do combined[#combined + 1] = {name = n, v = v} end
  table.sort(combined, function(a, b) return a.v > b.v end)
  for i = 1, math.min(#combined, maxRows2) do
    local yy = row2Y + 1 + i
    writeText(px + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(px + 4, yy, clip(combined[i].name, pw4 - 14), C.text, C.panel)
    writeRight(px + 1, yy, pw4, groupNum(combined[i].v, 1), C.accent2, C.panel)
  end
  if #combined == 0 then writeText(px + 2, row2Y + 2, "Нет данных", C.dim, C.panel) end

  -- НОВЫЕ ИГРОКИ (мелко, без цветов, с датой+временем)
  px = xs4[4]
  drawBox(px, row2Y, pw4, row2H, C.accent, "НОВЫЕ ИГРОКИ")
  writeText(px + 2, row2Y + 1, "ИГРОК", C.muted, C.panel)
  writeRight(px + 1, row2Y + 1, pw4, "ДАТА", C.muted, C.panel)
  local np = d.newPlayers or {}
  for i = 1, math.min(#np, maxRows2) do
    local yy = row2Y + 1 + i
    writeText(px + 2, yy, clip(np[i].name, pw4 - 15), C.text, C.panel)
    writeRight(px + 1, yy, pw4, fmtDate(np[i].date), C.muted, C.panel)
  end
  if #np == 0 then writeText(px + 2, row2Y + 2, "Нет данных", C.dim, C.panel) end

  -- ============ ROW 3: ПОКУПКИ 7 ДНЕЙ | ТОП АКТИВНОСТЬ | ПОСЛЕДНИЕ ОПЕРАЦИИ ============
  -- График 7 дней (покупки)
  local gx = xs3[1]
  drawBox(gx, row3Y, pw3, row3H, C.accent2, "ПОКУПКИ 7 ДНЕЙ")
  writeText(gx + 2, row3Y + 1, "(покупки и продажи)", C.muted, C.panel)
  local wk = d.week or {}
  local maxOps = 1
  for _, wki in ipairs(wk) do
    local v = wki.ops or wki.purchases or 0
    if v > maxOps then maxOps = v end
  end
  local chartTop = row3Y + 3
  local chartBot = row3Y + row3H - 3
  local labY = row3Y + row3H - 2
  local maxH = chartBot - chartTop
  local colW = math.floor((pw3 - 4) / 7)
  for i = 1, math.min(7, #wk) do
    local ops = wk[i].ops or wk[i].purchases or 0
    local bh = math.floor(maxH * ops / maxOps)
    if ops > 0 and bh < 1 then bh = 1 end
    if bh > maxH then bh = maxH end
    local cx = gx + 2 + (i - 1) * colW + math.floor((colW - 1) / 2)
    if bh > 0 then
      writeText(cx, chartBot - bh, tostring(ops), C.text, C.panel)
    end
    for r = 1, bh do
      writeText(cx, chartBot - bh + r, "█", (r == bh) and C.accent2 or C.accent, C.panel)
    end
    writeText(gx + 2 + (i - 1) * colW, labY, clip(wk[i].date or "", colW), C.muted, C.panel)
  end
  if #wk == 0 then writeText(gx + 2, chartTop, "Нет данных", C.dim, C.panel) end

  -- ТОП АКТИВНОСТЬ (по операциям)
  local ax = xs3[2]
  drawBox(ax, row3Y, pw3, row3H, C.green, "ТОП АКТИВНОСТЬ")
  writeText(ax + 2, row3Y + 1, "#", C.muted, C.panel)
  writeText(ax + 4, row3Y + 1, "ИГРОК", C.muted, C.panel)
  writeRight(ax + 1, row3Y + 1, pw3, "ОПЕР.", C.muted, C.panel)
  local to = d.topVisits or d.topOps or {}
  local maxRows3 = row3H - 3
  for i = 1, math.min(#to, maxRows3) do
    local yy = row3Y + 1 + i
    writeText(ax + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(ax + 4, yy, clip(to[i].name, pw3 - 14), C.text, C.panel)
    writeRight(ax + 1, yy, pw3, tostring(math.floor(to[i].v or 0)), C.white, C.panel)
  end
  if #to == 0 then writeText(ax + 2, row3Y + 2, "Нет данных", C.dim, C.panel) end

  -- ПОСЛЕДНИЕ ОПЕРАЦИИ
  local rx = xs3[3]
  drawBox(rx, row3Y, pw3, row3H, C.orange, "ПОСЛЕДНИЕ ОПЕРАЦИИ")
  writeText(rx + 2, row3Y + 1, "Т", C.muted, C.panel)
  writeText(rx + 4, row3Y + 1, "ИГРОК", C.muted, C.panel)
  writeText(rx + 16, row3Y + 1, "ПРЕДМЕТ", C.muted, C.panel)
  writeRight(rx + 1, row3Y + 1, pw3, "КОЛ", C.muted, C.panel)
  local rc = d.recent or {}
  for i = 1, math.min(#rc, maxRows3) do
    local yy = row3Y + 1 + i
    local t = rc[i]
    local isBuy = (t.type == "buy")
    writeText(rx + 2, yy, isBuy and "↓" or "↑", isBuy and C.green or C.red, C.panel)
    writeText(rx + 4, yy, clip(t.player, 11), C.text, C.panel)
    writeText(rx + 16, yy, clip(t.item, pw3 - 24), C.muted, C.panel)
    writeRight(rx + 1, yy, pw3, tostring(math.floor(tonumber(t.qty) or 0)), C.white, C.panel)
  end
  if #rc == 0 then writeText(rx + 2, row3Y + 2, "Нет данных", C.dim, C.panel) end

  -- ФУТЕР
  fillRect(1, H, W, 1, C.panel2)
  local showToast = toastText ~= "" and computer.uptime() <= toastUntil
  if showToast then
    writeText(2, H, clip(toastText, W - 2), toastColor, C.panel2)
  else
    writeText(2, H, "stats v2.2  •  by " .. OWNER, C.dim, C.panel2)
  end
end

-- ============================================================
-- СЕТЬ
-- ============================================================
local function request()
  modem.send(SERVER, 0xffef, serialization.serialize({op = "get_dashboard", limit = 7}))
  if not dashEver then
    modem.send(SERVER, 0xffef, serialization.serialize({op = "get_top", category = "balance", page = 1, perPage = 100}))
    modem.send(SERVER, 0xffef, serialization.serialize({op = "get_top", category = "purchases", page = 1, perPage = 100}))
  end
  lastReqAt = computer.uptime()
end

local topBalance, topPurchases = nil, nil

local function buildFallbackView()
  local v = view or {}
  if topBalance then
    v.totalPlayers = topBalance.total or #(topBalance.list or {}) or 0
    local coin, ema = 0, 0
    local byCoin, byEma = {}, {}
    for _, e in ipairs(topBalance.list or {}) do
      coin = coin + (e.coin or 0)
      ema = ema + (e.ema or 0)
      byCoin[#byCoin + 1] = {name = e.name, v = e.coin or 0}
      byEma[#byEma + 1] = {name = e.name, v = e.ema or 0}
    end
    v.coinTotal, v.emaTotal = coin, ema
    table.sort(byCoin, function(a, b) return a.v > b.v end)
    table.sort(byEma, function(a, b) return a.v > b.v end)
    v.topCoin, v.topEma = byCoin, byEma
  end
  if topPurchases then
    local tx, byOps = 0, {}
    for _, e in ipairs(topPurchases.list or {}) do
      local ops = (e.purchases or 0) + (e.sells or 0)
      tx = tx + ops
      byOps[#byOps + 1] = {name = e.name, v = ops}
    end
    v.txTotal = tx
    table.sort(byOps, function(a, b) return a.v > b.v end)
    v.topOps = byOps
  end
  v.newPlayers = v.newPlayers or {}
  v.week = v.week or {}
  v.recent = v.recent or {}
  view = v
end

local function handleModem(from, raw)
  if from ~= SERVER then return end
  local ok, msg = pcall(serialization.unserialize, raw)
  if not ok or type(msg) ~= "table" then return end
  if msg.op == "dashboard_data" then
    view = msg
    dashEver = true
    lastDataAt = computer.uptime()
    drawAll()
  elseif msg.op == "top_data" and not dashEver then
    if msg.category == "balance" then
      topBalance = msg
    elseif msg.category == "purchases" then
      topPurchases = msg
    end
    buildFallbackView()
    lastDataAt = computer.uptime()
    drawAll()
  end
end

-- ============================================================
-- ГОРЯЧИЕ КЛАВИШИ ВЛАДЕЛЬЦА
-- Ctrl+G (char=7, code=34) = update.lua
-- Ctrl+H (char=8, code=35) = toggle autorun
-- ВАЖНО: event.pull для key_down: (address, char, code, player)
-- ============================================================
local function handleKey(char, code, pname)
  if not samePlayerName(pname or "", OWNER) then return end
  if char == 7 and code == 34 then
    if fs.exists("/home/update.lua") then
      toast("⚙ Запускаю update.lua...", C.accent2, 2)
      drawAll()
      local ok = pcall(function() os.execute("/home/update.lua") end)
      drawAll()
      if ok then
        toast("✅ update.lua завершил работу", C.green, 3)
      else
        toast("⚠ update.lua завершился с ошибкой", C.yellow, 3)
      end
    else
      toast("❌ Файл /home/update.lua не найден", C.red, 3)
    end
    drawAll()
  elseif char == 8 and code == 35 then
    local on = not autorunEnabled()
    setAutorun(on)
    if on then
      toast("✅ Автозапуск stats.lua ВКЛЮЧЕН (.shrc)", C.green, 4)
    else
      toast("⚠ Автозапуск stats.lua ВЫКЛЮЧЕН (.shrc)", C.yellow, 4)
    end
    drawAll()
  end
end

-- ============================================================
-- ГЛАВНЫЙ ЦИКЛ
-- ============================================================
local function main()
  drawAll()
  request()
  while true do
    local ev = {pcall(event.pull, 1)}
    if ev[1] and ev[2] then
      local e = ev[2]
      if e == "modem_message" then
        handleModem(ev[4], ev[7])
      elseif e == "key_down" then
        -- ИСПРАВЛЕНО: char = ev[4], code = ev[5], player = ev[6]
        handleKey(ev[4], ev[5], ev[6])
      end
    end
    local now = computer.uptime()
    if now - lastReqAt >= REFRESH then request() end
    local clock = os.date("%H:%M:%S", getRealTimestamp())
    if clock ~= lastClock then
      lastClock = clock
      writeText(W - 22, 6, currentTimeStr(), C.muted, C.band)
      local online = lastDataAt > 0 and (now - lastDataAt) < 45
      local bcol = online and C.green or C.red
      writeText(W - 14, 3, online and "● ONLINE" or "● OFFLINE", bcol, C.band)
      -- футер
      fillRect(1, H, W, 1, C.panel2)
      local showToast = toastText ~= "" and now <= toastUntil
      if showToast then
        writeText(2, H, clip(toastText, W - 2), toastColor, C.panel2)
      else
        writeText(2, H, "stats v2.2  •  by " .. OWNER, C.dim, C.panel2)
      end
    end
  end
end

local ok, err = pcall(main)
if not ok then
  gpu.setBackground(C.bg); gpu.setForeground(C.red)
  gpu.fill(1, 1, W, H, " ")
  gpu.set(2, 2, "Ошибка stats.lua: " .. clip(tostring(err), W - 4))
  gpu.setForeground(C.muted)
  gpu.set(2, 4, "Перезапуск через 5 сек...")
  os.sleep(5)
end
