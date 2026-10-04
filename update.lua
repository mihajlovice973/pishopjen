-- update.lua
-- Обновление файлов магазина PIM SHOP
-- by KaRMa__

local component = require("component")
local gpu = component.gpu
local term = require("term")
local fs = require("filesystem")
local unicode = require("unicode")
local computer = require("computer")
local event = require("event")

-- ============================================================
-- НАСТРОЙКИ
-- ============================================================
local BASE_URL = "https://raw.githubusercontent.com/mihajlovice973/pishopjen/main/"

local FILES = {
    { name = "pimserver.lua",  path = "/home/pimserver.lua"  },
    { name = "buy_items.lua",  path = "/home/buy_items.lua"  },
    { name = "shop_items.lua", path = "/home/shop_items.lua" },
    { name = "exchanger.lua",  path = "/home/exchanger.lua"  },
    { name = "agreement.lua",  path = "/home/agreement.lua"  },
}

-- ============================================================
-- ЦВЕТА
-- ============================================================
local C = {
    bg      = 0x0A0A0F,
    panel   = 0x14141F,
    frame   = 0x00E5C9,
    accent  = 0x8B5CF6,
    white   = 0xFFFFFF,
    text    = 0xD0D0E0,
    muted   = 0x555566,
    green   = 0x00FFAA,
    red     = 0xFF4D7A,
    yellow  = 0xFFD166,
}

-- ============================================================
-- УТИЛИТЫ
-- ============================================================
local W, H = 80, 25

local function setFG(c) gpu.setForeground(c) end
local function setBG(c) gpu.setBackground(c) end

local function clear()
    setBG(C.bg)
    setFG(C.white)
    gpu.fill(1, 1, W, H, " ")
end

local function ulen(s) return unicode.len(tostring(s or "")) end

local function centerText(y, text, fg, bg)
    text = tostring(text or "")
    local x = math.floor((W - ulen(text)) / 2) + 1
    if x < 1 then x = 1 end
    if bg then setBG(bg) end
    if fg then setFG(fg) end
    gpu.set(x, y, text)
end

-- ============================================================
-- РАМКА
-- ============================================================
local function drawFrame(x, y, w, h, color)
    setFG(color or C.frame)
    setBG(C.bg)

    gpu.set(x, y, "┌" .. string.rep("─", w - 2) .. "┐")
    for i = 1, h - 2 do
        gpu.set(x, y + i, "│")
        gpu.set(x + w - 1, y + i, "│")
    end
    gpu.set(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
end

-- ============================================================
-- ПРОГРЕСС-БАР — проценты с отступом назад, внутри рамки
-- ============================================================
local function drawBar(x, y, w, percent, frameRight)
    percent = math.max(0, math.min(1, tonumber(percent) or 0))
    local inner = w - 2
    local filled = math.floor(inner * percent)

    setFG(C.accent)
    setBG(C.bg)
    gpu.set(x, y, "[" .. string.rep("█", filled) .. string.rep("░", inner - filled) .. "]")

    -- Проценты сдвинуты чуть назад: не вплотную к правому краю рамки
    local pct = string.format("%3d%%", math.floor(percent * 100 + 0.5))
    local pctX = x + w + 2

    -- Если упёрлись в рамку — прижимаем на 3 символа назад
    if frameRight and pctX + ulen(pct) > frameRight - 2 then
        pctX = frameRight - ulen(pct) - 3
    end

    setFG(C.green)
    gpu.set(pctX, y, pct)
end

-- ============================================================
-- ГЛАВНЫЙ ЭКРАН
-- ============================================================
local function drawHeader()
    clear()

    local fw, fh = 60, 19
    local fx = math.floor((W - fw) / 2) + 1
    local fy = 2

    drawFrame(fx, fy, fw, fh, C.frame)

    centerText(fy + 1, "PIM SHOP", C.accent)
    centerText(fy + 2, "Загрузка Магазина", C.white)

    -- Подпись автора
    local sig = "by KaRMa__"
    setFG(C.muted)
    gpu.set(fx + fw - ulen(sig) - 3, fy + fh - 2, sig)

    return fx, fy, fw, fh
end

-- ============================================================
-- СКАЧИВАНИЕ БЕЗ ВЫВОДА WGET
-- ============================================================
local function downloadFile(url, path)
    local cmd = string.format('wget -fq "%s" "%s" 2>/dev/null', url, path)
    os.execute(cmd)
    return fs.exists(path) and fs.size(path) > 0
end

-- ============================================================
-- ЗАПУСК
-- ============================================================
local function run()
    gpu.setResolution(80, 25)

    local fx, fy, fw, fh = drawHeader()

    local total = #FILES
    local done = 0
    local failed = {}

    local barX = fx + 4
    local barY = fy + 6
    local barW = fw - 14           -- короче, чтобы проценты влезли
    local frameRight = fx + fw - 1

    for i, file in ipairs(FILES) do
        drawHeader()
        drawFrame(fx, fy, fw, fh, C.frame)

        local label = string.format("Файл %d/%d: %s", i, total, file.name)
        centerText(fy + 4, label, C.text)

        drawBar(barX, barY, barW, (i - 1) / total, frameRight)
        centerText(barY + 2, "Скачивание...", C.yellow)

        local url = BASE_URL .. file.name
        local ok = downloadFile(url, file.path)

        if ok then
            done = done + 1
        else
            table.insert(failed, file.name)
        end

        drawHeader()
        drawFrame(fx, fy, fw, fh, C.frame)
        centerText(fy + 4, label, C.text)
        drawBar(barX, barY, barW, i / total, frameRight)

        if ok then
            centerText(barY + 2, "OK: " .. file.name, C.green)
        else
            centerText(barY + 2, "ОШИБКА: " .. file.name, C.red)
        end
    end

    -- Финальный экран
    drawHeader()
    drawFrame(fx, fy, fw, fh, C.frame)

    drawBar(barX, barY, barW, done / total, frameRight)

    if done == total then
        centerText(fy + 10, "Обновление успешно завершено!", C.green)
        centerText(fy + 11, "Все файлы скачаны.", C.text)
        centerText(fy + 13, "Перезагрузка компьютера...", C.yellow)
        os.sleep(3)
        computer.shutdown(true)   -- true = перезагрузка
        return
    else
        centerText(fy + 10, "Завершено с ошибками.", C.red)
        centerText(fy + 11, "Не скачано: " .. tostring(#failed), C.yellow)
        local y = fy + 12
        for _, n in ipairs(failed) do
            if y < fy + fh - 2 then
                centerText(y, "  - " .. n, C.red)
                y = y + 1
            end
        end
        centerText(fy + fh - 2, "Нажмите любую клавишу...", C.muted)
        event.pull("key_down")
    end
end

-- ============================================================
-- ЗАПУСК С ЗАЩИТОЙ ОТ ПАДЕНИЙ
-- ============================================================
local ok, err = pcall(run)
if not ok then
    clear()
    centerText(12, "Ошибка: " .. tostring(err), C.red)
    centerText(13, "Нажмите любую клавишу...", C.muted)
    event.pull("key_down")
end
