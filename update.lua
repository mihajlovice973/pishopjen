local component = require("component")
local gpu = component.gpu
local unicode = require("unicode")
local event = require("event")
local computer = require("computer")
local fs = require("filesystem")
local internet = require("internet")

-- ============================================================
-- НАСТРОЙКИ ЭКРАНА И ЦВЕТА
-- ============================================================
local maxW, maxH = gpu.maxResolution()
local W = math.min(60, maxW)
local H = math.min(16, maxH)
gpu.setResolution(W, H)

local colors = {
    bg = 0x0E0E14,       -- Основной фон
    fg = 0xE8E8F0,       -- Яркий текст
    accent = 0x9D4EDD,   -- Фиолетовый акцент
    border = 0x6A0DAD,   -- Рамка
    bar_bg = 0x2A2A3A,   -- Фон шкалы
    bar_fg = 0x00D9A3,   -- Цвет заполненной шкалы (зелёный)
    error = 0xFF4D6D,    -- Ошибка
    dim = 0x6A6A7A       -- Тусклый текст
}

-- ============================================================
-- ФУНКЦИИ ОТРИСОВКИ
-- ============================================================
local function clear()
    gpu.setBackground(colors.bg)
    gpu.fill(1, 1, W, H, " ")
end

local function drawBox(x, y, bw, bh, color)
    gpu.setForeground(color)
    gpu.fill(x, y, bw, 1, "━")
    gpu.fill(x, y + bh - 1, bw, 1, "━")
    for i = 1, bh - 2 do
        gpu.set(x, y + i, "┃")
        gpu.set(x + bw - 1, y + i, "┃")
    end
    gpu.set(x, y, "┏")
    gpu.set(x + bw - 1, y, "┓")
    gpu.set(x, y + bh - 1, "┗")
    gpu.set(x + bw - 1, y + bh - 1, "┛")
end

local spinnerChars = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
local spinnerIdx = 1
local function getSpinner()
    local ch = spinnerChars[spinnerIdx]
    spinnerIdx = (spinnerIdx % #spinnerChars) + 1
    return ch
end

local function drawUI(spinner, currentFile, destPath, percent, statusText)
    clear()
    drawBox(1, 1, W, H, colors.border)
    
    -- Заголовок с крутящимися знаками
    local title = "Обновление SHOP"
    local titleStr = spinner .. " " .. title .. " " .. spinner
    local tx = math.floor((W - unicode.len(titleStr)) / 2) + 1
    gpu.setForeground(colors.accent)
    gpu.set(tx, 3, titleStr)
    
    -- Информация о файле
    gpu.setForeground(colors.fg)
    gpu.set(4, 6, "Файл: " .. (currentFile or "Ожидание..."))
    gpu.setForeground(colors.dim)
    gpu.set(4, 7, "Куда: " .. (destPath or "-"))
    
    -- Шкала прогресса
    local barW = W - 10
    local barX = 6
    local barY = 9
    
    gpu.setBackground(colors.bar_bg)
    gpu.fill(barX, barY, barW, 1, " ")
    
    local filled = math.floor(barW * percent / 100)
    gpu.setBackground(colors.bar_fg)
    gpu.fill(barX, barY, filled, 1, " ")
    
    gpu.setBackground(colors.bg)
    local pText = string.format("%d%%", percent)
    gpu.setForeground(colors.fg)
    gpu.set(barX + math.floor((barW - unicode.len(pText)) / 2), barY, pText)
    
    -- Статус
    if statusText then
        gpu.setForeground(percent == 100 and colors.bar_fg or colors.dim)
        local stx = math.floor((W - unicode.len(statusText)) / 2) + 1
        gpu.set(stx, 11, statusText)
    end
    
    -- Подпись
    gpu.setForeground(colors.dim)
    gpu.set(W - unicode.len("By KaRMa__") - 2, H - 2, "By KaRMa__")
end

-- ============================================================
-- СПИСОК ФАЙЛОВ
-- ============================================================
local files = {
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/agreement.lua", path = "/home/agreement.lua", name = "agreement.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/primarket.lua", path = "/home/primarket.lua", name = "primarket.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/exchanger.lua", path = "/home/exchanger.lua", name = "exchanger.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/shop_items.lua", path = "/home/shop_items.lua", name = "shop_items.lua" }, -- Исправлено расширение
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/buy_items.lua", path = "/home/buy_items.lua", name = "buy_items.lua" },
    { url = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/pimserver.lua", path = "/home/pimserver.lua", name = "pimserver.lua" },
}

-- ============================================================
-- ОСНОВНОЙ ПРОЦЕСС
-- ============================================================
if not fs.exists("/home") then fs.makeDirectory("/home") end

local totalFiles = #files
local percent = 0
local currentFile = ""
local destPath = ""
local statusText = "Подготовка к скачиванию..."

drawUI(getSpinner(), currentFile, destPath, percent, statusText)
os.sleep(0.5)

local function download(url, path)
    local ok, handle = pcall(internet.request, url)
    if not ok or not handle then return false, "Нет сети или 404" end
    
    local file, err = io.open(path, "w")
    if not file then return false, "Ошибка записи" end
    
    -- Читаем чанками, чтобы анимировать спиннер
    for chunk in handle do
        file:write(chunk)
        drawUI(getSpinner(), currentFile, destPath, percent, "Скачивание...")
        os.sleep(0.05) -- Микро-задержка для плавности UI
    end
    file:close()
    return true
end

local success = true
for i, f in ipairs(files) do
    currentFile = f.name
    destPath = f.path
    statusText = "Скачивание..."
    
    local ok, err = download(f.url, f.path)
    if not ok then
        statusText = "Ошибка: " .. tostring(err)
        drawUI("✖", currentFile, destPath, percent, statusText)
        success = false
        break
    end
    
    -- Плавное заполнение шкалы после скачивания каждого файла
    local targetPercent = math.floor((i / totalFiles) * 100)
    statusText = "Обработка..."
    while percent < targetPercent do
        percent = percent + 1
        drawUI(getSpinner(), currentFile, destPath, percent, statusText)
        os.sleep(0.03)
    end
end

-- ============================================================
-- ФИНАЛ И ПЕРЕЗАГРУЗКА
-- ============================================================
if success then
    percent = 100
    local countdown = 5
    local startTime = computer.uptime()
    
    while countdown > 0 do
        statusText = string.format("Готово! Перезагрузка через %d сек... [Любая клавиша - сразу]", countdown)
        drawUI("✔", currentFile, destPath, percent, statusText)
        
        local deadline = startTime + (6 - countdown)
        while computer.uptime() < deadline do
            local ev = {event.pull(deadline - computer.uptime())}
            if ev[1] == "key_down" then
                countdown = 0
                break
            end
        end
        countdown = countdown - 1
    end
    
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    computer.shutdown(true) -- Перезагрузка
else
    statusText = "Ошибка! Нажми любую клавишу для выхода."
    drawUI("✖", currentFile, destPath, percent, statusText)
    event.pull("key_down")
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    clear()
end
