-- ============================================================
-- STATS.LUA v2.0 — НОВЫЙ GUI ЭКРАНА СТАТИСТИКИ
-- + тема "фиолетовый карбон" в стиль PI SHOP (двойные рамки)
-- + KPI-карточки с цветными шапками
-- + ВЕРТИКАЛЬНЫЙ график активности за 7 дней
-- + бегущая строка последних операций внизу
-- + ONLINE-бейдж и часы в шапке
-- + данные с pimserver (get_dashboard, фолбэк get_top)
-- + Ctrl+G / Ctrl+H — ТОЛЬКО владелец
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

-- НОВАЯ ПАЛИТРА
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
-- двойная рамка
local function dbox(x, y, w, h, color)
  fillRect(x, y, w, h, C.panel)
  gpu.setForeground(color); gpu.setBackground(C.panel)
  gpu.set(x, y, "╔" .. string.rep("═", math.max(0, w - 2)) .. "╗")
  for i = 1, h - 2 do
    gpu.set(x, y + i, "║")
    gpu.set(x + w - 1, y + i, "║")
  end
  gpu.set(x, y + h - 1, "╚" .. string.rep("═", math.max(0, w - 2)) .. "╝")
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
tickerText = ""
tickerPos = 0

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
        -- тень + символ
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

-- панель: двойная рамка + заголовок + строка-шапка таблицы
local function drawPanelBox(x, y, w, h, title, color)
  dbox(x, y, w, h, color)
  writeText(x + 2, y + 1, "▪ " .. title, color, C.panel)
  fillRect(x + 1, y + 2, w - 2, 1, C.panel2)
  return y + 3
end

-- KPI-карточка с цветной шапкой
local function drawKpi(x, y, w, h, icon, label, value, sub, color, dec)
  dbox(x, y, w, h, color)
  fillRect(x + 1, y + 1, w - 2, 1, color)
  writeText(x + 2, y + 1, icon .. " " .. label, C.bg, color)
  local val = groupNum(value, dec or 0)
  writeText(x + math.max(1, math.floor((w - ulen(val)) / 2)), y + 3, val, C.white, C.panel)
  writeText(x + math.max(1, math.floor((w - ulen(tostring(sub))) / 2)), y + h - 2, tostring(sub), C.muted, C.panel)
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
  -- ONLINE-бейдж
  local online = lastDataAt > 0 and (computer.uptime() - lastDataAt) < 45
  local bcol = online and C.green or C.red
  dbox(W - 27, 2, 25, 3, bcol)
  writeText(W - 24, 3, online and "● ONLINE" or "● OFFLINE", bcol, C.panel)
  writeText(W - 27, 6, currentTimeStr(), C.muted, C.band)
  -- разделитель-градиент
  local shades = {0x6A0DAD, 0x7B2CBF, 0x9D4EDD, 0xC792EA, 0x9D4EDD, 0x7B2CBF, 0x6A0DAD}
  for i = 1, W - 4 do
    gpu.setBackground(shades[((i - 1) % #shades) + 1])
    gpu.fill(2 + i - 1, 9, 1, 1, " ")
  end

  -- KPI-КАРТОЧКИ
  local ky = 11
  local cw = math.floor((W - 4 - 8) / 5)
  drawKpi(2 + 0 * (cw + 2), ky, cw, 6, "◉", "ИГРОКОВ", d.totalPlayers or 0, "всего на сервере", C.accent)
  drawKpi(2 + 1 * (cw + 2), ky, cw, 6, "▲", "АКТИВНЫХ", d.activePlayers or 0, "совершали сделки", C.green)
  drawKpi(2 + 2 * (cw + 2), ky, cw, 6, "≡", "ТРАНЗАКЦИЙ", d.txTotal or 0, "сегодня: " .. tostring(d.txToday or 0), C.orange)
  drawKpi(2 + 3 * (cw + 2), ky, cw, 6, "☄", "COINA", d.coinTotal or 0, "в обращении", C.coin, 1)
  drawKpi(2 + 4 * (cw + 2), ky, cw, 6, "⛭", "EMA", d.emaTotal or 0, "в обращении", C.ema, 1)

  -- РАСКЛАДКА
  local row2Y = ky + 8
  local contentBottom = H - 3
  local remain = contentBottom - row2Y
  local row2H = math.floor(remain * 0.46)
  local row3Y = row2Y + row2H + 2
  local row3H = contentBottom - row3Y
  local halfW = math.floor((W - 6) / 2)
  local thirdW = math.floor((W - 8) / 3)

  -- ТОП БАЛАНСА (широкий)
  local ry = drawPanelBox(2, row2Y, halfW, row2H, "ТОП БАЛАНСА", C.accent2)
  writeText(4, ry - 1, "#", C.muted, C.panel2)
  writeText(7, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeRight(2, ry - 1, halfW - 18, "COIN ☄", C.muted, C.panel2)
  writeRight(2, ry - 1, halfW, "EMA ⛭", C.muted, C.panel2)
  local tb = {}
  if d.topCoin and d.topEma then
    -- объединённый рейтинг: coin+ema
    local map = {}
    for _, e in ipairs(d.topCoin or {}) do map[e.name] = (map[e.name] or 0) + (e.v or 0) end
    for _, e in ipairs(d.topEma or {}) do map[e.name] = (map[e.name] or 0) + (e.v or 0) end
    -- coin/ema отдельно для колонок
    local coinV, emaV = {}, {}
    for _, e in ipairs(d.topCoin or {}) do coinV[e.name] = e.v end
    for _, e in ipairs(d.topEma or {}) do emaV[e.name] = e.v end
    local names = {}
    for n in pairs(map) do names[#names + 1] = n end
    table.sort(names, function(a, b) return map[a] > map[b] end)
    for i = 1, math.min(#names, row2H - 4) do
      local yy = ry + i - 1
      local n = names[i]
      writeText(4, yy, tostring(i), rankColor(i), C.panel)
      writeText(7, yy, clip(n, halfW - 34), rankColor(i), C.panel)
      writeRight(2, yy, halfW - 18, groupNum(coinV[n] or 0, 1), C.coin, C.panel)
      writeRight(2, yy, halfW, groupNum(emaV[n] or 0, 1), C.ema, C.panel)
    end
    if #names == 0 then writeText(4, ry + 1, "Нет данных", C.dim, C.panel) end
  else
    writeText(4, ry + 1, "Нет данных", C.dim, C.panel)
  end

  -- НОВЫЕ ИГРОКИ
  ry = drawPanelBox(4 + halfW, row2Y, W - halfW - 4, row2H, "НОВЫЕ ИГРОКИ", C.accent)
  local nw = W - halfW - 4
  writeText(6, ry - 1, "#", C.muted, C.panel2)
  writeText(9, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeRight(4 + halfW, ry - 1, nw, "ДАТА", C.muted, C.panel2)
  local np = d.newPlayers or {}
  for i = 1, math.min(#np, row2H - 4) do
    local yy = ry + i - 1
    writeText(6, yy, tostring(i), rankColor(i), C.panel)
    writeText(9, yy, clip(np[i].name, nw - 20), rankColor(i), C.panel)
    writeRight(4 + halfW, yy, nw, clip(tostring(np[i].date or ""):sub(1, 10), 10), C.text, C.panel)
  end
  if #np == 0 then writeText(6, ry + 1, "Нет данных", C.dim, C.panel) end

  -- ГРАФИК 7 ДНЕЙ (вертикальные столбцы)
  local gx, gw = 2, thirdW
  dbox(gx, row3Y, gw, row3H, C.accent2)
  writeText(gx + 2, row3Y + 1, "▪ АКТИВНОСТЬ 7 ДНЕЙ", C.accent2, C.panel)
  local wk = d.week or {}
  local maxOps = 1
  for _, wki in ipairs(wk) do if (wki.ops or 0) > maxOps then maxOps = wki.ops end end
  local topY = row3Y + 3
  local botY = row3Y + row3H - 3
  local labY = row3Y + row3H - 2
  local maxH = botY - topY
  local colW = math.floor((gw - 4) / 7)
  for i = 1, math.min(7, #wk) do
    local ops = wk[i].ops or 0
    local bh = math.floor(maxH * ops / maxOps)
    if ops > 0 and bh < 1 then bh = 1 end
    local cx = gx + 2 + (i - 1) * colW + math.floor(colW / 2)
    if botY - bh >= topY then
      writeText(cx - 1, botY - bh, tostring(ops), C.text, C.panel)
    end
    for r = 1, bh do
      writeText(cx, botY - bh + r, "█", (r == bh) and C.accent2 or C.accent, C.panel)
    end
    writeText(gx + 2 + (i - 1) * colW, labY, clip(wk[i].date or "", colW - 1), C.muted, C.panel)
  end
  if #wk == 0 then writeText(gx + 2, topY, "Нет данных", C.dim, C.panel) end

  -- ТОП АКТИВНОСТЬ
  local ax, aw = 4 + thirdW, thirdW
  ry = drawPanelBox(ax, row3Y, aw, row3H, "ТОП АКТИВНОСТЬ", C.green)
  writeText(ax + 2, ry - 1, "#", C.muted, C.panel2)
  writeText(ax + 5, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeRight(ax, ry - 1, aw, "ОПЕРАЦИЙ", C.muted, C.panel2)
  local to = d.topOps or {}
  for i = 1, math.min(#to, row3H - 4) do
    local yy = ry + i - 1
    writeText(ax + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(ax + 5, yy, clip(to[i].name, aw - 16), rankColor(i), C.panel)
    writeRight(ax, yy, aw, tostring(math.floor(to[i].v or 0)), rankColor(i), C.panel)
  end
  if #to == 0 then writeText(ax + 2, ry + 1, "Нет данных", C.dim, C.panel) end

  -- ПОСЛЕДНИЕ ОПЕРАЦИИ
  local rx, rw = 6 + 2 * thirdW, W - rx - 1
  ry = drawPanelBox(rx, row3Y, rw, row3H, "ПОСЛЕДНИЕ ОПЕРАЦИИ", C.orange)
  writeText(rx + 2, ry - 1, "Т", C.muted, C.panel2)
  writeText(rx + 5, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeText(rx + 18, ry - 1, "ПРЕДМЕТ", C.muted, C.panel2)
  writeRight(rx, ry - 1, rw, "КОЛ-ВО", C.muted, C.panel2)
  local rc = d.recent or {}
  for i = 1, math.min(#rc, row3H - 4) do
    local yy = ry + i - 1
    local t = rc[i]
    local isBuy = (t.type == "buy")
    writeText(rx + 2, yy, isBuy and "↓" or "↑", isBuy and C.green or C.red, C.panel)
    writeText(rx + 5, yy, clip(t.player, 11), C.text, C.panel)
    writeText(rx + 18, yy, clip(t.item, rw - 26), C.muted, C.panel)
    writeRight(rx, yy, rw, tostring(math.floor(tonumber(t.qty) or 0)), C.white, C.panel)
  end
  if #rc == 0 then writeText(rx + 2, ry + 1, "Нет данных", C.dim, C.panel) end

  -- ФУТЕР С БЕГУЩЕЙ СТРОКОЙ
  fillRect(1, H - 1, W, 1, C.panel2)
  gpu.setForeground(C.border); gpu.setBackground(C.panel2)
  gpu.set(1, H - 1, string.rep("═", W))
  local vw = W - 30
  local line = ""
  if tickerText ~= "" then
    local tl = ulen(tickerText)
    if tickerPos > tl then tickerPos = 0 end
    line = unicode.sub(tickerText, tickerPos + 1, tickerPos + vw)
    if ulen(line) < vw then
      line = line .. unicode.sub(tickerText, 1, vw - ulen(line))
    end
  end
  local showToast = toastText ~= "" and computer.uptime() <= toastUntil
  writeText(2, H - 1, clip(showToast and toastText or line, vw), showToast and toastColor or C.text, C.panel2)
  writeRight(1, H - 1, W, "[ " .. OWNER .. " ] [ stats v2.0 ]", C.accent2, C.panel2)
  fillRect(1, H, W, 1, C.bg)
end

-- ============================================================
-- СЕТЬ
-- ============================================================
local function buildTicker()
  local d = view or {}
  local parts = {}
  for _, t in ipairs(d.recent or {}) do
    parts[#parts + 1] = string.format("%s %s: %s x%s",
      (t.type == "buy") and "ПОКУПКА" or "ПРОДАЖА",
      tostring(t.player or "?"), tostring(t.item or "?"),
      tostring(math.floor(tonumber(t.qty) or 0)))
  end
  if #parts == 0 then parts[1] = "Ожидание данных с сервера..." end
  tickerText = "   •••   " .. table.concat(parts, "   |   ") .. "   "
end

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
    local active, tx, byOps = 0, 0, {}
    for _, e in ipairs(topPurchases.list or {}) do
      local ops = (e.purchases or 0) + (e.sells or 0)
      tx = tx + ops
      if ops > 0 then active = active + 1 end
      byOps[#byOps + 1] = {name = e.name, v = ops}
    end
    v.activePlayers, v.txTotal = active, tx
    table.sort(byOps, function(a, b) return a.v > b.v end)
    v.topOps = byOps
  end
  v.newPlayers = v.newPlayers or {}
  v.week = v.week or {}
  v.recent = v.recent or {}
  view = v
  buildTicker()
end

local function handleModem(from, raw)
  if from ~= SERVER then return end
  local ok, msg = pcall(serialization.unserialize, raw)
  if not ok or type(msg) ~= "table" then return end
  if msg.op == "dashboard_data" then
    view = msg
    dashEver = true
    lastDataAt = computer.uptime()
    buildTicker()
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
-- ============================================================
local function handleKey(char, code, pname)
  if not samePlayerName(pname, OWNER) then return end
  if char == 7 and code == 34 then
    if fs.exists("/home/update.lua") then
      toast("⚙ Запускаю update.lua...", C.accent2, 2)
      drawAll()
      os.execute("/home/update.lua")
      drawAll()
      toast("update.lua завершил работу", C.muted, 3)
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
    if ev[1] then
      local e = ev[2]
      if e == "modem_message" then
        handleModem(ev[4], ev[7])
      elseif e == "key_down" then
        handleKey(ev[3], ev[4], ev[5])
      end
    end
    local now = computer.uptime()
    if now - lastReqAt >= REFRESH then request() end
    local clock = os.date("%H:%M:%S", getRealTimestamp())
    if clock ~= lastClock then
      lastClock = clock
      tickerPos = tickerPos + 2
      -- точечное обновление: часы, бейдж, бегущая строка
      writeText(W - 27, 6, currentTimeStr(), C.muted, C.band)
      local online = lastDataAt > 0 and (now - lastDataAt) < 45
      local bcol = online and C.green or C.red
      writeText(W - 24, 3, online and "● ONLINE" or "● OFFLINE", bcol, C.panel)
      local vw = W - 30
      local line = ""
      if tickerText ~= "" then
        local tl = ulen(tickerText)
        if tickerPos > tl then tickerPos = 0 end
        line = unicode.sub(tickerText, tickerPos + 1, tickerPos + vw)
        if ulen(line) < vw then
          line = line .. unicode.sub(tickerText, 1, vw - ulen(line))
        end
      end
      local showToast = toastText ~= "" and computer.uptime() <= toastUntil
      writeText(2, H - 1, clip(showToast and toastText or line, vw), showToast and toastColor or C.text, C.panel2)
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
