-- /home/agreement.lua — пользовательское соглашение (адаптивное)
local component = require("component")
local gpu = component.gpu
local unicode = require("unicode")

local function centered(y, text, color, w)
    gpu.setForeground(color)
    local x = math.floor((w - unicode.len(text)) / 2) + 1
    gpu.set(x, y, text)
end

local function draw()
    local w, h = gpu.getResolution()
    local bw = math.min(76, w - 8)
    local bh = math.min(22, h - 8)
    local bx = math.floor((w - bw) / 2) + 1
    local by = math.floor((h - bh) / 2) + 1

    gpu.setBackground(0x000000)
    gpu.fill(bx, by, bw, bh, " ")

    gpu.setForeground(0x9D4EDD)
    gpu.fill(bx, by, bw, 1, "─")
    gpu.fill(bx, by + bh - 1, bw, 1, "─")
    for y = by + 1, by + bh - 2 do
        gpu.set(bx, y, "│"); gpu.set(bx + bw - 1, y, "│")
    end
    gpu.set(bx, by, "┌"); gpu.set(bx + bw - 1, by, "┐")
    gpu.set(bx, by + bh - 1, "└"); gpu.set(bx + bw - 1, by + bh - 1, "┘")

    -- ОГЛАВЛЕНИЕ БЕЛОЕ
    centered(by + 2, "ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ", 0xFFFFFF, w)

    local y = by + 4
    centered(y, "Используя данный ПК-магазин, ты автоматически соглашаешься", 0xD0D0E0, w); y = y + 1
    centered(y, "со следующими условиями:", 0xD0D0E0, w); y = y + 2
    centered(y, "1. Все операции выполняются на ваш страх и риск.", 0xD0D0E0, w); y = y + 1
    centered(y, "2. Администрация не несёт ответственности за потерю предметов.", 0xD0D0E0, w); y = y + 1
    centered(y, "3. Запрещено использование багов и эксплойтов.", 0xD0D0E0, w); y = y + 1
    centered(y, "Нарушение = перманентная блокировка аккаунта.", 0xFF4D7A, w); y = y + 2
    centered(y, "4. Цены могут изменяться без уведомления.", 0xD0D0E0, w); y = y + 1
    centered(y, "5. Все сделки окончательны. Возврат невозможен.", 0xD0D0E0, w); y = y + 2
    centered(y, "Нажимая кнопку ниже, ты подтверждаешь согласие со всеми", 0xD0D0E0, w); y = y + 1
    centered(y, "условиями данного соглашения.", 0xD0D0E0, w); y = y + 1
    centered(y, "Разработчик в дс - youtubetop", 0x8DA2B5, w); y = y + 2

    local btnText = "[ ПОНЯТНО ]"
    local btnW = unicode.len(btnText) + 2
    local btnX = math.floor((w - btnW) / 2) + 1
    local btnY = math.min(y, by + bh - 2)
    gpu.setBackground(0x00E5C9)
    gpu.fill(btnX, btnY, btnW, 1, " ")
    gpu.setForeground(0x000000)
    gpu.set(btnX + 1, btnY, btnText)
    gpu.setBackground(0x000000)

    -- запоминаем кнопку для кликов в primarket
    AGREE_BTN = { x = btnX, y = btnY, xs = btnW, ys = 1 }
end

return draw
