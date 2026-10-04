-- update.lua
-- Обновление файлов магазина PIM SHOP
-- by KaRMa__
-- UI: тёмно-серый + приглушённый фиолетовый, киберстиль
-- Логика: сверка по размеру + обратный отсчёт перед перезагрузкой

local component = require("component")
local gpu       = component.gpu
local term      = require("term")
local fs        = require("filesystem")
local unicode   = require("unicode")
local computer  = require("computer")
local event     = require("event")

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
    { name = "primarket.lua",  path = "/home/primarket.lua"  },
}

-- ============================================================
-- ПАЛИТРА
-- ============================================================
local C = {
    void      = 0x07070B,
    bg        = 0x0D0D14,
    panel     = 0x16161E,
    panel2    = 0x1C1C26,
    line      = 0x2A2A38,
    frame     = 0x3A3A4E,
    frameHi   = 0x6B5AA6,
    purple    = 0x6D5AA8,
    purpleHi  = 0x9A86D4,
    purpleDim = 0x3E3260,
    text      = 0xCFCFDC,
    textDim   = 0x8A8A9A,
    muted     = 0x55556A,
    ok        = 0x7FB69A,
    err       = 0xC46A8A,
    warn      = 0xC9A96A,
    white     = 0xE8E8F0,
}

-- ============================================================
-- УТИЛИТЫ
-- ============================================================
local W, H = 80, 25

local function setFG(c) pcall(gpu.setForeground, c) end
local function setBG(c) pcall(gpu.setBackground, c) end

local function clear()
    setBG(C.void)
    setFG(C.white)
    pcall(gpu.fill, 1, 1, W, H, " ")
end

local function ulen(s) return unicode.len(tostring(s or "")) end

local function put(x, y, text, fg, bg)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    if bg then setBG(bg) end
    if fg then setFG(fg) end
    pcall(gpu.set, x, y, tostring(text or ""))
end

local function centerText(y, text, fg, bg)
    text = tostring(text or "")
    local x = math.floor((W - ulen(text)) / 2) + 1
    if x < 1 then x = 1 end
    put(x, y, text, fg, bg)
end

local function putRight(xr, y, text, fg, bg)
    xr = math.floor(tonumber(xr) or 1)
    text = tostring(text or "")
    local x = xr - ulen(text) + 1
    if x < 1 then x = 1 end
    put(x, y, text, fg, bg)
end

local function repeatCh(ch, n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "" end
    return string.rep(ch, n)
end

-- ============================================================
-- РАМКА
-- ============================================================
local function drawWindow(x, y, w, h, frame, accent)
    frame  = frame  or C.frame
    accent = accent or C.frameHi

    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    w = math.floor(tonumber(w) or 1)
    h = math.floor(tonumber(h) or 1)

    setBG(C.bg)
    setFG(C.text)
    pcall(gpu.fill, x, y, w, h, " ")

    setFG(frame)
    setBG(C.bg)
    pcall(gpu.set, x, y, "┌" .. repeatCh("─", w - 2) .. "┐")
    pcall(gpu.set, x, y + h - 1, "└" .. repeatCh("─", w - 2) .. "┘")
    for i = 1, h - 2 do
        pcall(gpu.set, x, y + i, "│")
        pcall(gpu.set, x + w - 1, y + i, "│")
    end

    setFG(accent)
    pcall(gpu.set, x, y, "┌")
    pcall(gpu.set, x + w - 1, y, "┐")
    pcall(gpu.set, x, y + h - 1, "└")
    pcall(gpu.set, x + w - 1, y + h - 1, "┘")
    pcall(gpu.set, x + 1, y, "═")
    pcall(gpu.set, x + w - 2, y, "═")
    pcall(gpu.set, x + 1, y + h - 1, "═")
    pcall(gpu.set, x + w - 2, y + h - 1, "═")
end

-- ============================================================
-- ПРОГРЕСС-БАР
-- ============================================================
local function drawBar(x, y, w, percent, colorBg, colorFill, colorMark)
    percent = math.max(0, math.min(1, tonumber(percent) or 0))
    colorBg   = colorBg   or C.line
    colorFill = colorFill or C.purple
    colorMark = colorMark or C.purpleHi

    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    w = math.floor(tonumber(w) or 1)

    local inner  = w - 2
    local filled = math.floor(inner * percent)
    if filled < 0 then filled = 0 end
    if filled > inner then filled = inner end

    setFG(C.frame)
    setBG(C.bg)
    pcall(gpu.set, x, y, "▐")
    pcall(gpu.set, x + w - 1, y, "▌")

    setFG(colorBg)
    setBG(C.bg)
    if inner - filled > 0 then
        pcall(gpu.set, x + 1 + filled, y, repeatCh("░", inner - filled))
    end

    setFG(colorFill)
    if filled > 0 then
        pcall(gpu.set, x + 1, y, repeatCh("█", filled))
    end

    if filled > 0 and filled < inner then
        setFG(colorMark)
        pcall(gpu.set, x + filled, y, "▓")
    end
end

-- ============================================================
-- ШАПКА
-- ============================================================
local function drawHeader()
    clear()

    local fw, fh = 66, 21
    local fx = math.floor((W - fw) / 2) + 1
    local fy = math.floor((H - fh) / 2)

    drawWindow(fx, fy, fw, fh, C.frame, C.frameHi)

    setBG(C.panel2)
    setFG(C.text)
    pcall(gpu.fill, fx + 2, fy + 2, fw - 4, 3, " ")

    setFG(C.frameHi)
    setBG(C.bg)
    pcall(gpu.set, fx + 2, fy + 1, "╞" .. repeatCh("═", fw - 4) .. "╡")
    pcall(gpu.set, fx + 2, fy + 5, "╞" .. repeatCh("═", fw - 4) .. "╡")

    setFG(C.purpleHi)
    setBG(C.panel2)
    pcall(gpu.set, fx + 4,  fy + 2, "◆")
    pcall(gpu.set, fx + fw - 5, fy + 2, "◆")
    pcall(gpu.set, fx + 4,  fy + 4, "◇")
    pcall(gpu.set, fx + fw - 5, fy + 4, "◇")

    centerText(fy + 2, "P I M   S H O P", C.purpleHi, C.panel2)
    centerText(fy + 3, "· загрузка магазина ·", C.textDim, C.panel2)

    local sig = "by KaRMa__"
    putRight(fx + fw - 4, fy + fh - 2, sig, C.muted, C.bg)

    return fx, fy, fw, fh
end

-- ============================================================
-- СТАТУС
-- ============================================================
local function statusPrefix(kind)
    if kind == "ok"    then return C.ok,       "✔" end
    if kind == "err"   then return C.err,      "✖" end
    if kind == "warn"  then return C.warn,     "▸" end
    if kind == "info"  then return C.purpleHi, "›" end
    if kind == "dim"   then return C.muted,    "·" end
    return C.text, "·"
end

local function drawStatus(y, text, kind)
    local color, mark = statusPrefix(kind)
    centerText(y, mark .. "  " .. text, color)
end

-- ============================================================
-- ФАЙЛЫ
-- ============================================================
local function fileExists(p)
    return fs.exists(p) and fs.size(p) > 0
end

-- Сверка по размеру: если размеры разные — файлы отличаются.
-- Если одинаковые — считаем актуальными (для .lua этого достаточно).
local function filesDiffer(a, b)
    if not fileExists(a) then return true end
    if not fileExists(b) then return true end
    local sa = fs.size(a)
    local sb = fs.size(b)
    if type(sa) ~= "number" or type(sb) ~= "number" then return true end
    return sa ~= sb
end

-- ============================================================
-- СКАЧИВАНИЕ
-- ============================================================
local function downloadFile(url, path)
    if fs.exists(path) then fs.remove(path) end
    local cmd = string.format('wget -fq "%s" "%s" 2>/dev/null', url, path)
    os.execute(cmd)
    return fileExists(path)
end

-- ============================================================
-- СПИННЕР
-- ============================================================
local function drawSpinner(y, frame)
    local chars = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" }
    local ch = chars[(frame % #chars) + 1]
    centerText(y, ch .. "  скачивание", C.purpleHi)
end

-- ============================================================
-- ОСНОВНАЯ ЛОГИКА
-- ============================================================
local function run()
    pcall(gpu.setResolution, 80, 25)

    local fx, fy, fw, fh = drawHeader()

    local total  = #FILES
    local done   = 0
    local failed = {}

    local barX = fx + 6
    local barW = fw - 16

    local tmpDir = "/tmp/pim_upd"
    if not fs.exists(tmpDir) then fs.makeDirectory(tmpDir) end

    for i, file in ipairs(FILES) do
        drawHeader()
        drawStatus(fy + 7, string.format("шаг %d/%d", i, total), "info")
        centerText(fy + 9, "[" .. file.name .. "]", C.purpleHi)

        centerText(fy + 11, "общий прогресс", C.textDim)
        drawBar(barX, fy + 12, barW, (i - 1) / total, C.line, C.purpleDim, C.purpleHi)
        putRight(barX + barW + 1, fy + 12,
            string.format("%3d%%", math.floor((i - 1) / total * 100)), C.textDim)

        centerText(fy + 14, "текущий файл", C.textDim)
        drawBar(barX, fy + 15, barW, 0, C.line, C.purple, C.purpleHi)
        drawSpinner(fy + 17, 0)

        for f = 1, 4 do
            drawHeader()
            drawStatus(fy + 7, string.format("шаг %d/%d", i, total), "info")
            centerText(fy + 9, "[" .. file.name .. "]", C.purpleHi)
            centerText(fy + 11, "общий прогресс", C.textDim)
            drawBar(barX, fy + 12, barW, (i - 1) / total, C.line, C.purpleDim, C.purpleHi)
            putRight(barX + barW + 1, fy + 12,
                string.format("%3d%%", math.floor((i - 1) / total * 100)), C.textDim)
            centerText(fy + 14, "текущий файл", C.textDim)
            drawBar(barX, fy + 15, barW, f / 4 * 0.5, C.line, C.purple, C.purpleHi)
            drawSpinner(fy + 17, f)
            os.sleep(0.03)
        end

        local url = BASE_URL .. file.name
        local tmp = tmpDir .. "/" .. file.name
        local ok = downloadFile(url, tmp)

        local status, statusKind

        if not ok then
            status = "ОШИБКА · " .. file.name
            statusKind = "err"
            table.insert(failed, file.name)
        else
            if filesDiffer(tmp, file.path) then
                if fs.exists(file.path) then fs.remove(file.path) end
                fs.copy(tmp, file.path)
                done = done + 1
                status = "ОБНОВЛЁН · " .. file.name
                statusKind = "ok"
            else
                status = "УЖЕ АКТУАЛЕН · " .. file.name
                statusKind = "dim"
            end
            pcall(function() fs.remove(tmp) end)
        end

        drawHeader()
        drawStatus(fy + 7, string.format("шаг %d/%d", i, total), "info")
        centerText(fy + 9, "[" .. file.name .. "]", C.purpleHi)
        centerText(fy + 11, "общий прогресс", C.textDim)
        drawBar(barX, fy + 12, barW, i / total, C.line, C.purpleDim, C.purpleHi)
        putRight(barX + barW + 1, fy + 12,
            string.format("%3d%%", math.floor(i / total * 100)), C.textDim)
        centerText(fy + 14, "текущий файл", C.textDim)
        drawBar(barX, fy + 15, barW, 1, C.line, C.purple, C.purpleHi)
        drawStatus(fy + 17, status, statusKind)

        os.sleep(0.05)
    end

    -- ============================================================
    -- ФИНАЛЬНЫЙ ЭКРАН + ОТСЧЁТ
    -- ============================================================
    if #failed == 0 then
        local cw = fw - 20
        local cx = fx + math.floor((fw - cw) / 2)

        for n = 3, 1, -1 do
            drawHeader()
            if done == 0 then
                centerText(fy + 8,  "◆  ОБНОВЛЕНИЙ НЕТ  ◆", C.ok)
                centerText(fy + 10, "все " .. total .. " файлов уже актуальны", C.text)
            else
                centerText(fy + 8,  "◆  ОБНОВЛЕНИЕ ЗАВЕРШЕНО  ◆", C.ok)
                centerText(fy + 10, "обновлено файлов: " .. done .. " из " .. total, C.text)
            end
            drawBar(cx, fy + 12, cw, 1, C.line, C.purple, C.purpleHi)
            centerText(fy + 14, "перезагрузка через " .. n .. " ...", C.warn)
            os.sleep(1)
        end

        drawHeader()
        centerText(fy + 8,  "◆  ПЕРЕЗАГРУЗКА  ◆", C.warn)
        centerText(fy + 10, "до связи...", C.textDim)
        os.sleep(0.6)
        computer.shutdown(true)
        return
    else
        drawHeader()
        centerText(fy + 8,  "◆  ЗАВЕРШЕНО С ОШИБКАМИ  ◆", C.err)
        centerText(fy + 10, "не скачано: " .. tostring(#failed) .. " из " .. total, C.warn)

        local y = fy + 12
        for _, n in ipairs(failed) do
            if y >= fy + fh - 3 then break end
            centerText(y, "· " .. n, C.textDim)
            y = y + 1
        end

        centerText(fy + fh - 2, "нажмите любую клавишу...", C.muted)
        event.pull("key_down")
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================
local ok, err = pcall(run)
if not ok then
    clear()
    centerText(12, "Ошибка: " .. tostring(err), C.err)
    centerText(13, "Нажмите любую клавишу...", C.muted)
    event.pull("key_down")
end
