return function()
    local gpu = require("component").gpu
    local unicode = require("unicode")
    
    local colors = {
        bg_main = 0x0A0A0F,
        bg_secondary = 0x14141F,
        bg_button = 0x1F1F2E,
        accent_main = 0x8B5CF6,
        accent_secondary = 0x00E5C9,
        text_main = 0xD0D0E0,
        text_bright = 0xF0F0FF,
        success = 0x00FFAA,
        error = 0xFF4D7A,
        inactive = 0x555566,
        black_fon = 0x000000,
        white = 0xFFFFFF
    }
    
    local function drawCenteredText(y, text, color)
        gpu.setForeground(color or colors.text_main)
        local x = math.floor((120 - unicode.len(text)) / 2) + 1
        gpu.set(x, y, text)
    end
    
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 120, 40, " ")
    
    -- Рамка соглашения
    local boxW = 70
    local boxH = 20
    local boxX = math.floor((120 - boxW) / 2)
    local boxY = math.floor((40 - boxH) / 2) - 2
    
    gpu.setForeground(colors.white)
    gpu.set(boxX, boxY, "╔" .. string.rep("═", boxW - 2) .. "╗")
    for i = 1, boxH - 2 do
        gpu.set(boxX, boxY + i, "║")
        gpu.set(boxX + boxW - 1, boxY + i, "║")
    end
    gpu.set(boxX, boxY + boxH - 1, "" .. string.rep("═", boxW - 2) .. "╝")
    
    drawCenteredText(boxY + 2, "ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ", colors.accent_secondary)
    
    local lines = {
        "Используя данный ПК-магазин, ты автоматически соглашаешься",
        "со следующими условиями:",
        "",
        "1. Все операции выполняются на ваш страх и риск.",
        "2. Администрация не несёт ответственности за потерю предметов.",
        "3. Запрещено использование багов и эксплойтов.",
    }
    
    local y = boxY + 4
    for _, line in ipairs(lines) do
        drawCenteredText(y, line, colors.text_bright)
        y = y + 1
    end
    
    drawCenteredText(y, "Нарушение = перманентная блокировка аккаунта.", colors.error)
    y = y + 2
    
    local lines2 = {
        "4. Цены могут изменяться без уведомления.",
        "5. Все сделки окончательны. Возврат невозможен.",
        "",
        "Нажимая кнопку ниже, ты подтверждаешь согласие со всеми",
        "условиями данного соглашения.",
    }
    
    for _, line in ipairs(lines2) do
        drawCenteredText(y, line, colors.text_bright)
        y = y + 1
    end
    
    drawCenteredText(y, "Разработчик в дс - youtubetop", colors.inactive)
    y = y + 1
    
    local btnText = "[ ПОНЯТНО ]"
    local btnW = unicode.len(btnText) + 4
    local btnX = math.floor((120 - btnW) / 2)
    gpu.setBackground(colors.success)
    gpu.fill(btnX, y, btnW, 1, " ")
    gpu.setForeground(colors.black_fon)
    local tx = btnX + math.floor((btnW - unicode.len(btnText)) / 2)
    gpu.set(tx, y, btnText)
    gpu.setBackground(colors.bg_main)
end
