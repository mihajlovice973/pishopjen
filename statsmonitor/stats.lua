-- ============================================================
-- STATS.LUA v1.6 — HIDE OWNER FROM LISTS
-- + Убран KaRMa__ из всех списков (ТОПы, новые, операции)
-- + Оставлен By KaRMa__ в футере
-- + Добавлена ustr_width() для расчета реальной ширины (1 или 2 клетки)
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
local VERSION = "v1.6"
local AUTORUN_LINE = "lua /home/stats.lua"
local RC_PATHS = {"/home/.shrc", "/.shrc"}
local REFRESH_RATE = 15
local TOPS_REFRESH = 60
local TOPS_RETRY = 10
local TOP_STEP_DELAY = 0.15
local OFFLINE_AFTER = 70
local FILE_TS_TTL = 30

local C = {
  bg = 0x0D0B14, band = 0x150F22, panel = 0x171322, panel2 = 0x201A2E,
  border = 0x6A0DAD, accent = 0x9D4EDD, accent2 = 0xC792EA,
  coin = 0xFFCE7A, ema = 0x7FB6FF,
  green = 0x00D9A3, red = 0xFF4D6D, orange = 0xFF9F43, yellow = 0xFFD166,
  white = 0xF2F0F8, text = 0xD9D2EA, muted = 0x8A7FA8, dim = 0x3A3350,
  gold = 0xFFD700, silver = 0xC0C0C0, bronze = 0xCD7F32,
}

local W, H = gpu.maxResolution()
pcall(gpu.setResolution, W, H)

-- КЭШ ЦВЕТОВ
local _lastFg, _lastBg = -1, -1
local function setFg(c) if c ~= _lastFg then gpu.setForeground(c); _lastFg = c end end
local function setBg(c) if c ~= _lastBg then gpu.setBackground(c); _lastBg = c end end

-- БАЗОВЫЕ ХЕЛПЕРЫ
local function ulen(t) return unicode.len(tostring(t or "")) end

local function ustr_width(s)
  s = tostring(s or "")
  local w = 0
  for i = 1, unicode.len(s) do
    local c = unicode.sub(s, i, i)
    local cw = unicode.charWidth(c)
    if cw then w = w + cw else w = w + 1 end
  end
  return w
end

local function clip(t, w)
  t = tostring(t or "")
  if w <= 0 then return "" end
  if ustr_width(t) <= w then return t end
  local targetW = w - 1
  local out = ""
  local currentW = 0
  for i = 1, unicode.len(t) do
    local c = unicode.sub(t, i, i)
    local cw = unicode.charWidth(c) or 1
    if currentW + cw > targetW then break end
    out = out .. c
    currentW = currentW + cw
  end
  return out .. "…"
end

local function writeText(x, y, t, fg, bg)
  if y < 1 or y > H or x < 1 or x > W then return end
  t = tostring(t or "")
  if t == "" then return end
  local tw = ustr_width(t)
  if x + tw - 1 > W then
    t = clip(t, W - x + 1)
    tw = ustr_width(t)
    if tw == 0 then return end
  end
  if bg then setBg(bg) end
  if fg then setFg(fg) end
  gpu.set(x, y, t)
end

local function writeRight(x, y, w, t, fg, bg)
  t = tostring(t or "")
  local maxW = w - 3
  if maxW < 1 then return end
  if ustr_width(t) > maxW then t = clip(t, maxW) end
  local tw = ustr_width(t)
  if tw == 0 then return end
  local xx = x + w - 2 - tw
  if xx < x + 1 then xx = x + 1 end
  if xx + tw - 1 > W then
    t = clip(t, W - xx + 1)
    tw = ustr_width(t)
    if tw == 0 then return end
  end
  writeText(xx, y, t, fg, bg)
end

local function fillRect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  if x < 1 then w = w + (x - 1); x = 1 end
  if y < 1 then h = h + (y - 1); y = 1 end
  if x > W or y > H then return end
  if x + w - 1 > W then w = W - x + 1 end
  if y + h - 1 > H then h = H - y + 1 end
  if w <= 0 or h <= 0 then return end
  setBg(bg); gpu.fill(x, y, w, h, " ")
end

-- ФОРМАТИРОВАНИЕ
local function groupNum(n, dec)
  dec = dec or 0
  local num = tonumber(n)
  if not num or num ~= num or num == math.huge or num == -math.huge then num = 0 end
  local fmt = string.format("%." .. dec .. "f", num)
  local int, frac = fmt:match("^([^%.]+)(%.?.*)$")
  if not int then return fmt end
  local sign = ""
  if int:sub(1, 1) == "-" then sign = "-"; int = int:sub(2) end
  local out = ""
  while #int > 3 do out = "," .. int:sub(-3) .. out; int = int:sub(1, #int - 3) end
  return sign .. int .. out .. (frac or "")
end
local function trimName(s) return tostring(s or ""):match("^%s*(.-)%s*$") or "" end
local function samePlayerName(a, b)
  a, b = trimName(a), trimName(b)
  return a ~= "" and b ~= "" and unicode.lower(a) == unicode.lower(b)
end
local function fmtDate(s)
  s = tostring(s or "")
  local d, m, y, hh, mm = s:match("(%d%d)%.(%d%d)%.(%d%d%d%d)%s+(%d%d):(%d%d)")
  if d then return d .. "." .. m .. " " .. hh .. ":" .. mm end
  return clip(s, 14)
end

-- ВРЕМЯ
local tmpfs = component.proxy(computer.tmpAddress())
local _fileTsVal, _fileTsUptime = 0, 0
local function readFileTimestamp()
  local now = computer.uptime()
  if _fileTsVal > 0 and (now - _fileTsUptime) < FILE_TS_TTL then return _fileTsVal + (now - _fileTsUptime) end
  local ok, r = pcall(function()
    local h = tmpfs.open("/time", "w"); if not h then return nil end
    tmpfs.write(h, "time"); tmpfs.close(h)
    local mt = tmpfs.lastModified("/time"); if not mt then return nil end
    return mt / 1000 + 3 * 3600
  end)
  if ok and r then _fileTsVal = r; _fileTsUptime = now; return r end
  return os.time() + 3 * 3600
end
local timeBaseServer = 0
local timeBaseUptime = 0
local function parseServerTime(tstr)
  if not tstr then return nil end
  local d, m, y, hh, mm, ss = tstr:match("(%d%d)%.(%d%d)%.(%d%d%d%d) (%d%d):(%d%d):(%d%d)")
  if not d then return nil end
  local ok, t = pcall(os.time, { year = tonumber(y), month = tonumber(m), day = tonumber(d),
    hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss) })
  return ok and t or nil
end
local function currentTimeSec()
  if timeBaseServer > 0 then return timeBaseServer + (computer.uptime() - timeBaseUptime) end
  return readFileTimestamp()
end
local _lastClockSec = -1
local _lastClockStr = ""
local function currentTimeStr()
  local sec = math.floor(currentTimeSec())
  if sec == _lastClockSec then return _lastClockStr end
  _lastClockSec = sec
  _lastClockStr = os.date("%d.%m.%Y %H:%M:%S", sec)
  return _lastClockStr
end

-- АВТОЗАПУСК
local function readWholeFile(p) local f = io.open(p, "r"); if not f then return nil end; local d = f:read("*a"); f:close(); return d or "" end
local function writeWholeFile(p, t) local f = io.open(p, "w"); if not f then return false end; f:write(t); f:close(); return true end
local function trimLine(s) return s:gsub("^%s+", ""):gsub("%s+$", "") end
local function autorunEnabled()
  for _, p in ipairs(RC_PATHS) do
    local d = readWholeFile(p)
    if d then for line in d:gmatch("[^\n]+") do if trimLine(line) == AUTORUN_LINE then return true end end end
  end
  return false
end
local function setAutorun(on)
  for _, p in ipairs(RC_PATHS) do
    local d = readWholeFile(p)
    if on then
      if d == nil then d = "" end
      local found = false
      for line in d:gmatch("[^\n]+") do if trimLine(line) == AUTORUN_LINE then found = true; break end end
      if not found then
        if d ~= "" and not d:find("\n$") then d = d .. "\n" end
        writeWholeFile(p, d .. AUTORUN_LINE .. "\n")
      end
    else
      if d then
        local out = {}
        for line in d:gmatch("[^\n]+") do if trimLine(line) ~= AUTORUN_LINE then out[#out + 1] = line end end
        writeWholeFile(p, (#out > 0 and table.concat(out, "\n") .. "\n" or ""))
      end
    end
  end
end

-- СОСТОЯНИЕ
local view = {}
local lastDataAt = 0
local lastReqAt = -100
local lastTopsReqAt = -100
local nextTopRequestAt = 0
local topRequestsQueue = {}
local topPending = {}
local toastText, toastColor, toastUntil = "", C.muted, 0
local lastClock = ""
local firstDrawDone = false
local needsRedraw = true
local firstRequestSent = false

local dirty = {
  header = true, kpi = true, coin = true, ema = true, visits = true,
  purchases = true, sells = true, spent = true,
  newp = true, week = true, recent = true, footer = true,
}

local function toast(t, c, s)
  toastText = tostring(t or ""); toastColor = c or C.muted
  toastUntil = computer.uptime() + (s or 3)
  dirty.footer = true; needsRedraw = true
end

-- ОТРИСОВКА
local BIG = {
  P = {"███", "█ █", "███", "█  ", "█  "}, I = {"███", " █ ", " █ ", " █ ", "███"},
  S = {"███", "█  ", "███", "  █", "███"}, H = {"█ █", "█ █", "███", "█ █", "█ █"},
  O = {"███", "█ █", "█ █", "█ █", "███"}, [" "] = {"   ", "   ", "   ", "   ", "   "},
}
local function drawLogo(x, y, fg)
  local word = "PI SHOP"
  for ci = 1, ulen(word) do
    local g = BIG[unicode.sub(word, ci, ci)]
    if g then for r = 1, 5 do writeText(x + (ci - 1) * 4, y + r - 1, g[r], fg or C.accent2, C.band) end end
  end
end
local function rankColor(i)
  if i == 1 then return C.gold end
  if i == 2 then return C.silver end
  if i == 3 then return C.bronze end
  return C.text
end
local function buildTop(w, title)
  if not title or ulen(title) == 0 or w < 8 then return "┌" .. string.rep("─", w - 2) .. "┐" end
  local t = clip(title, math.max(1, w - 6)); local tlen = ustr_width(t)
  local fc = w - 5 - tlen; if fc < 0 then fc = 0 end
  local top = "┌─ " .. t .. " " .. string.rep("─", fc) .. "┐"
  local actual = ustr_width(top)
  if actual < w then top = "┌─ " .. t .. " " .. string.rep("─", fc + (w - actual)) .. "┐"
  elseif actual > w then top = unicode.sub(top, 1, w - 1) .. "┐" end
  return top
end
local function drawBox(x, y, w, h, color, title)
  if w < 4 or h < 3 then return end
  if x + w - 1 > W then w = W - x + 1 end
  if y + h - 1 > H then h = H - y + 1 end
  if w < 4 or h < 3 then return end
  fillRect(x, y, w, h, C.panel)
  writeText(x, y, buildTop(w, title), color, C.panel)
  for i = 1, h - 2 do
    writeText(x, y + i, "│", color, C.panel)
    writeText(x + w - 1, y + i, "│", color, C.panel)
  end
  writeText(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘", color, C.panel)
end
local function drawKpi(x, y, w, h, icon, label, value, sub, color, dec)
  drawBox(x, y, w, h, color, icon .. " " .. label)
  local val = groupNum(value, dec or 0)
  writeText(x + math.max(1, math.floor((w - ustr_width(val)) / 2)), y + 2, val, C.white, C.panel)
  local st = tostring(sub)
  writeText(x + math.max(1, math.floor((w - ustr_width(st)) / 2)), y + h - 2, st, C.muted, C.panel)
end
local function pickNum(e, ...)
  if type(e) ~= "table" then return 0 end
  for i = 1, select("#", ...) do
    local v = e[select(i, ...)]
    if v ~= nil then local n = tonumber(v); if n then return n end end
  end
  return 0
end

local function drawTopPanel(rect, title, color, entries, valueFn, valueColor, ranked)
  local px, py, pw, ph = rect.x, rect.y, rect.w, rect.h
  drawBox(px, py, pw, ph, color, title)
  if pw < 8 or ph < 4 then return end
  writeText(px + 2, py + 1, "#", C.muted, C.panel)
  writeText(px + 4, py + 1, "ИГРОК", C.muted, C.panel)
  writeRight(px + 1, py + 1, pw, "ЗНАЧ", C.muted, C.panel)
  local maxRows = ph - 3; if maxRows <= 0 then return end
  if entries == nil then
    writeText(px + 2, py + 2, "Загрузка...", C.accent2, C.panel); return
  end
  
  -- ФИЛЬТРУЕМ ВЛАДЕЛЬЦА
  local filtered = {}
  for i = 1, #entries do
    local e = entries[i]
    if type(e) == "table" and not samePlayerName(e.name, OWNER) then
      filtered[#filtered + 1] = e
    end
  end

  if #filtered == 0 then
    writeText(px + 2, py + 2, "Нет данных", C.dim, C.panel); return
  end

  for i = 1, math.min(#filtered, maxRows) do
    local e = filtered[i]
    local yy = py + 1 + i
    local rc = (ranked ~= false) and rankColor(i) or C.text
    writeText(px + 2, yy, tostring(i), rc, C.panel)
    writeText(px + 4, yy, clip(e.name or "?", pw - 15), rc, C.panel)
    writeRight(px + 1, yy, pw, valueFn(e), valueColor, C.panel)
  end
end

local function drawNewPlayers(rect, entries)
  local px, py, pw, ph = rect.x, rect.y, rect.w, rect.h
  drawBox(px, py, pw, ph, C.accent, "НОВЫЕ ИГРОКИ")
  if pw < 8 or ph < 4 then return end
  writeText(px + 2, py + 1, "ИГРОК", C.muted, C.panel)
  writeRight(px + 1, py + 1, pw, "ДАТА МСК", C.muted, C.panel)
  local maxRows = ph - 3; if maxRows <= 0 then return end
  if entries == nil then writeText(px + 2, py + 2, "Загрузка...", C.accent2, C.panel); return end
  
  -- ФИЛЬТРУЕМ ВЛАДЕЛЬЦА
  local filtered = {}
  for i = 1, #entries do
    local e = entries[i]
    if type(e) == "table" and not samePlayerName(e.name, OWNER) then
      filtered[#filtered + 1] = e
    end
  end

  if #filtered == 0 then writeText(px + 2, py + 2, "Нет данных", C.dim, C.panel); return end

  for i = 1, math.min(#filtered, maxRows) do
    local e = filtered[i]
    local yy = py + 1 + i
    writeText(px + 2, yy, clip(e.name or "?", pw - 14), C.text, C.panel)
    writeRight(px + 1, yy, pw, fmtDate(e.date), C.muted, C.panel)
  end
end

local function drawWeekChart(rect, entries)
  local px, py, pw, ph = rect.x, rect.y, rect.w, rect.h
  drawBox(px, py, pw, ph, C.accent2, "ПОКУПКИ 7 ДНЕЙ")
  if pw < 8 or ph < 5 then return end
  if entries == nil then writeText(px + 2, py + 2, "Загрузка...", C.accent2, C.panel); return end
  if #entries == 0 then writeText(px + 2, py + 2, "Нет данных", C.dim, C.panel); return end
  local maxOps = 1
  for _, e in ipairs(entries) do local v = e.ops or e.purchases or 0; if v > maxOps then maxOps = v end end
  local chartTop = py + 2; local chartBot = py + ph - 3
  local maxH = math.max(1, chartBot - chartTop)
  local colW = math.max(2, math.floor((pw - 4) / 7))
  for i = 1, math.min(7, #entries) do
    local ops = entries[i].ops or entries[i].purchases or 0
    local bh = math.floor(maxH * ops / maxOps)
    if ops > 0 and bh < 1 then bh = 1 end
    if bh > maxH then bh = maxH end
    local cx = px + 2 + (i - 1) * colW + math.floor((colW - 1) / 2)
    if bh > 0 then writeText(cx, chartBot - bh, tostring(ops), C.text, C.panel) end
    for r = 1, bh do writeText(cx, chartBot - bh + r, "█", (r == bh) and C.accent2 or C.accent, C.panel) end
    writeText(px + 2 + (i - 1) * colW, py + ph - 2, clip(entries[i].date or "", colW), C.muted, C.panel)
  end
end

local function drawRecent(rect, entries)
  local px, py, pw, ph = rect.x, rect.y, rect.w, rect.h
  drawBox(px, py, pw, ph, C.orange, "ПОСЛЕДНИЕ ОПЕРАЦИИ")
  if pw < 12 or ph < 4 then return end
  writeText(px + 2, py + 1, "ОП", C.muted, C.panel)
  writeText(px + 6, py + 1, "ИГРОК", C.muted, C.panel)
  writeText(px + 20, py + 1, "ПРЕДМЕТ", C.muted, C.panel)
  writeRight(px + 1, py + 1, pw, "КОЛ", C.muted, C.panel)
  local maxRows = ph - 3; if maxRows <= 0 then return end
  if entries == nil then writeText(px + 2, py + 2, "Загрузка...", C.accent2, C.panel); return end
  
  -- ФИЛЬТРУЕМ ВЛАДЕЛЬЦА
  local filtered = {}
  for i = 1, #entries do
    local t = entries[i]
    if type(t) == "table" and not samePlayerName(t.player, OWNER) then
      filtered[#filtered + 1] = t
    end
  end

  if #filtered == 0 then writeText(px + 2, py + 2, "Нет данных", C.dim, C.panel); return end

  for i = 1, math.min(#filtered, maxRows) do
    local t = filtered[i]
    local yy = py + 1 + i
    local isBuy = (t.type == "buy")
    writeText(px + 2, yy, isBuy and "BUY" or "SELL", isBuy and C.green or C.red, C.panel)
    writeText(px + 6, yy, clip(t.player or "?", 12), C.text, C.panel)
    writeText(px + 20, yy, clip(t.item or "?", pw - 26), C.muted, C.panel)
    writeRight(px + 1, yy, pw, tostring(math.floor(tonumber(t.qty) or 0)), C.white, C.panel)
  end
end

-- LAYOUT
local layout = {}
local function computeLayout()
  local kpiY, kpiH = 9, 5
  if H < 30 then kpiY, kpiH = 9, 4 end
  if H < 25 then kpiY, kpiH = 9, 3 end
  if H < 20 then kpiY, kpiH = 7, 3 end
  local colW = math.floor((W - 6) / 4)
  if colW < 10 then colW = math.floor((W - 4) / 4) end
  layout.kpiY, layout.kpiH, layout.kpiW = kpiY, kpiH, colW
  layout.kpiX = function(i) return 1 + (i - 1) * (colW + 1) end
  local contentTop = kpiY + kpiH + 1
  local availableH = H - 1 - contentTop
  local numRows = 3; local gap = 1
  local rowH = math.floor((availableH - (numRows - 1) * gap) / numRows)
  if rowH < 4 then rowH = 4 end
  if rowH > 10 then rowH = 10 end
  local totalH = contentTop + numRows * rowH + (numRows - 1) * gap
  if totalH > H - 1 then
    rowH = math.floor((H - 1 - contentTop - (numRows - 1) * gap) / numRows)
    if rowH < 3 then rowH = 3 end
  end
  local row1Y = contentTop
  local row2Y = row1Y + rowH + 1
  local row3Y = row2Y + rowH + 1
  local row3H = H - row3Y; if row3H < 3 then row3H = 3 end
  local col3W = math.floor((W - 4) / 3)
  local function col3X(i) return 1 + (i - 1) * (col3W + 1) end
  layout.coin = {x = col3X(1), y = row1Y, w = col3W, h = rowH}
  layout.ema = {x = col3X(2), y = row1Y, w = col3W, h = rowH}
  layout.visits = {x = col3X(3), y = row1Y, w = col3W, h = rowH}
  layout.purchases = {x = col3X(1), y = row2Y, w = col3W, h = rowH}
  layout.sells = {x = col3X(2), y = row2Y, w = col3W, h = rowH}
  layout.spent = {x = col3X(3), y = row2Y, w = col3W, h = rowH}
  layout.newp = {x = col3X(1), y = row3Y, w = col3W, h = row3H}
  layout.week = {x = col3X(2), y = row3Y, w = col3W, h = row3H}
  layout.recent = {x = col3X(3), y = row3Y, w = col3W, h = row3H}
end
computeLayout()

-- HEADER
local function drawHeader()
  fillRect(1, 1, W, 7, C.band)
  drawLogo(3, 2)
  writeText(32, 3, "MARKET STATISTICS", C.accent2, C.band)
  writeText(32, 5, "рейтинг игроков • экономика • активность", C.muted, C.band)
  local now = computer.uptime()
  local online = (lastDataAt > 0 or firstRequestSent) and (now - math.max(lastDataAt, 0)) < OFFLINE_AFTER
  local bcol = online and C.green or C.red
  local status = online and "[+] ONLINE" or "[-] OFFLINE"
  local sx = W - ustr_width(status) - 2
  writeText(sx, 3, status, bcol, C.band)
  writeText(W - 23, 6, currentTimeStr(), C.muted, C.band)
  fillRect(1, 8, W, 1, C.bg)
end
local function drawKPIRow()
  local d = view or {}
  drawKpi(layout.kpiX(1), layout.kpiY, layout.kpiW, layout.kpiH, "*", "ИГРОКОВ", d.totalPlayers or 0, "всего", C.accent)
  drawKpi(layout.kpiX(2), layout.kpiY, layout.kpiW, layout.kpiH, "#", "ТРАНЗАКЦИЙ", d.txTotal or 0, "сегодня: " .. tostring(d.txToday or 0), C.orange)
  drawKpi(layout.kpiX(3), layout.kpiY, layout.kpiW, layout.kpiH, "$", "COINA", d.coinTotal or 0, "в обращении", C.coin, 1)
  drawKpi(layout.kpiX(4), layout.kpiY, layout.kpiW, layout.kpiH, "%", "EMA", d.emaTotal or 0, "в обращении", C.ema, 1)
end
local _dashCache, _dashCacheW = "", 0
local function getDashLine()
  if _dashCacheW == W and _dashCache ~= "" then return _dashCache end
  _dashCache = string.rep("─", W); _dashCacheW = W
  return _dashCache
end
local function drawFooter()
  fillRect(1, H, W, 1, C.panel2)
  writeText(1, H, getDashLine(), C.accent, C.panel2)
  local author = "| By " .. AUTHOR .. " | " .. VERSION .. " |"
  local alen = ustr_width(author)
  local ax = W - alen - 1
  if ax >= 1 and alen <= W - 2 then writeText(ax, H, author, C.accent2, C.panel2) end
  if toastText ~= "" and computer.uptime() <= toastUntil then
    local maxT = (ax >= 1 and ax or W) - 4
    if maxT > 5 then
      local displayToast = " " .. toastText .. " "
      writeText(2, H, clip(displayToast, maxT), toastColor, C.panel2)
    end
  end
end

-- RENDER DIRTY
local function redrawDirty()
  if dirty.header then drawHeader() dirty.header = false end
  if dirty.kpi then drawKPIRow() dirty.kpi = false end
  if dirty.coin then
    drawTopPanel(layout.coin, "ТОП COIN", C.coin, view.topCoin,
      function(e) return groupNum(pickNum(e, "v", "value", "coin", "count", "total"), 1) end, C.coin, true)
    dirty.coin = false
  end
  if dirty.ema then
    drawTopPanel(layout.ema, "ТОП EMA", C.ema, view.topEma,
      function(e) return groupNum(pickNum(e, "v", "value", "ema", "count", "total"), 1) end, C.ema, true)
    dirty.ema = false
  end
  if dirty.visits then
    drawTopPanel(layout.visits, "ТОП ВИЗИТЫ", C.accent2, view.topVisits,
      function(e) return tostring(math.floor(pickNum(e, "visits", "value", "count", "total", "v"))) end, C.accent2, true)
    dirty.visits = false
  end
  if dirty.purchases then
    drawTopPanel(layout.purchases, "ТОП ПОКУПКИ", C.green, view.topPurchases,
      function(e) return tostring(math.floor(pickNum(e, "purchases", "count", "value", "total", "qty", "amount", "ops", "v"))) end, C.green, true)
    dirty.purchases = false
  end
  if dirty.sells then
    drawTopPanel(layout.sells, "ТОП ПРОДАЖИ", C.accent, view.topSells,
      function(e) return tostring(math.floor(pickNum(e, "sells", "count", "value", "total", "qty", "amount", "ops", "v"))) end, C.accent, true)
    dirty.sells = false
  end
  if dirty.spent then
    drawTopPanel(layout.spent, "ТОП ТРАТЫ", C.orange, view.topSpent,
      function(e)
        local c = pickNum(e, "spentCoin", "coin", "spent_coin", "c")
        local em = pickNum(e, "spentEma", "ema", "spent_ema", "e")
        if c <= 0 and em <= 0 then return "0" end
        local parts = {}
        if c > 0 then parts[#parts + 1] = groupNum(c, 1) .. "☄" end
        if em > 0 then parts[#parts + 1] = groupNum(em, 1) .. "⛭" end
        return table.concat(parts, " ")
      end, C.orange, true)
    dirty.spent = false
  end
  if dirty.newp then drawNewPlayers(layout.newp, view.newPlayers) dirty.newp = false end
  if dirty.week then drawWeekChart(layout.week, view.week) dirty.week = false end
  if dirty.recent then drawRecent(layout.recent, view.recent) dirty.recent = false end
  if dirty.footer then drawFooter() dirty.footer = false end
end

-- СЕТЬ
local function request()
  modem.send(SERVER, 0xffef, serialization.serialize({ op = "get_dashboard", limit = 7 }))
  if not firstRequestSent then
    firstRequestSent = true
    lastDataAt = computer.uptime()
    dirty.header = true
  end
  local now = computer.uptime()
  if #topRequestsQueue == 0 then
    local needRefill = false
    if now - lastTopsReqAt >= TOPS_REFRESH then needRefill = true end
    if not needRefill then
      for cat, p in pairs(topPending) do
        if p and p.tries < 3 and (now - p.sentAt) >= TOPS_RETRY then
          topRequestsQueue = {cat}
          p.tries = (p.tries or 0) + 1
          p.sentAt = now
          break
        end
      end
      if #topRequestsQueue > 0 then lastTopsReqAt = now; lastReqAt = now; return end
    end
    if needRefill then
      lastTopsReqAt = now
      topRequestsQueue = {"visits", "purchases", "sells", "spent"}
      topPending = {}
      for _, cat in ipairs(topRequestsQueue) do topPending[cat] = {sentAt = now, tries = 0} end
    end
  end
  lastReqAt = now
end

local function handleModem(from, raw)
  if from ~= SERVER then return end
  local ok, msg = pcall(serialization.unserialize, raw)
  if not ok or type(msg) ~= "table" then return end
  lastDataAt = computer.uptime()
  if not firstRequestSent then firstRequestSent = true; dirty.header = true end
  if msg.op == "dashboard_data" then
    local oldV, oldP, oldS, oldSp = view.topVisits, view.topPurchases, view.topSells, view.topSpent
    view = msg
    view.topVisits, view.topPurchases, view.topSells, view.topSpent = oldV, oldP, oldS, oldSp
    if msg.time then
      local ts = parseServerTime(msg.time)
      if ts then timeBaseServer = ts; timeBaseUptime = computer.uptime() end
    end
    dirty.kpi = true; dirty.coin = true; dirty.ema = true
    dirty.newp = true; dirty.week = true; dirty.recent = true
    needsRedraw = true
  elseif msg.op == "top_data" then
    local cat = tostring(msg.category or "")
    local lst = msg.list
    if lst == nil then lst = {} end
    if cat == "visits" then
      view.topVisits = lst; dirty.visits = true; topPending["visits"] = nil
    elseif cat == "purchases" or cat == "buy" or cat == "buys" or cat == "purchase" then
      view.topPurchases = lst; dirty.purchases = true; topPending["purchases"] = nil
    elseif cat == "sells" or cat == "sell" then
      view.topSells = lst; dirty.sells = true; topPending["sells"] = nil
    elseif cat == "spent" or cat == "spending" or cat == "spend" then
      view.topSpent = lst; dirty.spent = true; topPending["spent"] = nil
    end
    needsRedraw = true
  end
end

-- КЛАВИШИ
local function handleKey(char, code, pname)
  if not samePlayerName(pname or "", OWNER) then return end
  if char == 7 and code == 34 then
    if fs.exists("/home/update.lua") then
      toast("[~] Запускаю update.lua...", C.accent2, 2)
      pcall(function() os.execute("/home/update.lua") end)
      toast("[OK] update.lua завершил работу", C.green, 3)
    else toast("[X] Файл /home/update.lua не найден", C.red, 3) end
  elseif char == 8 and code == 35 then
    local on = not autorunEnabled(); setAutorun(on)
    toast(on and "[OK] Автозапуск ВКЛ (.shrc)" or "[!] Автозапуск ВЫКЛ (.shrc)", on and C.green or C.yellow, 4)
  elseif char == 18 and code == 19 then
    toast("[!] Перезапуск компьютера через 3 секунды...", C.orange, 10)
    needsRedraw = true; redrawDirty()
    os.sleep(3); computer.shutdown(true)
  end
end

-- ГЛАВНЫЙ ЦИКЛ
local function main()
  setBg(C.bg); setFg(C.text)
  gpu.fill(1, 1, W, H, " ")
  firstDrawDone = true
  redrawDirty()
  request()

  local lastClockCheck = 0
  while true do
    local timeout = (#topRequestsQueue > 0) and 0.05 or 0.5
    local ev = {pcall(event.pull, timeout)}
    if ev[1] and ev[2] then
      local e = ev[2]
      if e == "modem_message" then handleModem(ev[4], ev[7])
      elseif e == "key_down" then handleKey(ev[4], ev[5], ev[6])
      elseif e == "screen_resized" then
        W, H = gpu.maxResolution(); pcall(gpu.setResolution, W, H)
        computeLayout(); _dashCacheW = 0
        for k in pairs(dirty) do dirty[k] = true end
        firstDrawDone = false; needsRedraw = true
      end
    end
    local now = computer.uptime()
    if needsRedraw then
      if not firstDrawDone then
        setBg(C.bg); setFg(C.text); gpu.fill(1, 1, W, H, " ")
        firstDrawDone = true
        for k in pairs(dirty) do dirty[k] = true end
      end
      redrawDirty(); needsRedraw = false
    end
    if now - lastReqAt >= REFRESH_RATE then request() end
    if #topRequestsQueue == 0 then
      for cat, p in pairs(topPending) do
        if p and p.tries < 3 and (now - p.sentAt) >= TOPS_RETRY then
          topRequestsQueue = {cat}
          p.tries = (p.tries or 0) + 1
          p.sentAt = now
          break
        end
      end
    end
    if #topRequestsQueue > 0 and now >= nextTopRequestAt then
      local cat = table.remove(topRequestsQueue, 1)
      modem.send(SERVER, 0xffef, serialization.serialize({op = "get_top", category = cat, page = 1, perPage = 10}))
      nextTopRequestAt = now + TOP_STEP_DELAY
      if not topPending[cat] then topPending[cat] = {sentAt = now, tries = 0} end
    end
    if now - lastClockCheck >= 0.5 then
      lastClockCheck = now
      local clock = currentTimeStr()
      if clock ~= lastClock then
        lastClock = clock
        if firstDrawDone then
          writeText(W - 23, 6, clock, C.muted, C.band)
          local online = (lastDataAt > 0 or firstRequestSent) and (now - math.max(lastDataAt, 0)) < OFFLINE_AFTER
          local status = online and "[+] ONLINE" or "[-] OFFLINE"
          local sx = W - ustr_width(status) - 2
          writeText(sx, 3, status, online and C.green or C.red, C.band)
        end
      end
    end
    if toastText ~= "" and now > toastUntil then
      toastText = ""; dirty.footer = true; needsRedraw = true
    end
  end
end

local ok, err = pcall(main)
if not ok then
  pcall(function()
    setBg(C.bg); setFg(C.red); gpu.fill(1, 1, W, H, " ")
    gpu.set(2, 2, clip("Ошибка stats.lua: " .. tostring(err), W - 4))
    setFg(C.muted); gpu.set(2, 4, "Перезапуск через 5 сек...")
  end)
  os.sleep(5)
end
