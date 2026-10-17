-- ============================================================
-- UPDATE_MARKET.LUA v2 — 5 файлов магазина в ОДНОМ окне
-- + internet.request через корутину (без вывода wget в консоль)
-- + общий прогресс-бар на все файлы, живая анимация
-- + автоперезагрузка после успеха
-- + By KaRMa__
-- ============================================================
local component = require("component")
local unicode = require("unicode")
local computer = require("computer")
local fs = require("filesystem")
local gpu = component.gpu

local FILES = {
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/primarket.lua", path = "/home/primarket.lua", name = "primarket.lua" },
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/buy_items.lua",  path = "/home/buy_items.lua",  name = "buy_items.lua" },
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/shop_items.lua", path = "/home/shop_items.lua", name = "shop_items.lua" },
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/agreement.lua",  path = "/home/agreement.lua",  name = "agreement.lua" },
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/questlist.lua",  path = "/home/questlist.lua",  name = "questlist.lua" },
}

local ESTIMATE_PER_FILE = 25000   -- ~25 КБ на файл (для прогресса)
local TIMEOUT = 40                -- сек на файл
local RESTART_SECONDS = 5

local colors = {
  bg = 0x0B1018, panel = 0x111A27, border = 0x2C6E8F,
  accent = 0x00B6FF, accent2 = 0x35D0BA,
  text = 0xD7E2EC, bright = 0xF2F6FA, muted = 0x8DA2B5,
  success = 0x55E98D, error = 0xFF6262, yellow = 0xFFD166,
  barEmpty = 0x1C3345,
}

local W, H = gpu.maxResolution()
gpu.setResolution(W, H)

local function ulen(t) return unicode.len(tostring(t or "")) end
local function clip(t, w)
  t = tostring(t or "")
  if ulen(t) <= w then return t end
  return unicode.sub(t, 1, w - 1) .. "…"
end
local function clear()
  gpu.setBackground(colors.bg); gpu.setForeground(colors.bright)
  gpu.fill(1, 1, W, H, " ")
end
local function center(y, t, fg)
  t = tostring(t or "")
  local x = math.floor((W - ulen(t)) / 2) + 1
  if x < 1 then x = 1 end
  gpu.setBackground(colors.bg); gpu.setForeground(fg or colors.text)
  gpu.set(x, y, t)
end
local function drawFrame(x, y, w, h, title)
  gpu.setBackground(colors.panel); gpu.setForeground(colors.border)
  gpu.fill(x, y, w, h, " ")
  gpu.set(x, y, "┌" .. string.rep("─", w - 2) .. "┐")
  for yy = y + 1, y + h - 2 do
    gpu.set(x, yy, "│"); gpu.set(x + w - 1, yy, "│")
  end
  gpu.set(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
  if title and title ~= "" then
    gpu.setForeground(colors.accent); gpu.setBackground(colors.panel)
    gpu.set(x + math.floor((w - ulen(title) - 2) / 2), y, " " .. title .. " ")
  end
end

local function drawBar(x, y, w, p, color)
  p = math.max(0, math.min(1, tonumber(p) or 0))
  local inner = w - 2
  local filled = math.floor(inner * p)
  gpu.setBackground(colors.panel)
  gpu.setForeground(colors.muted)
  gpu.set(x, y, "╢"); gpu.set(x + w - 1, y, "╟")
  gpu.setForeground(color or colors.accent)
  gpu.set(x + 1, y, string.rep("█", filled))
  gpu.setForeground(colors.barEmpty)
  gpu.set(x + 1 + filled, y, string.rep("░", inner - filled))
end

local SPINNER = {"⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"}
local function drawSpinner(x, y, frame, color)
  gpu.setBackground(colors.panel)
  gpu.setForeground(color or colors.accent)
  gpu.set(x, y, SPINNER[(frame % #SPINNER) + 1])
end

local BIG = {
  U = {"█ █","█ █","█ █","█ █","███"},
  P = {"███","█ █","███","█  ","█  "},
  D = {"███","█ █","█ █","█ █","███"},
  A = {" █ ","█ █","███","█ █","█ █"},
  T = {"███"," █ "," █ "," █ "," █ "},
  E = {"███","█  ","███","█  ","███"},
}
local function drawBigWord(word, color)
  local step = 4
  local total = ulen(word) * step - 1
  local sx = math.floor((W - total) / 2) + 1
  local sy = math.floor(H * 0.16)
  gpu.setBackground(colors.bg)
  gpu.setForeground(color or colors.accent)
  for ci = 1, ulen(word) do
    local g = BIG[unicode.sub(word, ci, ci)]
    if g then
      for r = 1, 5 do
        gpu.set(sx + (ci - 1) * step, sy + r - 1, g[r])
      end
    end
  end
  gpu.setForeground(colors.accent2)
  gpu.setBackground(colors.bg)
  center(sy + 7, "P I M   M A R K E T   U P D A T E R")
end

local FX, FY, FW, FH
local function drawInterface()
  clear()
  drawBigWord("UPDATE")
  FW, FH = 58, 14
  FX = math.floor((W - FW) / 2) + 1
  FY = math.floor((H - FH) / 2) + 3
  drawFrame(FX, FY, FW, FH, "ОБНОВЛЕНИЕ МАГАЗИНА")
  gpu.setForeground(colors.muted); gpu.setBackground(colors.bg)
  gpu.set(2, H, "By KaRMa__")
  gpu.set(W - 11, H, "PIM MARKET")
end

local function drawStatus(l1, l2, l3, color)
  local cy = FY + 3
  gpu.setBackground(colors.panel)
  gpu.setForeground(color or colors.bright)
  gpu.set(FX + 3, cy,     clip(l1 or "", FW - 6))
  gpu.set(FX + 3, cy + 1, clip(l2 or "", FW - 6))
  gpu.set(FX + 3, cy + 2, clip(l3 or "", FW - 6))
  gpu.set(FX + 3, cy + 3, clip("Файлов: " .. #FILES .. " шт.", FW - 6))
end

local function drawCenterBar(p, color)
  drawBar(FX + 2, FY + FH + 1, FW - 4, p, color)
end

-- ============================================================
-- СКАЧИВАНИЕ ОДНОГО ФАЙЛА: internet.request (ЧИСТО, без вывода)
-- ============================================================
local function downloadOneStreaming(fileInfo)
  local okLib, inet = pcall(require, "internet")
  if not okLib or type(inet) ~= "table" or type(inet.request) ~= "function" then
    return nil, "no-lib"
  end
  local file, ferr = io.open(fileInfo.path, "wb")
  if not file then return false, ferr end

  local co = coroutine.create(function()
    local ok, err = pcall(function()
      for chunk in inet.request(fileInfo.url) do
        coroutine.yield(chunk)
      end
    end)
    if not ok then coroutine.yield(nil, tostring(err)) end
  end)

  local total, frame = 0, 0
  local start = computer.uptime()
  local err = nil

  while coroutine.status(co) ~= "dead" do
    if computer.uptime() - start > TIMEOUT then
      err = "таймаут"
      break
    end
    local okr, chunk, cerr = coroutine.resume(co)
    if not okr then err = tostring(chunk); break end
    if cerr then err = cerr; break end
    if chunk and #chunk > 0 then
      file:write(chunk)
      total = total + #chunk
    end
    -- общий прогресс: (номер файла + доля внутри файла) / всего
    local localP = math.min(0.95, 0.05 + 0.85 * (total / ESTIMATE_PER_FILE))
    local globalP = ((fileInfo.index - 1) + localP) / #FILES
    drawInterface()
    drawStatus("Скачивание...", fileInfo.name,
      string.format("Файл %d из %d | %d КБ", fileInfo.index, #FILES, math.floor(total / 1024)),
      colors.accent2)
    drawCenterBar(globalP, colors.accent2)
    drawSpinner(FX + FW - 4, FY + 5, frame, colors.accent2)
    frame = frame + 1
    os.sleep(0.02)
  end
  file:close()
  if err then
    pcall(fs.remove, fileInfo.path)
    return false, err
  end
  return true, nil, total
end

-- ============================================================
-- ЗАПАСНОЙ ВАРИАНТ: wget БЕЗ вывода в консоль
-- ============================================================
local function downloadOneWget(fileInfo)
  -- удаляем старый файл
  pcall(fs.remove, fileInfo.path)
  -- -q = тихо, -f = fail on error
  -- перенаправление 2>/dev/null прячет ошибки от консоли
  local cmd = string.format('wget -q -f "%s" "%s" 2>/dev/null', fileInfo.url, fileInfo.path)
  local ok = os.execute(cmd)
  -- если не сработало — пробуем wget без -q, но с редиректом
  if not fs.exists(fileInfo.path) or fs.size(fileInfo.path) == 0 then
    cmd = string.format('wget -f "%s" "%s" > /dev/null 2>&1', fileInfo.url, fileInfo.path)
    os.execute(cmd)
  end
  return fs.exists(fileInfo.path) and fs.size(fileInfo.path) > 0
end

-- ============================================================
-- СКАЧИВАЕМ ВСЕ 5 ФАЙЛОВ ПОСЛЕДОВАТЕЛЬНО
-- ============================================================
local function downloadAllFiles()
  local useInternet = component.isAvailable("internet")
  local totalBytes = 0
  local hasLib = false
  if useInternet then
    local okLib, inet = pcall(require, "internet")
    hasLib = okLib and type(inet) == "table" and type(inet.request) == "function"
  end

  for i, fileInfo in ipairs(FILES) do
    fileInfo.index = i
    local success, err, bytes
    if hasLib then
      success, err, bytes = downloadOneStreaming(fileInfo)
      if success == nil then
        -- internet недоступна — переключаемся на wget для всех оставшихся
        hasLib = false
      end
    end
    if not hasLib or success == nil then
      -- фолбэк: wget без вывода
      drawInterface()
      drawStatus("Скачивание (wget)...", fileInfo.name,
        string.format("Файл %d из %d", i, #FILES), colors.yellow)
      drawCenterBar((i - 1) / #FILES, colors.yellow)
      drawSpinner(FX + FW - 4, FY + 5, i, colors.yellow)
      success = downloadOneWget(fileInfo)
      bytes = fs.exists(fileInfo.path) and fs.size(fileInfo.path) or 0
      err = success and nil or "wget не смог скачать"
      -- небольшая анимация прогресса для wget
      for step = 1, 4 do
        drawInterface()
        drawStatus("Скачивание (wget)...", fileInfo.name,
          string.format("Файл %d из %d", i, #FILES), colors.yellow)
        drawCenterBar((i - 1 + step * 0.2) / #FILES, colors.yellow)
        drawSpinner(FX + FW - 4, FY + 5, i * 10 + step, colors.yellow)
        os.sleep(0.08)
      end
    end

    if not success then
      return false, err or ("не удалось скачать " .. fileInfo.name), i
    end
    totalBytes = totalBytes + (bytes or 0)
  end

  return true, nil, totalBytes
end

-- ============================================================
-- ЭТАПЫ АНИМАЦИИ
-- ============================================================
local function animateStage(title, seconds, fromP, toP, color)
  local start = computer.uptime()
  local frame = 0
  while computer.uptime() - start < seconds do
    local t = (computer.uptime() - start) / seconds
    drawInterface()
    drawStatus(title, "подготовка...", string.format("%.0f%%", t * 100), color)
    drawCenterBar(fromP + (toP - fromP) * t, color)
    drawSpinner(FX + FW - 4, FY + 5, frame, color)
    os.sleep(0.06)
    frame = frame + 1
  end
end

local function animateSuccess(bytes)
  local start = computer.uptime()
  local frame = 0
  while computer.uptime() - start < 1.6 do
    local t = (computer.uptime() - start) / 1.6
    drawInterface()
    drawStatus("✓ ГОТОВО",
      "Все файлы магазина обновлены",
      string.format("Всего: %d КБ", math.floor((bytes or 0) / 1024)),
      colors.success)
    drawCenterBar(0.92 + 0.08 * t, colors.success)
    drawSpinner(FX + FW - 4, FY + 5, frame, colors.success)
    os.sleep(0.06)
    frame = frame + 1
  end
end

local function restartCountdown()
  for i = RESTART_SECONDS, 1, -1 do
    drawInterface()
    drawStatus("✓ ГОТОВО",
      "Все файлы магазина обновлены",
      "Перезагрузка через " .. i .. " сек...",
      colors.success)
    drawCenterBar(1, colors.success)
    os.sleep(1)
  end
  drawInterface()
  drawStatus("✓ ГОТОВО", "Все файлы магазина обновлены", "Перезагрузка...", colors.success)
  drawCenterBar(1, colors.success)
  os.sleep(0.5)
  computer.shutdown(true)
end

local function animateError(msg)
  drawInterface()
  drawStatus("✗ ОШИБКА", tostring(msg or "неизвестная"), "Повтори запуск позже", colors.error)
  drawCenterBar(0, colors.error)
  os.sleep(5)
end

-- ============================================================
-- ЗАПУСК
-- ============================================================
local function main()
  animateStage("Проверка системы", 0.7, 0.0, 0.03, colors.accent)
  animateStage("Подготовка", 0.5, 0.03, 0.05, colors.accent)

  local ok, err, bytes = downloadAllFiles()
  if not ok then
    animateError(err)
    return
  end

  -- проверка: все 5 файлов должны существовать и быть непустыми
  for _, fileInfo in ipairs(FILES) do
    if not fs.exists(fileInfo.path) or fs.size(fileInfo.path) < 100 then
      animateError("Файл повреждён: " .. fileInfo.name)
      return
    end
  end

  animateSuccess(bytes)
  restartCountdown()
end

local ok, err = pcall(main)
if not ok then
  clear()
  center(math.floor(H / 2), "Ошибка: " .. clip(tostring(err), W - 10), colors.error)
  center(math.floor(H / 2) + 2, "Возврат в shell через 4 сек...", colors.muted)
  os.sleep(4)
end
clear()
