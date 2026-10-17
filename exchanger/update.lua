-- ============================================================
-- UPDATE.LUA v2 — загрузка exchanger.lua (ссылка скрыта)
-- + полоса прогресса по центру рамки
-- + исправленный BIG-заголовок "UPDATE"
-- + после успеха: отсчёт 5 сек и АВТОПЕРЕЗАГРУЗКА
-- + потоковое скачивание с живой анимацией, запасной wget -f
-- + By KaRMa__
-- ============================================================
local component = require("component")
local unicode = require("unicode")
local computer = require("computer")
local fs = require("filesystem")
local gpu = component.gpu

-- СКРЫТАЯ ССЫЛКА (пользователь её не видит)
local TARGET_URL = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/exchanger/exchanger.lua"
local TARGET_PATH = "/home/exchanger.lua"
local ESTIMATE_SIZE = 102400
local TIMEOUT = 45
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
-- полоска: x,y + ширина; рисуется ПО ЦЕНТРУ вызова
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
local SPINNER = {"⠋","⠙","","","⠼","⠴","","⠧","⠇",""}
local function drawSpinner(x, y, frame, color)
  gpu.setBackground(colors.panel)
  gpu.setForeground(color or colors.accent)
  gpu.set(x, y, SPINNER[(frame % #SPINNER) + 1])
end

-- BIG-ШРИФТ 3x5 для заголовка UPDATE
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
  center(sy + 7, "P I M   E X C H A N G E R   U P D A T E R")
end

local FX, FY, FW, FH
local function drawInterface()
  clear()
  drawBigWord("UPDATE")
  FW, FH = 58, 12
  FX = math.floor((W - FW) / 2) + 1
  FY = math.floor((H - FH) / 2) + 3
  drawFrame(FX, FY, FW, FH, "ОБНОВЛЕНИЕ ОБМЕННИКА")
  gpu.setForeground(colors.muted); gpu.setBackground(colors.bg)
  gpu.set(2, H, "By KaRMa__")
  gpu.set(W - 14, H, "PIM EXCHANGER")
end
local function drawStatus(l1, l2, l3, color)
  local cy = FY + 3
  gpu.setBackground(colors.panel)
  gpu.setForeground(color or colors.bright)
  gpu.set(FX + 3, cy,     clip(l1 or "", FW - 6))
  gpu.set(FX + 3, cy + 1, clip(l2 or "", FW - 6))
  gpu.set(FX + 3, cy + 2, clip(l3 or "", FW - 6))
end
-- ЦЕНТРИРОВАННАЯ полоса под рамкой: отступ 2 с каждой стороны
local function drawCenterBar(p, color)
  drawBar(FX + 2, FY + FH + 1, FW - 4, p, color)
end

-- ============================================================
-- ПОТОКОВОЕ СКАЧИВАНИЕ (internet lib + корутина) С АНИМАЦИЕЙ
-- ============================================================
local function downloadStreaming()
  local okLib, inet = pcall(require, "internet")
  if not okLib or type(inet) ~= "table" or type(inet.request) ~= "function" then
    return nil, "no-lib"
  end
  local file, ferr = io.open(TARGET_PATH, "wb")
  if not file then return false, ferr end

  local co = coroutine.create(function()
    for chunk in inet.request(TARGET_URL) do
      coroutine.yield(chunk)
    end
  end)

  local total, frame = 0, 0
  local start = computer.uptime()
  local err = nil

  while coroutine.status(co) ~= "dead" do
    if computer.uptime() - start > TIMEOUT then
      err = "таймаут соединения"
      break
    end
    local okr, chunk = coroutine.resume(co)
    if not okr then
      err = tostring(chunk)
      break
    end
    if chunk and #chunk > 0 then
      file:write(chunk)
      total = total + #chunk
    end
    local p = math.min(0.92, 0.10 + 0.80 * (total / ESTIMATE_SIZE))
    drawInterface()
    drawStatus("Скачивание потока...",
      "exchanger.lua",
      string.format("Получено: %d КБ", math.floor(total / 1024)),
      colors.accent2)
    drawCenterBar(p, colors.accent)
    drawSpinner(FX + FW - 4, FY + 4, frame, colors.accent2)
    frame = frame + 1
  end
  file:close()
  if err then
    pcall(fs.remove, TARGET_PATH)
    return false, err
  end
  return true, nil, total
end

-- запасной вариант: wget -f (тихий режим)
local function downloadWget()
  drawInterface()
  drawStatus("Скачивание (резервный канал)...", "exchanger.lua", "Подождите...", colors.yellow)
  drawCenterBar(0.5, colors.yellow)
  os.execute('wget -fq "' .. TARGET_URL .. '" "' .. TARGET_PATH .. '"')
  return fs.exists(TARGET_PATH) and fs.size(TARGET_PATH) > 0
end

-- ============================================================
-- ЭТАПЫ С АНИМАЦИЕЙ
-- ============================================================
local function animateStage(title, seconds, fromP, toP, color)
  local start = computer.uptime()
  local frame = 0
  while computer.uptime() - start < seconds do
    local t = (computer.uptime() - start) / seconds
    drawInterface()
    drawStatus(title, "подготовка...", string.format("%.0f%%", t * 100), color)
    drawCenterBar(fromP + (toP - fromP) * t, color)
    drawSpinner(FX + FW - 4, FY + 4, frame, color)
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
      "exchanger.lua обновлён",
      string.format("Размер: %d КБ", math.floor((bytes or 0) / 1024)),
      colors.success)
    drawCenterBar(0.92 + 0.08 * t, colors.success)
    drawSpinner(FX + FW - 4, FY + 4, frame, colors.success)
    os.sleep(0.06)
    frame = frame + 1
  end
end

-- ОБРАТНЫЙ ОТСЧЁТ И АВТОПЕРЕЗАГРУЗКА
local function restartCountdown()
  for i = RESTART_SECONDS, 1, -1 do
    drawInterface()
    drawStatus("✓ ГОТОВО",
      "exchanger.lua обновлён",
      "Перезагрузка через " .. i .. " сек...",
      colors.success)
    drawCenterBar(1, colors.success)
    os.sleep(1)
  end
  drawInterface()
  drawStatus("✓ ГОТОВО", "exchanger.lua обновлён", "Перезагрузка...", colors.success)
  drawCenterBar(1, colors.success)
  os.sleep(0.5)
  computer.shutdown(true) -- reboot
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
  if not component.isAvailable("internet") then
    drawInterface()
    animateError("Нет интернет-карты")
    return
  end
  animateStage("Проверка системы", 0.9, 0.0, 0.08, colors.accent)
  animateStage("Подключение к серверу", 1.0, 0.08, 0.15, colors.accent)

  local ok, err, bytes = downloadStreaming()
  if ok == nil then
    if not downloadWget() then
      animateError("wget не смог скачать файл")
      return
    end
    bytes = fs.size(TARGET_PATH)
  elseif ok == false then
    animateError(err)
    return
  end

  if not fs.exists(TARGET_PATH) or fs.size(TARGET_PATH) < 1000 then
    animateError("Файл повреждён или пуст")
    return
  end
  animateSuccess(bytes or fs.size(TARGET_PATH))
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
