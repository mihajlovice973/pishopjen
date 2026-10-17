-- ============================================================
-- UPDATE_MARKET.LUA v1 — загрузка файлов магазина (5 файлов)
-- + скачивание primarket, buy_items, shop_items, agreement, questlist
-- + полоса прогресса на все файлы, живая анимация и спиннер
-- + после успеха: отсчёт 5 сек и АВТОПЕРЕЗАГРУЗКА
-- + By KaRMa__
-- ============================================================
local component = require("component")
local unicode = require("unicode")
local computer = require("computer")
local fs = require("filesystem")
local gpu = component.gpu

-- СПИСОК ФАЙЛОВ ДЛЯ СКАЧИВАНИЯ
local FILES = {
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/primarket.lua", path = "/home/primarket.lua", name = "primarket.lua" },
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/buy_items.lua",  path = "/home/buy_items.lua",  name = "buy_items.lua" },
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/shop_items.lua", path = "/home/shop_items.lua", name = "shop_items.lua" },
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/agreement.lua",  path = "/home/agreement.lua",  name = "agreement.lua" },
  { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/Market/questlist.lua",  path = "/home/questlist.lua",  name = "questlist.lua" },
}

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
  center(sy + 7, "P I M   M A R K E T   U P D A T E R")
end

local FX, FY, FW, FH
local function drawInterface()
  clear()
  drawBigWord("UPDATE")
  FW, FH = 58, 12
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
end

local function drawCenterBar(p, color)
  drawBar(FX + 2, FY + FH + 1, FW - 4, p, color)
end

-- ============================================================
-- СКАЧИВАНИЕ ОДНОГО ФАЙЛА ЧЕРЕЗ WGET С АНИМАЦИЕЙ
-- ============================================================
local function downloadFileWget(fileInfo, index, totalFiles, frame)
  local baseP = (index - 1) / totalFiles
  local stepP = 1 / totalFiles
  
  -- Анимация подключения
  for i = 1, 3 do
    drawInterface()
    drawStatus("Подключение к GitHub...", fileInfo.name, string.format("Файл %d из %d", index, totalFiles), colors.accent)
    drawCenterBar(baseP + stepP * (i/4), colors.accent)
    drawSpinner(FX + FW - 4, FY + 4, frame + i, colors.accent)
    os.sleep(0.08)
  end

  drawInterface()
  drawStatus("Скачивание...", fileInfo.name, string.format("Файл %d из %d", index, totalFiles), colors.accent2)
  drawCenterBar(baseP + stepP * 0.8, colors.accent2)
  drawSpinner(FX + FW - 4, FY + 4, frame + 4, colors.accent2)
  
  -- Тихий wget
  local cmd = string.format('wget -fq "%s" "%s"', fileInfo.url, fileInfo.path)
  os.execute(cmd)
  
  -- Фолбэк на обычный wget, если файл пустой или не скачался
  if not fs.exists(fileInfo.path) or fs.size(fileInfo.path) == 0 then
    cmd = string.format('wget -f "%s" "%s"', fileInfo.url, fileInfo.path)
    os.execute(cmd)
  end

  if fs.exists(fileInfo.path) and fs.size(fileInfo.path) > 0 then
    return true, fs.size(fileInfo.path)
  end
  return false, 0
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

local function animateSuccess()
  local start = computer.uptime()
  local frame = 0
  while computer.uptime() - start < 1.6 do
    local t = (computer.uptime() - start) / 1.6
    drawInterface()
    drawStatus("✓ ГОТОВО",
      "Все файлы магазина обновлены",
      "primarket, items, agreement, quests",
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
  animateStage("Проверка системы", 0.9, 0.0, 0.05, colors.accent)
  animateStage("Подключение к серверу", 1.0, 0.05, 0.10, colors.accent)

  local totalFiles = #FILES
  local frame = 0
  
  for i, fileInfo in ipairs(FILES) do
    local ok, bytes = downloadFileWget(fileInfo, i, totalFiles, frame)
    if not ok then
      animateError("Не удалось скачать " .. fileInfo.name)
      return
    end
    frame = frame + 5
  end

  animateSuccess()
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
