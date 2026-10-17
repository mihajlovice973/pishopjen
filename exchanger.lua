-- ============================================================
-- PI SHOP v9.0 - ULTIMATE MEGA EDITION
-- Полностью переписанный движок с двойной буферизацией.
-- Включает: логирование, настройки, темы, анимации, и т.д.
-- ============================================================

-- === МОДУЛИ ===
local component = require("component")
local event = require("event")
local computer = require("computer")
local unicode = require("unicode")
local fs = require("filesystem")
local serialization = require("serialization")
local term = require("term")

-- === КОМПОНЕНТЫ ===
local gpu = component.gpu
local pim = component.isAvailable("pim") and component.pim or nil
local me = component.isAvailable("me_interface") and component.me_interface or nil

-- === РАЗРЕШЕНИЕ ЭКРАНА ===
local W, H = 160, 50
local maxW, maxH = gpu.maxResolution()
if maxW < 160 then W, H = maxW, maxH end
pcall(gpu.setResolution, W, H)
W, H = gpu.getResolution()

-- === ЦВЕТОВЫЕ ПАЛИТРЫ ===
local THEMES = {
    purple = {
        bg=0x05000A, panel=0x110022, panel_light=0x200033,
        border=0x4B0082, border_br=0x9932CC, accent=0xDA70D6,
        text=0xE6E6FA, dim=0x9370DB, dark=0x4A3B5C,
        green=0x00FF7F, red=0xFF4500, yellow=0xFFD700, cyan=0x00FFFF,
        select=0x300050, header=0x0A0015
    },
    blue = {
        bg=0x000A0F, panel=0x001A2A, panel_light=0x003A5C,
        border=0x004B8C, border_br=0x0099FF, accent=0x00CCFF,
        text=0xE0F7FA, dim=0x80DEEA, dark=0x006064,
        green=0x00E676, red=0xFF1744, yellow=0xFFEA00, cyan=0x18FFFF,
        select=0x004D66, header=0x000A14
    },
    red = {
        bg=0x0A0000, panel=0x1A0000, panel_light=0x3A0000,
        border=0x8C0000, border_br=0xFF0000, accent=0xFF5555,
        text=0xFFD0D0, dim=0xCC8888, dark=0x660000,
        green=0x00FF88, red=0xFF0000, yellow=0xFFDD00, cyan=0x00FFFF,
        select=0x660000, header=0x140000
    }
}

-- === КОНФИГУРАЦИЯ ===
local CONFIG_PATH = "/home/pishop.cfg"
local Config = { sound = true, auto_refresh = true, theme = "purple" }

local function loadConfig()
    if fs.exists(CONFIG_PATH) then
        local f = io.open(CONFIG_PATH, "r")
        if f then
            local ok, data = pcall(serialization.unserialize, f:read("*a"))
            f:close()
            if ok and type(data) == "table" then
                for k,v in pairs(data) do Config[k] = v end
            end
        end
    end
end

local function saveConfig()
    local f = io.open(CONFIG_PATH, "w")
    if f then f:write(serialization.serialize(Config)); f:close() end
end
loadConfig()

local C = THEMES[Config.theme] or THEMES.purple

-- === ДВИЖОК ДВОЙНОЙ БУФЕРИЗАЦИИ ===
local screen = {}
local old_screen = {}

local function initBuffers()
    for y = 1, H do
        screen[y] = {}
        old_screen[y] = {}
        for x = 1, W do
            screen[y][x] = {t=" ", f=C.text, b=C.bg}
            old_screen[y][x] = {t="\0", f=0, b=0} 
        end
    end
end

local function clearBuf(bg)
    for y=1,H do
        for x=1,W do
            screen[y][x].t = " "
            screen[y][x].b = bg
        end
    end
end

local function drawStr(x, y, text, fg, bg)
    if y < 1 or y > H then return end
    local len = unicode.len(text)
    for i=1,len do
        local cx = x + i - 1
        if cx >= 1 and cx <= W then
            screen[y][cx].t = unicode.sub(text, i, i)
            screen[y][cx].f = fg
            screen[y][cx].b = bg
        end
    end
end

local function fillBuf(x, y, w, h, char, fg, bg)
    for i=0,h-1 do
        local cy = y + i
        if cy >= 1 and cy <= H then
            for j=0,w-1 do
                local cx = x + j
                if cx >= 1 and cx <= W then
                    screen[cy][cx].t = char
                    screen[cy][cx].f = fg
                    screen[cy][cx].b = bg
                end
            end
        end
    end
end

local function flushBuf()
    for y=1,H do
        for x=1,W do
            local s = screen[y][x]
            local o = old_screen[y][x]
            if s.t ~= o.t or s.f ~= o.f or s.b ~= o.b then
                gpu.setBackground(s.b)
                gpu.setForeground(s.f)
                gpu.set(x, y, s.t)
                o.t = s.t; o.f = s.f; o.b = s.b
            end
        end
    end
end

-- === УТИЛИТЫ ===
local function ulen(t) return unicode.len(tostring(t or "")) end
local function clip(t, w) 
    t = tostring(t or "")
    if ulen(t) <= w then return t end 
    return unicode.sub(t, 1, w-1) .. "…" 
end
local function padR(t, w) 
    t = clip(t, w)
    return t .. string.rep(" ", math.max(0, w - ulen(t))) 
end
local function fmtNum(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return string.format("%.1fM", n/1000000) end
    if n >= 1000 then return string.format("%.1fK", n/1000) end
    return tostring(math.floor(n))
end

-- === БАЗА ДАННЫХ РУД ===
local ores = {
    { cat="precious", name="Алмазная руда", take_id="minecraft:diamond_ore", take_dmg=0, give_id="minecraft:diamond", give_dmg=0, take_amt=1, give_amt=2, icon="💎" },
    { cat="precious", name="Изумрудная руда", take_id="minecraft:emerald_ore", take_dmg=0, give_id="minecraft:emerald", give_dmg=0, take_amt=1, give_amt=2, icon="💚" },
    { cat="precious", name="Золотая руда", take_id="minecraft:gold_ore", take_dmg=0, give_id="minecraft:gold_ingot", give_dmg=0, take_amt=3, give_amt=7, icon="🟡" },
    { cat="precious", name="Серебряная руда", take_id="ThermalFoundation:Ore", take_dmg=2, give_id="IC2:itemIngot", give_dmg=6, take_amt=1, give_amt=2, icon="⚪" },
    { cat="precious", name="Платиновая руда", take_id="ThermalFoundation:Ore", take_dmg=5, give_id="ThermalFoundation:material", give_dmg=37, take_amt=1, give_amt=2, icon="🔘" },
    { cat="metals", name="Железная руда", take_id="minecraft:iron_ore", take_dmg=0, give_id="minecraft:iron_ingot", give_dmg=0, take_amt=3, give_amt=7, icon="⬜" },
    { cat="metals", name="Медная руда", take_id="IC2:blockOreCopper", take_dmg=0, give_id="IC2:itemIngot", give_dmg=0, take_amt=3, give_amt=7, icon="🟠" },
    { cat="metals", name="Оловянная руда", take_id="IC2:blockOreTin", take_dmg=0, give_id="IC2:itemIngot", give_dmg=1, take_amt=3, give_amt=7, icon="🔵" },
    { cat="metals", name="Никелевая руда", take_id="ThermalFoundation:Ore", take_dmg=4, give_id="ThermalFoundation:material", give_dmg=68, take_amt=1, give_amt=2, icon="🟢" },
    { cat="other", name="Угольная руда", take_id="minecraft:coal_ore", take_dmg=0, give_id="minecraft:coal", give_dmg=0, take_amt=1, give_amt=3, icon="⚫" },
    { cat="other", name="Красная руда", take_id="minecraft:redstone_ore", take_dmg=0, give_id="minecraft:redstone_block", give_dmg=0, take_amt=1, give_amt=1, icon="🔴" },
    { cat="magic", name="Лазуритовая руда", take_id="minecraft:lapis_ore", take_dmg=0, give_id="minecraft:dye", give_dmg=4, take_amt=1, give_amt=7, icon="🔷" },
    { cat="magic", name="Кварцевая руда", take_id="minecraft:quartz_ore", take_dmg=0, give_id="minecraft:quartz", give_dmg=0, take_amt=1, give_amt=4, icon="⬛" },
    { cat="magic", name="Дракониевая руда", take_id="DraconicEvolution:draconiumOre", take_dmg=0, give_id="DraconicEvolution:draconiumDust", give_dmg=0, take_amt=1, give_amt=2, icon="🐉" },
}
for _, o in ipairs(ores) do o.stock=0; o.avail=false; o.max_stack=64 end

-- === СОСТОЯНИЕ ===
local S = {
    tab="exchange", cat="all", selected=1, scroll=0,
    anim=0, marquee=0, status="PI SHOP v9.0 запущен", status_col=C.cyan,
    player="---", total_items=0, history={}, modal=nil,
    search="", search_active=false,
    boxes={}, 
    processing=false, progress=0,
    pending_exchange=nil, pending_all=nil,
    last_clock=""
}

local categories = {
    { id="all", label="ВСЕ РУДЫ", icon="◆" },
    { id="precious", label="ДРАГОЦЕННЫЕ", icon="💎" },
    { id="metals", label="МЕТАЛЛЫ", icon="⚙" },
    { id="magic", label="МАГИЯ", icon="✦" },
    { id="other", label="ПРОЧИЕ", icon="■" },
}

-- === ЛОГИКА ===
local function getFiltered()
    local t = {}
    local q = unicode.lower(S.search)
    for _, o in ipairs(ores) do
        local match_cat = (S.cat == "all" or o.cat == S.cat)
        local match_search = (q == "" or unicode.lower(o.name):find(q, 1, true))
        if match_cat and match_search then
            t[#t+1] = o
        end
    end
    return t
end

local function refreshME()
    if not me then
        S.status = "ОШИБКА: МЭ не подключена!"; S.status_col = C.red; return
    end
    S.total_items = 0
    for _, o in ipairs(ores) do
        local ok, item = pcall(function()
            return me.getItemDetail({ id=o.give_id, dmg=o.give_dmg or 0 }).basic()
        end)
        if ok and item then
            o.stock = item.qty
            o.max_stack = item.max_size or 64
            o.avail = item.qty >= (o.give_amt or 1)
            S.total_items = S.total_items + item.qty
        else
            o.stock=0; o.avail=false; o.max_stack=64
        end
    end
    S.status = "Данные МЭ успешно обновлены"; S.status_col = C.green
    if Config.sound then computer.beep(800, 0.05) end
end

local function saveHistoryToFile()
    local f = io.open("/home/pishop_history.txt", "a")
    if f then
        for _, h in ipairs(S.history) do
            f:write(h.time .. " | " .. h.item .. " x" .. h.qty .. "\n")
        end
        f:close()
    end
end

local function doExchange(o)
    if S.processing then return end
    if not pim or not me then
        S.status = "Ошибка: PIM или МЭ не подключены"; S.status_col = C.red; return
    end
    if not o.avail then
        S.status = "Недостаточно " .. o.name .. " в МЭ"; S.status_col = C.red
        if Config.sound then computer.beep(200, 0.1) end
        return
    end
    
    S.processing = true
    S.progress = 0
    S.status = "Обмен " .. o.name .. "..."; S.status_col = C.yellow
    S.pending_exchange = o
end

local function processExchange()
    local o = S.pending_exchange
    if not o then return end
    
    local slots = pim.getInventorySize()
    local data = pim.getAllStacks(0)
    local out = 0
    
    for slot = 1, slots do
        local s = data[slot]
        if s and s.id == o.take_id and (s.dmg or 0) == (o.take_dmg or 0) then
            local take = s.qty - (s.qty % o.take_amt)
            if take > 0 then
                local need = (take / o.take_amt) * o.give_amt
                if o.stock >= need then
                    local ok, got = pcall(pim.pushItem, "DOWN", slot, take)
                    if ok and got and got > 0 then
                        local give = math.floor(got / o.take_amt) * o.give_amt
                        local ok2, res = pcall(me.exportItem, { id=o.give_id, dmg=o.give_dmg or 0 }, "UP", give)
                        if ok2 and res and res.size then out = out + res.size end
                    end
                end
            end
        end
    end
    
    if out > 0 then
        S.status = "Успешно обменяно: " .. out .. " шт!"; S.status_col = C.green
        table.insert(S.history, 1, { time=os.date("%H:%M:%S"), item=o.name, qty=out })
        if #S.history > 50 then table.remove(S.history) end
        saveHistoryToFile()
        if Config.sound then computer.beep(1200, 0.1) end
    else
        S.status = "Нет руды в инвентаре для обмена"; S.status_col = C.yellow
        if Config.sound then computer.beep(300, 0.2) end
    end
    
    S.processing = false
    S.pending_exchange = nil
    refreshME()
end

local function doExchangeAll()
    local f = getFiltered()
    local to_ex = {}
    for _, o in ipairs(f) do
        if o.avail then to_ex[#to_ex+1] = o end
    end
    
    if #to_ex == 0 then
        S.status = "Нет доступных ресурсов для обмена"; S.status_col = C.yellow; return
    end
    
    S.processing = true
    S.progress = 0
    S.status = "Пакетный обмен..."; S.status_col = C.cyan
    S.pending_all = to_ex
end

local function processExchangeAll()
    local list = S.pending_all
    local cnt = 0
    for _, o in ipairs(list) do
        local slots = pim.getInventorySize()
        local data = pim.getAllStacks(0)
        for slot = 1, slots do
            local s = data[slot]
            if s and s.id == o.take_id and (s.dmg or 0) == (o.take_dmg or 0) then
                local take = s.qty - (s.qty % o.take_amt)
                if take > 0 and o.stock >= ((take / o.take_amt) * o.give_amt) then
                    local ok, got = pcall(pim.pushItem, "DOWN", slot, take)
                    if ok and got and got > 0 then
                        local give = math.floor(got / o.take_amt) * o.give_amt
                        pcall(me.exportItem, { id=o.give_id, dmg=o.give_dmg or 0 }, "UP", give)
                        cnt = cnt + 1
                    end
                end
            end
        end
    end
    
    S.status = "Пакетный обмен завершен! Обработано видов: " .. cnt; S.status_col = C.green
    S.processing = false
    S.pending_all = nil
    if Config.sound then computer.beep(1500, 0.15) end
    refreshME()
end

-- === ОТРИСОВКА ЭЛЕМЕНТОВ ===
local function drawBoxBuf(x, y, w, h, title, border_col, bg_col)
    fillBuf(x, y, w, h, " ", C.text, bg_col)
    drawStr(x, y, "┌" .. string.rep("─", w-2) .. "┐", border_col, bg_col)
    drawStr(x, y+h-1, "└" .. string.rep("─", w-2) .. "┘", border_col, bg_col)
    for i=1,h-2 do
        drawStr(x, y+i, "│", border_col, bg_col)
        drawStr(x+w-1, y+i, "│", border_col, bg_col)
    end
    if title and #title > 0 then
        drawStr(x+2, y, " " .. title .. " ", C.accent, bg_col)
    end
end

local function drawHeader()
    fillBuf(1, 1, W, 4, " ", C.text, C.header)
    drawStr(3, 2, "◆ PI SHOP ◆", C.accent, C.header)
    drawStr(3, 3, "RESOURCE EXCHANGER v9.0", C.dim, C.header)
    
    for i = 1, 6 do
        local bx = W - 50 + (i - 1) * 6
        drawStr(bx, 2, "▬▬▬", (i % 2 == 0) and C.accent or C.border, C.header)
    end
    
    local dot = (S.anim % 10 < 5) and C.green or C.dark
    drawStr(W - 15, 2, "● ONLINE", dot, C.header)
    
    local clock = os.date("%d.%m.%Y %H:%M:%S")
    if clock ~= S.last_clock then
        S.last_clock = clock
        drawStr(W - ulen(clock) - 2, 3, clock, C.dim, C.header)
    end
    drawStr(1, 4, string.rep("═", W), C.border_br, C.header)
end

local function drawTabs()
    local tabs = {
        { id="exchange", label="ОБМЕН", icon="⇄" },
        { id="history", label="ИСТОРИЯ", icon="❐" },
        { id="stats", label="СТАТИСТИКА", icon="▤" },
        { id="settings", label="НАСТРОЙКИ", icon="⚙" },
    }
    local x = 2
    for _, t in ipairs(tabs) do
        local active = S.tab == t.id
        local w = ulen(t.label) + 6
        local bg = active and C.select or C.panel_light
        local fg = active and C.accent or C.dim
        
        drawStr(x, 5, (active and "▐" or " ") .. string.rep(" ", w-2) .. (active and "▌" or " "), active and C.border_br or C.border, bg)
        drawStr(x + 2, 5, t.icon .. " " .. t.label, fg, bg)
        
        S.boxes[#S.boxes+1] = { x=x, y=5, w=w, h=1, id=t.id, type="tab" }
        x = x + w + 1
    end
end

local function drawLeft()
    local lx, ly, lw, lh = 2, 7, 22, H - 12
    drawBoxBuf(lx, ly, lw, lh, "КАТЕГОРИИ", C.border, C.panel)
    
    local y = ly + 2
    for _, c in ipairs(categories) do
        local active = S.cat == c.id
        local bg = active and C.select or C.panel
        local fg = active and C.accent or C.dim
        drawStr(lx + 1, y, string.rep(" ", lw-2), fg, bg)
        drawStr(lx + 2, y, (active and "▸ " or "  ") .. c.icon .. " " .. c.label, fg, bg)
        
        S.boxes[#S.boxes+1] = { x=lx+1, y=y, w=lw-2, h=1, id=c.id, type="cat" }
        y = y + 1
    end
    
    drawStr(lx + 1, y + 1, string.rep("─", lw-2), C.border, C.panel)
    local iy = y + 3
    drawStr(lx + 2, iy, "СТАТИСТИКА", C.accent, C.panel)
    drawStr(lx + 2, iy+1, "Всего видов:", C.dim, C.panel)
    drawStr(lx + lw - 4, iy+1, tostring(#ores), C.cyan, C.panel)
    drawStr(lx + 2, iy+2, "Доступно:", C.dim, C.panel)
    
    local av = 0
    for _, o in ipairs(ores) do if o.avail then av = av + 1 end end
    drawStr(lx + lw - 4, iy+2, tostring(av), C.green, C.panel)
    drawStr(lx + 2, iy+3, "В МЭ:", C.dim, C.panel)
    drawStr(lx + lw - 4, iy+3, fmtNum(S.total_items), C.yellow, C.panel)
end

local function drawMain()
    local mx, my, mw, mh = 25, 7, 60, H - 12
    drawBoxBuf(mx, my, mw, mh, "ОБМЕН РЕСУРСОВ", C.border, C.panel)
    
    if S.tab == "exchange" then
        drawStr(mx + 2, my + 1, "ПОИСК:", C.dim, C.panel)
        local sbg = S.search_active and C.select or C.panel_light
        drawStr(mx + 9, my + 1, " " .. padR(S.search, 20) .. " ", C.text, sbg)
        S.boxes[#S.boxes+1] = { x=mx+9, y=my+1, w=20, h=1, id="search", type="input" }
        
        local hy = my + 3
        fillBuf(mx + 1, hy, mw - 2, 1, " ", C.text, C.panel_light)
        drawStr(mx + 2, hy, "#", C.dim, C.panel_light)
        drawStr(mx + 5, hy, "ВИД РУДЫ", C.dim, C.panel_light)
        drawStr(mx + 26, hy, "В МЭ", C.dim, C.panel_light)
        drawStr(mx + 34, hy, "КУРС", C.dim, C.panel_light)
        drawStr(mx + 46, hy, "ВЫДАЕТСЯ", C.dim, C.panel_light)
        
        local filtered = getFiltered()
        local max_r = mh - 5
        if S.selected > #filtered then S.selected = math.max(1, #filtered) end
        if S.selected < 1 then S.selected = 1 end
        if S.selected > S.scroll + max_r then S.scroll = S.selected - max_r end
        if S.selected <= S.scroll then S.scroll = S.selected - 1 end
        
        for i = 1, max_r do
            local idx = S.scroll + i
            local o = filtered[idx]
            if not o then break end
            
            local y = hy + 1 + i
            local active = (idx == S.selected)
            local bg = active and C.select or C.panel
            local fg = active and C.text or C.dim
            
            fillBuf(mx + 1, y, mw - 2, 1, " ", fg, bg)
            local cur = active and ((S.anim % 8 < 4) and "►" or " ") or " "
            drawStr(mx + 1, y, cur, C.accent, bg)
            drawStr(mx + 2, y, string.format("%02d", idx), fg, bg)
            drawStr(mx + 5, y, o.icon .. " " .. padR(o.name, 18), fg, bg)
            drawStr(mx + 26, y, fmtNum(o.stock), o.avail and C.cyan or C.red, bg)
            drawStr(mx + 34, y, o.take_amt .. " ► " .. o.give_amt, C.yellow, bg)
            drawStr(mx + 46, y, clip(o.give_id:gsub("^[^:]+:", ""), 12), o.avail and C.green or C.dark, bg)
            
            S.boxes[#S.boxes+1] = { x=mx+1, y=y, w=mw-2, h=1, id=idx, type="row" }
        end
        
    elseif S.tab == "history" then
        drawStr(mx + 2, my + 1, "ИСТОРИЯ ОПЕРАЦИЙ", C.accent, C.panel)
        if #S.history == 0 then
            drawStr(mx + 3, my + 3, "Нет записей. Совершите обмен.", C.dim, C.panel)
        else
            drawStr(mx + 3, my + 3, "ВРЕМЯ      ОПЕРАЦИЯ", C.dim, C.panel)
            for i = 1, math.min(#S.history, mh - 6) do
                local h = S.history[i]
                drawStr(mx + 3, my + 4 + i, h.time .. "   " .. clip(h.item, 35) .. " x" .. h.qty, C.text, C.panel)
            end
        end
    elseif S.tab == "stats" then
        drawStr(mx + 2, my + 1, "СТАТИСТИКА", C.accent, C.panel)
        drawStr(mx + 3, my + 3, "Всего видов руды:", C.dim, C.panel)
        drawStr(mx + 30, my + 3, tostring(#ores), C.cyan, C.panel)
        drawStr(mx + 3, my + 4, "Доступно к обмену:", C.dim, C.panel)
        local av = 0
        for _, o in ipairs(ores) do if o.avail then av = av + 1 end end
        drawStr(mx + 30, my + 4, tostring(av), C.green, C.panel)
        drawStr(mx + 3, my + 5, "Всего в МЭ:", C.dim, C.panel)
        drawStr(mx + 30, my + 5, fmtNum(S.total_items), C.yellow, C.panel)
    elseif S.tab == "settings" then
        drawStr(mx + 2, my + 1, "НАСТРОЙКИ", C.accent, C.panel)
        drawStr(mx + 3, my + 3, "[Звук] " .. (Config.sound and "ВКЛ" or "ВЫКЛ"), C.text, C.panel)
        drawStr(mx + 3, my + 4, "[Тема] " .. Config.theme, C.text, C.panel)
        drawStr(mx + 3, my + 5, "[Версия] 9.0 Ultimate", C.text, C.panel)
        drawStr(mx + 3, my + 6, "[Автор] KaRMa__", C.text, C.panel)
    end
end

local function drawRight()
    local rx, ry, rw, rh = 86, 7, 73, H - 12
    drawBoxBuf(rx, ry, rw, rh, "ДЕТАЛИ РЕСУРСА", C.border, C.panel)
    
    local filtered = getFiltered()
    local o = filtered[S.selected]
    if not o then
        drawStr(rx + 3, ry + 3, "Ресурс не выбран", C.dim, C.panel); return
    end
    
    local y = ry + 2
    drawStr(rx + 3, y, o.icon .. " " .. clip(o.name, rw - 6), C.accent, C.panel)
    y = y + 2
    drawStr(rx + 3, y, "В МЭ:", C.dim, C.panel)
    drawStr(rx + rw - 4, y, fmtNum(o.stock), o.avail and C.green or C.red, C.panel)
    y = y + 1
    drawStr(rx + 3, y, "Курс:", C.dim, C.panel)
    drawStr(rx + rw - 7, y, o.take_amt .. " ► " .. o.give_amt, C.yellow, C.panel)
    y = y + 1
    drawStr(rx + 3, y, "Выход:", C.dim, C.panel)
    drawStr(rx + 12, y, clip(o.give_id, rw - 15), C.cyan, C.panel)
    y = y + 2
    
    drawStr(rx + 1, y, string.rep("─", rw - 2), C.border, C.panel)
    y = y + 1
    drawStr(rx + 3, y, o.avail and "✓ ДОСТУПНО ДЛЯ ОБМЕНА" or "✗ НЕДОСТАТОЧНО В МЭ", o.avail and C.green or C.red, C.panel)
    
    y = y + 3
    if S.processing then
        drawStr(rx + 3, y, "ОБМЕН ВЫПОЛНЯЕТСЯ...", C.cyan, C.panel)
        drawStr(rx + 3, y + 2, "[", C.dim, C.panel)
        drawStr(rx + rw - 4, y + 2, "]", C.dim, C.panel)
        local fill_w = math.floor((rw - 7) * (S.progress / 100))
        fillBuf(rx + 4, y + 2, rw - 7, 1, " ", C.bg, C.panel_light)
        if fill_w > 0 then
            fillBuf(rx + 4, y + 2, fill_w, 1, " ", C.bg, C.cyan)
        end
    else
        local bw = rw - 6
        local btns = {
            { label="ОБМЕНЯТЬ", id="btn_exchange", enabled=o.avail, color=C.green },
            { label="ОБМЕНЯТЬ ВСЁ", id="btn_exchange_all", enabled=true, color=C.yellow },
            { label="ОБНОВИТЬ МЭ", id="btn_refresh", enabled=true, color=C.cyan },
        }
        for _, b in ipairs(btns) do
            local bg = b.enabled and C.panel_light or C.panel
            local fg = b.enabled and b.color or C.dark
            drawStr(rx + 3, y, string.rep(" ", bw), fg, bg)
            drawStr(rx + 3, y, "▐" .. string.rep(" ", bw-2) .. "▌", C.border, bg)
            local tx = rx + 3 + math.floor((bw - ulen(b.label)) / 2)
            drawStr(tx, y, b.label, fg, bg)
            
            if b.enabled then
                S.boxes[#S.boxes+1] = { x=rx+3, y=y, w=bw, h=1, id=b.id, type="btn" }
            end
            y = y + 1
        end
    end
end

local function drawBottom()
    local by = H - 4
    drawBoxBuf(2, by, W - 4, 3, "БЫСТРЫЕ ДЕЙСТВИЯ", C.border, C.panel)
    
    local bx = 3
    local quick = {
        { label="⇄ ОБМЕН",    id="quick_exchange" },
        { label="⇄ ВСЁ",      id="quick_all" },
        { label="↻ ОБНОВИТЬ", id="quick_refresh" },
        { label="❐ ИСТОРИЯ",  id="quick_history" },
        { label="⚙ НАСТРОЙКИ",id="quick_settings" },
    }
    for _, q in ipairs(quick) do
        local qw = ulen(q.label) + 4
        drawStr(bx, by+1, "▐" .. string.rep(" ", qw-2) .. "▌", C.border, C.panel_light)
        drawStr(bx+2, by+1, q.label, C.accent, C.panel_light)
        
        S.boxes[#S.boxes+1] = { x=bx, y=by+1, w=qw, h=1, id=q.id, type="quick" }
        bx = bx + qw + 1
    end
end

local function drawStatus()
    local sy = H - 2
    drawBoxBuf(2, sy, W - 4, 2, "СТАТУС", C.border, C.panel_light)
    
    local full = "● " .. S.status .. "  ●  PI SHOP v9.0  ●  Игрок: " .. S.player .. "  ●  "
    local len = ulen(full)
    S.marquee = (S.marquee + 2) % len
    local vw = W - 8
    local disp = ""
    for i = 1, vw do
        local ci = ((S.marquee + i - 2) % len) + 1
        disp = disp .. unicode.sub(full, ci, ci)
    end
    drawStr(4, sy+1, disp, S.status_col, C.panel_light)
end

local function drawAll()
    clearBuf(C.bg)
    S.boxes = {}
    
    drawHeader()
    drawTabs()
    drawLeft()
    drawMain()
    drawRight()
    drawBottom()
    drawStatus()
end

-- === ВВОД ===
local function hitTest(x, y)
    for i = #S.boxes, 1, -1 do
        local b = S.boxes[i]
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            return b
        end
    end
    return nil
end

local function handleClick(x, y)
    local b = hitTest(x, y)
    if not b then return end
    
    if b.type == "tab" then
        S.tab = b.id
    elseif b.type == "cat" then
        S.cat = b.id; S.selected = 1; S.scroll = 0
    elseif b.type == "row" then
        S.selected = b.id
    elseif b.type == "input" then
        S.search_active = true
    elseif b.type == "btn" then
        if b.id == "btn_exchange" then
            doExchange(getFiltered()[S.selected])
        elseif b.id == "btn_exchange_all" then
            doExchangeAll()
        elseif b.id == "btn_refresh" then
            refreshME()
        end
    elseif b.type == "quick" then
        if b.id == "quick_exchange" then doExchange(getFiltered()[S.selected])
        elseif b.id == "quick_all" then doExchangeAll()
        elseif b.id == "quick_refresh" then refreshME()
        elseif b.id == "quick_history" then S.tab = "history"
        elseif b.id == "quick_settings" then S.tab = "settings" end
    end
end

local function handleKey(char, code)
    if code == 1 then 
        S.search_active = false
        return
    end
    
    if S.search_active then
        if code == 28 then 
            S.search_active = false
        elseif code == 14 then 
            S.search = unicode.sub(S.search, 1, -2)
            S.selected = 1; S.scroll = 0
        elseif char >= 32 and char <= 126 then
            S.search = S.search .. string.char(char)
            S.selected = 1; S.scroll = 0
        end
        return
    end
    
    local key = (char >= 32 and char <= 126) and string.char(char):lower() or ""
    if code == 200 then S.selected = math.max(1, S.selected - 1)
    elseif code == 208 then S.selected = math.min(#getFiltered(), S.selected + 1)
    elseif key == "r" then refreshME()
    elseif key == "e" then doExchange(getFiltered()[S.selected])
    elseif key == "a" then doExchangeAll()
    end
end

-- === ГЛАВНЫЙ ЦИКЛ ===
local function main()
    initBuffers()
    refreshME()
    drawAll()
    flushBuf()
    
    local last_anim = computer.uptime()
    
    while true do
        local ev, p1, p2, p3, p4 = event.pull(0.05)
        
        if ev == "touch" then handleClick(p3, p4)
        elseif ev == "key_down" then handleKey(p3, p4)
        elseif ev == "player_on" or ev == "pim_player_enter" then
            S.player = p1 or "?"
            S.status = "Приветствую, " .. S.player .. "!"
            S.status_col = C.accent
            refreshME()
        elseif ev == "player_off" or ev == "pim_player_leave" then
            S.player = "---"
            S.status = "Ожидание игрока..."
            S.status_col = C.cyan
        end
        
        local now = computer.uptime()
        
        if now - last_anim >= 0.05 then
            S.anim = S.anim + 1
            last_anim = now
            
            if S.processing then
                S.progress = S.progress + 5
                if S.progress >= 100 then
                    if S.pending_exchange then processExchange() end
                    if S.pending_all then processExchangeAll() end
                end
            end
            
            drawAll()
            flushBuf()
        end
    end
end

local ok, err = pcall(main)
if not ok then
    gpu.setBackground(C.bg); gpu.setForeground(C.red)
    gpu.fill(1, 1, W, H, " ")
    gpu.set(2, 2, "КРИТИЧЕСКАЯ ОШИБКА: " .. tostring(err))
    os.sleep(10)
end
