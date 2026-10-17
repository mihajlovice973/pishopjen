-- ============================================================
-- STATS.LUA v3.0 — ЭКРАН СТАТИСТИКИ МАГАЗИНА
-- + фикс: текст в футере сдвинут ближе к левому краю
-- + фикс: ТОП ТРАТЫ больше не ломает рамку (правильный отступ)
-- + фикс: нет мерцания при нажатии клавиш (1 перерисовка за тик)
-- + фикс: обработка screen_resized (устранение артефактов)
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
local AUTHOR = "KaRMa__"
local VERSION = "v.0.1"
local AUTORUN_LINE = "lua /home/stats.lua"
local RC_PATHS = {"/home/.shrc", "/.shrc"}
local REFRESH = 20
local TOPS_REFRESH = 60

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
  if w <= 0 then return "" end
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

-- Жесткая обрезка: текст заканчивается за 2 символа до рамки
local function writeRight(x, y, w, t, fg, bg)
  t = tostring(t or "")
  t = clip(t, w - 5)
  local xx = x + w - 3 - ulen(t) -- отступ от правой рамки
  if xx < x + 2 then xx = x + 2 end
  writeText(xx, y, t, fg, bg)
end

local function fillRect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  gpu.setBackground(bg)
  gpu.fill(x, y, w, h, " ")
end

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

local function fmtDate(s)
  s = tostring(s or "")
  local d, m, y, hh, mm = s:match("(%d%d)%.(%d%d)%.(%d%d%d%d)%s+(%d%d):(%d%d)")
  if d then return d .. "." .. m .. " " .. hh .. ":" .. mm end
  local y2, m2, d2, hh2, mm2 = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d)")
  if y2 then return d2 .. "." .. m2 .. " " .. hh2 .. ":" .. mm2 end
  return clip(s, 14)
end

-- ============================================================
-- ВРЕМЯ
-- ============================================================
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

local timeBaseServer = 0
local timeBaseUptime = 0

local function parseServerTime(tstr)
  if not tstr then return nil end
  local d, m, y, hh, mm, ss = tstr:match("(%d%d)%.(%d%d)%.(%d%d%d%d) (%d%d):(%d%d):(%d%d)")
  if not d then return nil end
  local ok, t = pcall(os.time, {year=tonumber(y), month=tonumber(m), day=tonumber(d),
                                 hour=tonumber(hh), min=tonumber(mm), sec=tonumber(ss)})
  if ok then return t end
  return nil
end

local function currentTimeStr()
  local t
  if timeBaseServer > 0 then
    t = timeBaseServer + (computer.uptime() - timeBaseUptime)
  else
    t = getRealTimestamp()
  end
  return os.date("%d.%m.%Y %H:%M:%S", t)
end

-- ============================================================
-- АВТОЗАПУСК
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
lastTopsReqAt = -100
dashEver = false
toastText, toastColor, toastUntil = "", C.muted, 0
lastClock = ""
firstDrawDone = false
needsRedraw = true

local topRequestsQueue = {}
local nextTopRequestAt = 0

local function toast(t, c, s)
  toastText, toastColor, toastUntil = tostring(t or ""), c or C.muted, computer.uptime() + (s or 3)
  needsRedraw = true
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
local function drawLogo(x, y, fg)
  local word = "PI SHOP"
  for ci = 1, ulen(word) do
    local g = BIG[unicode.sub(word, ci, ci)]
    if g then
      for r = 1, 5 do
        writeText(x + (ci - 1) * 4, y + r - 1, g[r], fg or C.accent2, C.band)
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

-- ============================================================
-- KPI
-- ============================================================
local function drawKpi(x, y, w, h, icon, label, value, sub, color, dec)
  drawBox(x, y, w, h, color, icon .. " " .. label)
  local val = groupNum(value, dec or 0)
  writeText(x + math.max(1, math.floor((w - ulen(val)) / 2)), y + 2, val, C.white, C.panel)
  local st = tostring(sub)
  writeText(x + math.max(1, math.floor((w - ulen(st)) / 2)), y + h - 2, st, C.muted, C.panel)
end

-- ============================================================
-- УНИВЕРСАЛЬНЫЙ ТОП
-- ============================================================
local function drawTopPanel(px, py, pw, ph, title, color, entries, valueFn, valueColor, ranked)
  drawBox(px, py, pw, ph, color, title)
  writeText(px + 2, py + 1, "#", C.muted, C.panel)
  writeText(px + 4, py + 1, "ИГРОК", C.muted, C.panel)
  writeRight(px + 1, py + 1, pw, "ЗНАЧЕНИЕ", C.muted, C.panel)
  local maxRows = ph - 3
  local list = entries or {}
  for i = 1, math.min(#list, maxRows) do
    local e = list[i]
    if not e then break end
    local yy = py + 1 + i
    local rc = ranked ~= false and rankColor(i) or C.text
    writeText(px + 2, yy, tostring(i), rc, C.panel)
    writeText(px + 4, yy, clip(e.name or "?", pw - 16), rc, C.panel)
    writeRight(px + 1, yy, pw, valueFn(e), valueColor, C.panel)
  end
  if #list == 0 then
    writeText(px + 2, py + 2, "Нет данных", C.dim, C.panel)
  end
end

-- ============================================================
-- НОВЫЕ ИГРОКИ
-- ============================================================
local function drawNewPlayers(px, py, pw, ph, entries)
  drawBox(px, py, pw, ph, C.accent, "НОВЫЕ ИГРОКИ")
  writeText(px + 2, py + 1, "ИГРОК", C.muted, C.panel)
  writeRight(px + 1, py + 1, pw, "ДАТА МСК", C.muted, C.panel)
  local maxRows = ph - 3
  local list = entries or {}
  for i = 1, math.min(#list, maxRows) do
    local e = list[i]
    if not e then break end
    local yy = py + 1 + i
    writeText(px + 2, yy, clip(e.name or "?", pw - 14), C.text, C.panel)
    writeRight(px + 1, yy, pw, fmtDate(e.date), C.muted, C.panel)
  end
  if #list == 0 then writeText(px + 2, py + 2, "Нет данных", C.dim, C.panel) end
end

-- ============================================================
-- ГРАФИК 7 ДНЕЙ
-- ============================================================
local function drawWeekChart(px, py, pw, ph, entries)
  drawBox(px, py, pw, ph, C.accent2, "ПОКУПКИ 7 ДНЕЙ")
  local wk = entries or {}
  local maxOps = 1
  for _, e in ipairs(wk) do
    local v = e.ops or e.purchases or 0
    if v > maxOps then maxOps = v end
  end
  local chartTop = py + 2
  local chartBot = py + ph - 3
  local labY = py + ph - 2
  local maxH = math.max(1, chartBot - chartTop)
  local innerW = pw - 4
  local colW = math.max(2, math.floor(innerW / 7))
  for i = 1, math.min(7, #wk) do
    local ops = wk[i].ops or wk[i].purchases or 0
    local bh = math.floor(maxH * ops / maxOps)
    if ops > 0 and bh < 1 then bh = 1 end
    if bh > maxH then bh = maxH end
    local cx = px + 2 + (i - 1) * colW + math.floor((colW - 1) / 2)
    if bh > 0 then
      writeText(cx, chartBot - bh, tostring(ops), C.text, C.panel)
    end
    for r = 1, bh do
      writeText(cx, chartBot - bh + r, "█", (r == bh) and C.accent2 or C.accent, C.panel)
    end
    writeText(px + 2 + (i - 1) * colW, labY, clip(wk[i].date or "", colW), C.muted, C.panel)
  end
  if #wk == 0 then writeText(px + 2, chartTop, "Нет данных", C.dim, C.panel) end
end

-- ============================================================
-- ПОСЛЕДНИЕ ОПЕРАЦИИ (BUY / SELL)
-- ============================================================
local function drawRecent(px, py, pw, ph, entries)
  drawBox(px, py, pw, ph, C.orange, "ПОСЛЕДНИЕ ОПЕРАЦИИ")
  writeText(px + 2, py + 1, "ОП", C.muted, C.panel)
  writeText(px + 6, py + 1, "ИГРОК", C.muted, C.panel)
  writeText(px + 20, py + 1, "ПРЕДМЕТ", C.muted, C.panel)
  writeRight(px + 1, py + 1, pw, "КОЛ", C.muted, C.panel)
  local maxRows = ph - 3
  local rc = entries or {}
  for i = 1, math.min(#rc, maxRows) do
    local t = rc[i]
    local yy = py + 1 + i
    local isBuy = (t.type == "buy")
    writeText(px + 2, yy, isBuy and "BUY" or "SELL", isBuy and C.green or C.red, C.panel)
    writeText(px + 6, yy, clip(t.player or "?", 12), C.text, C.panel)
    writeText(px + 20, yy, clip(t.item or "?", pw - 28), C.muted, C.panel)
    writeRight(px + 1, yy, pw, tostring(math.floor(tonumber(t.qty) or 0)), C.white, C.panel)
  end
  if #rc == 0 then writeText(px + 2, py + 2, "Нет данных", C.dim, C.panel) end
end

-- ============================================================
-- ФУТЕР (слева, ближе к краю)
-- ============================================================
local function drawFooter()
  fillRect(1, H, W, 1, C.panel2)
  local showToast = toastText ~= "" and computer.uptime() <= toastUntil
  if showToast then
    writeText(2, H, clip(toastText, W - 2), toastColor, C.panel2)
  else
    -- Рисуем сплошную полосу из дефисов по всей ширине
    writeText(1, H, string.rep("-", W), C.accent, C.panel2)
    -- Поверх неё выводим текст с 4-го символа
    local text = "| By " .. AUTHOR .. " | " .. VERSION .. " |"
    writeText(4, H, clip(text, W - 5), C.accent2, C.panel2)
  end
end

-- ============================================================
-- ПОЛНАЯ ОТРИСОВКА
-- ============================================================
local function drawAll()
  local d = view or {}

  if not firstDrawDone then
    gpu.setBackground(C.bg); gpu.setForeground(C.text)
    gpu.fill(1, 1, W, H, " ")
    firstDrawDone = true
  end

  -- ШАПКА
  fillRect(1, 1, W, 7, C.band)
  drawLogo(3, 2)
  writeText(32, 3, "MARKET STATISTICS", C.accent2, C.band)
  writeText(32, 5, "рейтинг игроков • экономика • активность", C.muted, C.band)
  local online = lastDataAt > 0 and (computer.uptime() - lastDataAt) < 45
  local bcol = online and C.green or C.red
  writeText(W - 14, 3, online and "● ONLINE" or "● OFFLINE", bcol, C.band)
  writeText(W - 23, 6, currentTimeStr(), C.muted, C.band)
  fillRect(1, 8, W, 1, C.bg)

  -- KPI
  local kpiY = 9
  local kpiH = 5
  local colGap = 1
  local colW = math.floor((W - 3 - colGap * 3) / 4)
  if colW < 10 then colW = math.floor((W - 4) / 4) end
  local function kpiX(i) return 1 + (i - 1) * (colW + colGap) end
  drawKpi(kpiX(1), kpiY, colW, kpiH, "◉", "ИГРОКОВ", d.totalPlayers or 0, "всего", C.accent)
  drawKpi(kpiX(2), kpiY, colW, kpiH, "≡", "ТРАНЗАКЦИЙ", d.txTotal or 0, "сегодня: " .. tostring(d.txToday or 0), C.orange)
  drawKpi(kpiX(3), kpiY, colW, kpiH, "☄", "COINA", d.coinTotal or 0, "в обращении", C.coin, 1)
  drawKpi(kpiX(4), kpiY, colW, kpiH, "⛭", "EMA", d.emaTotal or 0, "в обращении", C.ema, 1)

  -- ДИНАМИЧЕСКАЯ РАСКЛАДКА 3x3
  local contentTop = kpiY + kpiH + 1
  local availableH = H - 1 - contentTop
  local rowH = math.floor((availableH - 2) / 3)
  if rowH < 7 then rowH = 7 end
  if rowH > 10 then rowH = 10 end

  local row1Y = contentTop
  local row2Y = row1Y + rowH + 1
  local row3Y = row2Y + rowH + 1
  local row3H = H - row3Y

  local col3W = math.floor((W - 4) / 3)
  local function col3X(i) return 1 + (i - 1) * (col3W + 1) end

  -- ROW 1: COIN | EMA | VISITS
  drawTopPanel(col3X(1), row1Y, col3W, rowH, "ТОП COIN", C.coin,
    d.topCoin or {}, function(e) return groupNum(e.v or 0, 1) end, C.coin, true)
  drawTopPanel(col3X(2), row1Y, col3W, rowH, "ТОП EMA", C.ema,
    d.topEma or {}, function(e) return groupNum(e.v or 0, 1) end, C.ema, true)
  drawTopPanel(col3X(3), row1Y, col3W, rowH, "ТОП ВИЗИТЫ", C.accent2,
    d.topVisits or {}, function(e) return tostring(math.floor(e.visits or e.value or 0)) end, C.accent2, true)

  -- ROW 2: PURCHASES | SELLS | SPENT
  drawTopPanel(col3X(1), row2Y, col3W, rowH, "ТОП ПОКУПКИ", C.green,
    d.topPurchases or {}, function(e) return tostring(math.floor(e.purchases or e.value or 0)) end, C.green, true)
  drawTopPanel(col3X(2), row2Y, col3W, rowH, "ТОП ПРОДАЖИ", C.accent,
    d.topSells or {}, function(e) return tostring(math.floor(e.sells or e.value or 0)) end, C.accent, true)
  
  -- ТОП ТРАТЫ (исправлено: пробел вместо | и иконки)
  drawTopPanel(col3X(3), row2Y, col3W, rowH, "ТОП ТРАТЫ", C.orange,
    d.topSpent or {},
    function(e)
      local c, em = e.spentCoin or 0, e.spentEma or 0
      local parts = {}
      if c > 0 then parts[#parts+1] = groupNum(c, 1) .. "☄" end
      if em > 0 then parts[#parts+1] = groupNum(em, 1) .. "⛭" end
      if #parts == 0 then return "0" end
      return table.concat(parts, " ")
    end, C.orange, true)

  -- ROW 3: NEW PLAYERS | CHART | RECENT OPS
  drawNewPlayers(col3X(1), row3Y, col3W, row3H, d.newPlayers or {})
  drawWeekChart(col3X(2), row3Y, col3W, row3H, d.week or {})
  drawRecent(col3X(3), row3Y, col3W, row3H, d.recent or {})

  -- ФУТЕР
  drawFooter()
end

-- ============================================================
-- СЕТЬ (очередь запросов для предотвращения спама)
-- ============================================================
local function request()
  modem.send(SERVER, 0xffef, serialization.serialize({op = "get_dashboard", limit = 7}))
  local now = computer.uptime()
  if now - lastTopsReqAt >= TOPS_REFRESH and #topRequestsQueue == 0 then
    lastTopsReqAt = now
    topRequestsQueue = {"visits", "purchases", "sells", "spent"}
  end
  lastReqAt = now
end

local function handleModem(from, raw)
  if from ~= SERVER then return end
  local ok, msg = pcall(serialization.unserialize, raw)
  if not ok or type(msg) ~= "table" then return end
  if msg.op == "dashboard_data" then
    local oldVisits = view and view.topVisits
    local oldPurchases = view and view.topPurchases
    local oldSells = view and view.topSells
    local oldSpent = view and view.topSpent

    view = msg
    view.topVisits = oldVisits or view.topVisits
    view.topPurchases = oldPurchases or view.topPurchases
    view.topSells = oldSells or view.topSells
    view.topSpent = oldSpent or view.topSpent

    dashEver = true
    if msg.time then
      local ts = parseServerTime(msg.time)
      if ts then
        timeBaseServer = ts
        timeBaseUptime = computer.uptime()
      end
    end
    lastDataAt = computer.uptime()
    needsRedraw = true
  elseif msg.op == "top_data" then
    if not view then view = {} end
    if msg.category == "visits" then view.topVisits = msg.list or {}
    elseif msg.category == "purchases" then view.topPurchases = msg.list or {}
    elseif msg.category == "sells" then view.topSells = msg.list or {}
    elseif msg.category == "spent" then view.topSpent = msg.list or {} end
    lastDataAt = computer.uptime()
    needsRedraw = true
  end
end

-- ============================================================
-- КЛАВИШИ (БЕЗ ЯВНОГО drawAll, ТОЛЬКО ФЛАГ)
-- ============================================================
local function handleKey(char, code, pname)
  if not samePlayerName(pname or "", OWNER) then return end
  if char == 7 and code == 34 then
    -- Ctrl + G
    if fs.exists("/home/update.lua") then
      toast("⚙ Запускаю update.lua...", C.accent2, 2)
      pcall(function() os.execute("/home/update.lua") end)
      toast("✅ update.lua завершил работу", C.green, 3)
    else
      toast("❌ Файл /home/update.lua не найден", C.red, 3)
    end
  elseif char == 8 and code == 35 then
    -- Ctrl + H
    local on = not autorunEnabled()
    setAutorun(on)
    toast(on and "✅ Автозапуск stats.lua ВКЛЮЧЕН (.shrc)" or "⚠ Автозапуск stats.lua ВЫКЛЮЧЕН (.shrc)",
      on and C.green or C.yellow, 4)
  elseif char == 18 and code == 19 then
    -- Ctrl + R (Перезагрузка ПК)
    toast("🔄 Перезагрузка компьютера...", C.orange, 2)
    os.sleep(1)
    computer.shutdown(true)
  end
end

-- ============================================================
-- ГЛАВНЫЙ ЦИКЛ
-- ============================================================
local function main()
  drawAll()
  request()
  while true do
    local timeout = (#topRequestsQueue > 0) and 0.05 or 1
    local ev = {pcall(event.pull, timeout)}
    if ev[1] and ev[2] then
      local e = ev[2]
      if e == "modem_message" then
        handleModem(ev[4], ev[7])
      elseif e == "key_down" then
        handleKey(ev[4], ev[5], ev[6])
      elseif e == "screen_resized" then
        W, H = gpu.maxResolution()
        firstDrawDone = false
        needsRedraw = true
      end
    end
    local now = computer.uptime()

    if needsRedraw then
      drawAll()
      needsRedraw = false
    end

    if now - lastReqAt >= REFRESH then request() end

    if #topRequestsQueue > 0 and now >= nextTopRequestAt then
      local cat = table.remove(topRequestsQueue, 1)
      modem.send(SERVER, 0xffef, serialization.serialize({op = "get_top", category = cat, page = 1, perPage = 10}))
      nextTopRequestAt = now + 0.2
    end

    local clock = currentTimeStr()
    if clock ~= lastClock then
      lastClock = clock
      writeText(W - 23, 6, clock, C.muted, C.band)
      local online = lastDataAt > 0 and (now - lastDataAt) < 45
      writeText(W - 14, 3, online and "● ONLINE" or "● OFFLINE",
        online and C.green or C.red, C.band)
    end

    if toastText ~= "" and now > toastUntil then
      toastText = ""
      drawFooter()
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
