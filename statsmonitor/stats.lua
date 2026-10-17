-- ============================================================
-- STATS.LUA v1.0 — ОТДЕЛЬНЫЙ ЭКРАН СТАТИСТИКИ МАГАЗИНА
-- + логотип PI SHOP (вместо QQ), стиль как на референсе
-- + ВСЕ данные с сервера pimserver (op get_dashboard,
--   запасной режим — get_top, если сервер без вставки)
-- + Ctrl+G — ТОЛЬКО владелец: запуск /home/update.lua
-- + Ctrl+H — ТОЛЬКО владелец: автозапуск stats.lua (.shrc)
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
  bg = 0x0B1018, band = 0x141B26, panel = 0x101823, panel2 = 0x172334,
  cyan = 0x00B6FF, cyan2 = 0x35D0BA,
  yellow = 0xFFD166, magenta = 0xC792EA, green = 0x55E98D,
  orange = 0xFF9F43, red = 0xFF6262,
  white = 0xF2F6FA, text = 0xD7E2EC, muted = 0x8DA2B5, dim = 0x39424E,
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
  if y < 1 or y > H or x > W then return end
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
local function borderRect(x, y, w, h, color, bg)
  bg = bg or C.panel
  gpu.setForeground(color); gpu.setBackground(bg)
  gpu.set(x, y, "┌" .. string.rep("─", math.max(0, w - 2)) .. "┐")
  for i = 1, h - 2 do
    gpu.set(x, y + i, "│")
    gpu.set(x + w - 1, y + i, "│")
  end
  gpu.set(x, y + h - 1, "└" .. string.rep("─", math.max(0, w - 2)) .. "┘")
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

-- реальное время (tmpfs-трюк)
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
-- АВТОЗАПУСК (.shrc) — ТОЛЬКО ВЛАДЕЛЕЦ (Ctrl+H)
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
view = nil            -- данные дашборда с сервера
lastDataAt = 0        -- когда получили данные
lastReqAt = -100      -- когда запрашивали
dashEver = false      -- приходил ли get_dashboard хоть раз
toastText, toastColor, toastUntil = "", C.muted, 0
lastClock = ""

local function toast(t, c, s)
  toastText, toastColor, toastUntil = tostring(t or ""), c or C.muted, computer.uptime() + (s or 3)
end

-- ============================================================
-- ЛОГОТИП PI SHOP (3x5)
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
  gpu.setForeground(C.white); gpu.setBackground(C.band)
  for ci = 1, ulen(word) do
    local g = BIG[unicode.sub(word, ci, ci)]
    if g then
      for r = 1, 5 do
        gpu.set(x + (ci - 1) * 4, y + r - 1, g[r])
      end
    end
  end
end

-- ============================================================
-- ПАНЕЛИ
-- ============================================================
local function rankColor(i)
  if i == 1 then return C.yellow end
  if i == 2 then return C.white end
  if i == 3 then return C.orange end
  return C.text
end

local function panelHead(x, y, w, title, color, headers)
  fillRect(x, y, w, 1, C.panel)
  borderRect(x, y, w, 1, color, C.panel) -- заглушка не нужна; рамка ниже
  writeText(x + 2, y, "▪ " .. title, color, C.panel)
end

local function drawPanelBox(x, y, w, h, title, color)
  fillRect(x, y, w, h, C.panel)
  borderRect(x, y, w, h, color, C.panel)
  writeText(x + 2, y + 1, "▪ " .. title, color, C.panel)
  fillRect(x + 1, y + 2, w - 2, 1, C.panel2)
  return y + 3 -- первая строка данных
end

local function drawCard(x, y, w, h, icon, label, value, sub, color, dec)
  fillRect(x, y, w, h, C.panel)
  borderRect(x, y, w, h, color, C.panel)
  writeText(x + 2, y + 1, icon .. " " .. label, color, C.panel)
  local val = groupNum(value, dec or 0)
  writeText(x + math.max(1, math.floor((w - ulen(val)) / 2)), y + 2, val, C.white, C.panel)
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
  fillRect(1, 1, W, 7, C.band)
  drawLogo(3, 2)
  writeText(3, 7 - 0, "MARKET STATISTICS", C.cyan, C.band)
  writeText(20, 7, "Рейтинг игроков  •  экономика  •  активность", C.muted, C.band)
  local online = lastDataAt > 0 and (computer.uptime() - lastDataAt) < 45
  writeText(W - 11, 2, online and "● ONLINE" or "● OFFLINE", online and C.green or C.red, C.band)
  local shades = {0x00B6FF, 0x2FA8E0, 0x2C8FBF, 0x1F6F8F, 0x1F5F7F}
  for i = 1, 5 do
    gpu.setBackground(shades[i])
    gpu.fill(W - 57 + (i - 1) * 11, 4, 9, 1, " ")
  end
  writeText(W - 21, 6, currentTimeStr(), C.muted, C.band)
  gpu.setBackground(C.cyan); gpu.fill(2, 9, W - 4, 1, " ")

  -- КАРТОЧКИ
  local cardsY = 11
  local cw = math.floor((W - 4 - 8) / 5)
  drawCard(2 + 0 * (cw + 2), cardsY, cw, 5, "◉", "ИГРОКОВ", d.totalPlayers or 0, "Всего на сервере", C.cyan)
  drawCard(2 + 1 * (cw + 2), cardsY, cw, 5, "▲", "АКТИВНЫХ", d.activePlayers or 0, "Активных игроков", C.green)
  drawCard(2 + 2 * (cw + 2), cardsY, cw, 5, "≡", "ТРАНЗАКЦИЙ", d.txTotal or 0, "Сегодня: " .. tostring(d.txToday or 0), C.orange)
  drawCard(2 + 3 * (cw + 2), cardsY, cw, 5, "☄", "COINA", d.coinTotal or 0, "В обращении", C.yellow, 1)
  drawCard(2 + 4 * (cw + 2), cardsY, cw, 5, "⛭", "EMA", d.emaTotal or 0, "В обращении", C.magenta, 1)

  -- РАСКЛАДКА ПАНЕЛЕЙ
  local row2Y = cardsY + 7
  local avail = (H - 3) - row2Y
  local row2H = math.floor((avail - 2) / 2)
  local row3H = avail - 2 - row2H
  local row3Y = row2Y + row2H + 2
  local pw = math.floor((W - 4 - 4) / 3)
  local x1, x2, x3 = 2, 2 + pw + 2, 2 + 2 * (pw + 2)

  -- ТОП COINA
  local ry = drawPanelBox(x1, row2Y, pw, row2H, "ТОП COINA", C.yellow)
  writeText(x1 + 2, ry - 1, "#", C.muted, C.panel2)
  writeText(x1 + 5, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeRight(x1, ry - 1, pw, "COINA", C.muted, C.panel2)
  local tc = d.topCoin or {}
  for i = 1, math.min(#tc, row2H - 4) do
    local yy = ry + i - 1
    writeText(x1 + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(x1 + 5, yy, clip(tc[i].name, pw - 20), rankColor(i), C.panel)
    writeRight(x1, yy, pw, groupNum(tc[i].v, 1), rankColor(i), C.panel)
  end
  if #tc == 0 then writeText(x1 + 2, ry + 1, "Нет данных", C.dim, C.panel) end

  -- ТОП EMA
  ry = drawPanelBox(x2, row2Y, pw, row2H, "ТОП EMA", C.magenta)
  writeText(x2 + 2, ry - 1, "#", C.muted, C.panel2)
  writeText(x2 + 5, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeRight(x2, ry - 1, pw, "EMA", C.muted, C.panel2)
  local te = d.topEma or {}
  for i = 1, math.min(#te, row2H - 4) do
    local yy = ry + i - 1
    writeText(x2 + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(x2 + 5, yy, clip(te[i].name, pw - 20), rankColor(i), C.panel)
    writeRight(x2, yy, pw, groupNum(te[i].v, 1), rankColor(i), C.panel)
  end
  if #te == 0 then writeText(x2 + 2, ry + 1, "Нет данных", C.dim, C.panel) end

  -- НОВЫЕ ИГРОКИ
  ry = drawPanelBox(x3, row2Y, pw, row2H, "НОВЫЕ ИГРОКИ", C.cyan)
  writeText(x3 + 2, ry - 1, "#", C.muted, C.panel2)
  writeText(x3 + 5, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeRight(x3, ry - 1, pw, "ДАТА", C.muted, C.panel2)
  local np = d.newPlayers or {}
  for i = 1, math.min(#np, row2H - 4) do
    local yy = ry + i - 1
    writeText(x3 + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(x3 + 5, yy, clip(np[i].name, pw - 18), rankColor(i), C.panel)
    writeRight(x3, yy, pw, clip(tostring(np[i].date or ""):sub(1, 10), 10), C.text, C.panel)
  end
  if #np == 0 then writeText(x3 + 2, ry + 1, "Нет данных", C.dim, C.panel) end

  -- ТОП АКТИВНОСТЬ
  ry = drawPanelBox(x1, row3Y, pw, row3H, "ТОП АКТИВНОСТЬ", C.green)
  writeText(x1 + 2, ry - 1, "#", C.muted, C.panel2)
  writeText(x1 + 5, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeRight(x1, ry - 1, pw, "ОПЕРАЦИЙ", C.muted, C.panel2)
  local to = d.topOps or {}
  for i = 1, math.min(#to, row3H - 4) do
    local yy = ry + i - 1
    writeText(x1 + 2, yy, tostring(i), rankColor(i), C.panel)
    writeText(x1 + 5, yy, clip(to[i].name, pw - 16), rankColor(i), C.panel)
    writeRight(x1, yy, pw, tostring(math.floor(to[i].v or 0)), rankColor(i), C.panel)
  end
  if #to == 0 then writeText(x1 + 2, ry + 1, "Нет данных", C.dim, C.panel) end

  -- АКТИВНОСТЬ 7 ДНЕЙ
  ry = drawPanelBox(x2, row3Y, pw, row3H, "АКТИВНОСТЬ 7 ДНЕЙ", C.cyan2)
  writeText(x2 + 2, ry - 1, "ДАТА", C.muted, C.panel2)
  writeText(x2 + 9, ry - 1, "АКТИВНОСТЬ", C.muted, C.panel2)
  writeRight(x2, ry - 1, pw, "КОЛ-ВО", C.muted, C.panel2)
  local wk = d.week or {}
  local maxOps = 1
  for _, w in ipairs(wk) do if (w.ops or 0) > maxOps then maxOps = w.ops end end
  local barW = pw - 20
  for i = 1, math.min(#wk, row3H - 4) do
    local yy = ry + i - 1
    writeText(x2 + 2, yy, clip(wk[i].date, 5), C.text, C.panel)
    local filled = math.floor(barW * ((wk[i].ops or 0) / maxOps))
    gpu.setBackground(C.cyan); gpu.fill(x2 + 9, yy, filled, 1, " ")
    gpu.setBackground(C.dim); gpu.fill(x2 + 9 + filled, yy, barW - filled, 1, " ")
    writeRight(x2, yy, pw, tostring(wk[i].ops or 0), C.text, C.panel)
  end
  if #wk == 0 then writeText(x2 + 2, ry + 1, "Нет данных", C.dim, C.panel) end

  -- ПОСЛЕДНИЕ ОПЕРАЦИИ
  ry = drawPanelBox(x3, row3Y, pw, row3H, "ПОСЛЕДНИЕ ОПЕРАЦИИ", C.orange)
  writeText(x3 + 2, ry - 1, "#", C.muted, C.panel2)
  writeText(x3 + 5, ry - 1, "ТИП", C.muted, C.panel2)
  writeText(x3 + 11, ry - 1, "ИГРОК", C.muted, C.panel2)
  writeText(x3 + 25, ry - 1, "ПРЕДМЕТ", C.muted, C.panel2)
  writeRight(x3, ry - 1, pw, "КОЛ-ВО", C.muted, C.panel2)
  local rc = d.recent or {}
  for i = 1, math.min(#rc, row3H - 4) do
    local yy = ry + i - 1
    local t = rc[i]
    local isBuy = (t.type == "buy")
    writeText(x3 + 2, yy, tostring(i), C.muted, C.panel)
    writeText(x3 + 5, yy, isBuy and "BUY" or "SELL", isBuy and C.green or C.red, C.panel)
    writeText(x3 + 11, yy, clip(t.player, 12), C.text, C.panel)
    writeText(x3 + 25, yy, clip(t.item, pw - 34), C.text, C.panel)
    writeRight(x3, yy, pw, tostring(math.floor(tonumber(t.qty) or 0)), C.white, C.panel)
  end
  if #rc == 0 then writeText(x3 + 2, ry + 1, "Нет данных", C.dim, C.panel) end

  -- ФУТЕР
  fillRect(1, H - 1, W, 1, C.panel2)
  gpu.setForeground(C.cyan); gpu.setBackground(C.panel2)
  gpu.set(1, H - 1, string.rep("─", W))
  local left = toastText ~= "" and computer.uptime() <= toastUntil and toastText
    or ("Обновление каждые " .. REFRESH .. " сек | источник: pimserver")
  writeText(2, H - 1, clip(left, W - 30), toastText ~= "" and computer.uptime() <= toastUntil and toastColor or C.muted, C.panel2)
  writeRight(1, H - 1, W, "[ " .. OWNER .. " ]  [ stats v1.0 ]", C.cyan, C.panel2)
  fillRect(1, H, W, 1, C.bg)
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
    v.totalPlayers = topBalance.total or #topBalance.list or 0
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
-- ============================================================
local function handleKey(char, code, pname)
  if not samePlayerName(pname, OWNER) then return end
  if char == 7 and code == 34 then
    -- Ctrl+G: обновление
    if fs.exists("/home/update.lua") then
      toast("⚙ Запускаю update.lua...", C.cyan, 2)
      drawAll()
      os.execute("/home/update.lua")
      drawAll()
      toast("update.lua завершил работу", C.muted, 3)
    else
      toast("❌ Файл /home/update.lua не найден", C.red, 3)
    end
    drawAll()
  elseif char == 8 and code == 35 then
    -- Ctrl+H: автозапуск
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
      -- точечно обновляем часы и статус, без полной перерисовки
      writeText(W - 21, 6, currentTimeStr(), C.muted, C.band)
      local online = lastDataAt > 0 and (now - lastDataAt) < 45
      writeText(W - 11, 2, online and "● ONLINE" or "● OFFLINE", online and C.green or C.red, C.band)
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
