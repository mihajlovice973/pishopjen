-- agreement.lua
local component = require("component")
local gpu = component.gpu
local unicode = require("unicode")

local function drawAgreementScreen()
    gpu.setBackground(0x0A0A0F)
    gpu.fill(1, 1, 80, 25, " ")

    -- Рамка
    local left, right, top, bottom = 3, 78, 2, 22
    gpu.setForeground(0xFFFFFF)
    gpu.fill(left, top, right-left+1, 1, "─")
    gpu.fill(left, bottom, right-left+1, 1, "─")
    for y = top+1, bottom-1 do
        gpu.set(left, y, "│")
        gpu.set(right, y, "│")
    end
    gpu.set(left, top, "┌")
    gpu.set(right, top, "┐")
    gpu.set(left, bottom, "└")
    gpu.set(right, bottom, "┘")

    -- Функция центрирования текста
    local function center(y, txt, col)
        gpu.setForeground(col or 0xFFFFFF)
        local x = math.floor((80 - unicode.len(txt)) / 2) + 1
        gpu.set(x, y, txt)
    end

    -- Заголовок
    center(5, "ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ", 0x00CCFF)

    -- Текст
    gpu.setForeground(0x888888)
    center(7,  "Используя данный ПК-магазин, ты автоматически соглашаешься")
    center(8,  "со следующими условиями:")

    center(10, "1. Все операции выполняются на ваш страх и риск.")
    center(11, "2. Администрация не несёт ответственности за потерю предметов.")
    center(12, "3. Запрещено использование багов и эксплойтов.")

    -- Красная строка
    gpu.setForeground(0xFF0000)
    local redText = "   Нарушение = перманентная блокировка аккаунта."
    local redX = math.floor((80 - unicode.len(redText)) / 2) + 1
    gpu.set(redX, 13, redText)

    gpu.setForeground(0x888888)
    center(15, "4. Цены могут изменяться без уведомления.")
    center(16, "5. Все сделки окончательны. Возврат невозможен.")

    center(18, "Нажимая кнопку ниже, ты подтверждаешь согласие со всеми")
    center(19, "условиями данного соглашения.")

    -- Кнопка
    local btnText = "[ ПОНЯТНО ]"
    local btnW = unicode.len(btnText) + 4
    local btnX = math.floor((80 - btnW) / 2) + 2

    gpu.setBackground(0x004400)
    gpu.setForeground(0x00FF88)
    gpu.fill(btnX, 22, btnW, 1, " ")
    gpu.set(btnX + 2, 22, btnText)
    gpu.setBackground(0x000000)
end

-- ВОЗВРАЩАЕМ ФУНКЦИЮ
return drawAgreementScreen
