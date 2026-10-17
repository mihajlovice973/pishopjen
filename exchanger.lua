-- ============================================================
-- PI SHOP v7.0 — ПОЛНОСТЬЮ НОВЫЙ GUI (FIXED)
-- Тёмно-фиолетовая тема • множество функций • анимации
-- ============================================================
local component = require("component")
local event = require("event")
local computer = require("computer")
local unicode = require("unicode")
local gpu = component.gpu
local pim = component.isAvailable("pim") and component.pim or nil
local me = component.isAvailable("me_interface") and component.me_interface or nil

local W, H = 160, 50
local maxW, maxH = gpu.maxResolution()
if maxW < 160 then W, H = maxW, maxH end
pcall(gpu.setResolution, W, H)
W, H = gpu.getResolution()

local C = {
    bg=0x08030F, panel=0x150826, panel_med=0x1E0F35, panel_light=0x2D1B4E,
    border=0x6A0DAD, border_br=0x9D4EDD, accent=0xC792EA, glow=0xE0AAFF,
    text=0xF2F0F8, text_dim=0x8A7FA8, text_muted=0x5A4A75,
    green=0x00FF88, red=0xFF4D6D, yellow=0xFFD166, cyan=0x00E5FF,
    select=0x4A2B7A, header=0x1A0B2E,
}

local S = {
    tab="exchange", category="all", selected=1, scroll=0, anim=0, marquee=0,
    status="PI SHOP готов к работе", status_col=0x00E5FF, player="---",
    total_items=0, history={}, modal=nil,
    tab_boxes={}, cat_boxes={}, row_boxes={}, btn_boxes={}, quick_boxes={}, modal_boxes={},
}

-- ЗАМЕНИЛ in= НА input= (Lua-ключевое слово!)
local ores = {
    { cat="precious", name="Алмазная руда", input="minecraft:diamond_ore", out="minecraft:diamond", ri=1, ro=2, icon="💎" },
    { cat="precious", name="Изумрудная руда", input="minecraft:emerald_ore", out="minecraft:emerald", ri=1, ro=2, icon="💚" },
    { cat="precious", name="Золотая руда", input="minecraft:gold_ore", out="minecraft:gold_ingot", ri=3, ro=7, icon="🟡" },
    { cat="precious", name="Серебряная руда", input="ThermalFoundation:Ore", di=2, out="IC2:itemIngot", do_=6, ri=1, ro=2, icon="⚪" },
    { cat="precious", name="Платиновая руда", input="ThermalFoundation:Ore", di=5, out="ThermalFoundation:material", do_=37, ri=1, ro=2, icon="🔘" },
    { cat="metals", name="Железная руда", input="minecraft:iron_ore", out="minecraft:iron_ingot", ri=3, ro=7, icon="⬜" },
    { cat="metals", name="Медная руда", input="IC2:blockOreCopper", out="IC2:itemIngot", ri=3, ro=7, icon="🟠" },
    { cat="metals", name="Оловянная руда", input="IC2:blockOreTin", out="IC2:itemIngot", do_=1, ri=3, ro=7, icon="🔵" },
    { cat="metals", name="Никелевая руда", input="ThermalFoundation:Ore", di=4, out="ThermalFoundation:material", do_=68, ri=1, ro=2, icon="🟢" },
    { cat="other", name="Угольная руда", input="minecraft:coal_ore", out="minecraft:coal", ri=1, ro=3, icon="⚫" },
    { cat="other", name="Красная руда", input="minecraft:redstone_ore", out="minecraft:redstone_block", ri=1, ro=1, icon="🔴" },
    { cat="magic", name="Лазуритовая руда", input="minecraft:lapis_ore", out="minecraft:dye", do_=4, ri=1, ro=7, icon="🔷" },
    { cat="magic", name="Кварцевая руда", input="minecraft:quartz_ore", out="minecraft:quartz", ri=1, ro=4, icon="⬛" },
    { cat="magic", name="Дракониевая руда", input="DraconicEvolution:draconiumOre", out="DraconicEvolution:draconiumDust", ri=1, ro=2, icon="🐉" },
}
for _, o in ipairs(ores) do o.stock=0; o.avail=false; o.max_stack=64 end

local function ulen(t) return unicode.len(tostring(t or "")) end
local function clip(t, w)
    t = tostring(t or "")
    if ulen(t) <= w then return t end
    return unicode.sub(t, 1, w - 1) .. "…"
end
local function padR(t, w)
    t = clip(t, w)
    return t .. string.rep(" ", math.max(0, w - ulen(t)))
end
local function wt(x, y, t, fg, bg)
    if y < 1 or y > H or x > W or x < 1 then return end
    if bg then gpu.setBackground(bg) end
    if fg then gpu.setForeground(fg) end
    gpu.set(x, y, tostring(t))
end
local function fr(x, y, w, h, bg)
    if w <= 0 or h <= 0 then return end
    gpu.setBackground(bg); gpu.fill(x, y, w, h, " ")
end
local function box(x, y, w, h, col, bg)
    fr(x, y, w, h, bg)
    gpu.setForeground(col); gpu.setBackground(bg)
    gpu.set(x, y, "┌" .. string.rep("─", w - 2) .. "┐")
    gpu.set(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
    for i = 1, h - 2 do
        gpu.set(x, y + i, "│")
        gpu.set(x + w - 1, y + i, "│")
    end
end
local function fmtNum(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(math.floor(n))
end

local categories = {
    { id="all", label="ВСЕ РУДЫ", icon="◆" },
    { id="precious", label="ДРАГОЦЕННЫЕ", icon="💎" },
    { id="metals", label="МЕТАЛЛЫ", icon="⚙" },
    { id="magic", label="МАГИЯ", icon="✦" },
    { id="other", label="ПРОЧИЕ", icon="■" },
}

local HDR_Y, HDR_H = 1, 4
local TAB_Y = 5
local L_X, L_Y, L_W = 2, 7, 22
local M_X = L_X + L_W + 1
local M_W = math.floor((W - 40) * 0.68)
local R_X = M_X + M_W + 1
local R_W = W - R_X - 1
local CT_Y = L_Y
local CT_H = H - CT_Y - 8
local BOT_Y = H - 6
local ST_Y = H - 3
local FT_Y = H

local function getFiltered()
    local t = {}
    for _, o in ipairs(ores) do
        if S.category == "all" or o.cat == S.category then t[#t + 1] = o end
    end
    return t
end

local function refreshME()
    if not me then
        S.status = "МЭ не подключена"; S.status_col = C.red; return
    end
    S.total_items = 0
    for _, o in ipairs(ores) do
        local ok, item = pcall(function()
            return me.getItemDetail({ id=o.out, dmg=o.do_ or 0 }).basic()
        end)
        if ok and item then
            o.stock = item.qty
            o.max_stack = item.max_size or 64
            o.avail = item.qty >= (o.ro or 1)
            S.total_items = S.total_items + item.qty
        else
            o.stock=0; o.avail=false; o.max_stack=64
        end
    end
    S.status = "Данные МЭ обновлены"; S.status_col = C.green
end

local function drawHeader()
    fr(1, HDR_Y, W, HDR_H, C.header)
    local pulse = (S.anim % 20 < 10)
    wt(3, HDR_Y + 1, "◆ PI SHOP ◆", pulse and C.glow or C.accent, C.header)
    wt(3, HDR_Y + 2, "RESOURCE EXCHANGER v7.0", C.text_dim, C.header)
    for i = 1, 6 do
        local bx = W - 50 + (i - 1) * 6
        local col = (math.floor((S.anim + i * 3) / 5) % 2 == 0) and C.accent or C.border
        wt(bx, HDR_Y + 1, "▬▬▬", col, C.header)
    end
    local dot = (S.anim % 10 < 5) and C.green or C.text_muted
    wt(W - 14, HDR_Y + 1, "● ONLINE", dot, C.header)
    local clock = os.date("%d.%m.%Y %H:%M:%S")
    wt(W - ulen(clock) - 2, HDR_Y + 2, clock, C.text_dim, C.header)
    gpu.setForeground(C.border_br); gpu.setBackground(C.bg)
    gpu.set(1, HDR_Y + HDR_H, string.rep("═", W))
end

local function drawTabs()
    local tabs = {
        { id="exchange", label="ОБМЕН", icon="⇄" },
        { id="history", label="ИСТОРИЯ", icon="❐" },
        { id="stats", label="СТАТИСТИКА", icon="▤" },
        { id="settings", label="НАСТРОЙКИ", icon="⚙" },
    }
    S.tab_boxes = {}
    local x = 2
    for _, t in ipairs(tabs) do
        local active = S.tab == t.id
        local w = ulen(t.label) + 6
        local bg = active and C.select or C.panel_med
        local fg = active and C.accent or C.text_dim
        fr(x, TAB_Y, w, 1, bg)
        gpu.setForeground(active and C.border_br or C.border)
        gpu.setBackground(bg)
        gpu.set(x, TAB_Y, (active and "▐" or " ") .. string.rep(" ", w - 2) .. (active and "▌" or " "))
        wt(x + 2, TAB_Y, t.icon .. " " .. t.label, fg, bg)
        S.tab_boxes[#S.tab_boxes + 1] = { x=x, y=TAB_Y, w=w, h=1, id=t.id }
        x = x + w + 1
    end
end

local function drawLeft()
    box(L_X, L_Y, L_W, CT_H, C.border, C.panel)
    wt(L_X + 2, L_Y, " КАТЕГОРИИ ", C.accent, C.panel)
    S.cat_boxes = {}
    local y = L_Y + 2
    for _, c in ipairs(categories) do
        local active = S.category == c.id
        local bg = active and C.select or C.panel
        local fg = active and C.accent or C.text_dim
        fr(L_X + 1, y, L_W - 2, 1, bg)
        local prefix = active and "▸ " or "  "
        wt(L_X + 2, y, prefix .. c.icon .. " " .. c.label, fg, bg)
        S.cat_boxes[#S.cat_boxes + 1] = { x=L_X + 1, y=y, w=L_W - 2, h=1, id=c.id }
        y = y + 1
    end
    gpu.setForeground(C.border); gpu.setBackground(C.panel)
    gpu.set(L_X + 1, y + 1, string.rep("─", L_W - 2))
    local iy = y + 3
    wt(L_X + 2, iy, "СТАТИСТИКА", C.accent, C.panel)
    wt(L_X + 2, iy + 1, "Всего видов:", C.text_dim, C.panel)
    wt(L_X + L_W - 4, iy + 1, tostring(#ores), C.accent, C.panel)
    wt(L_X + 2, iy + 2, "Доступно:", C.text_dim, C.panel)
    local av = 0
    for _, o in ipairs(ores) do if o.avail then av = av + 1 end end
    wt(L_X + L_W - 4, iy + 2, tostring(av), C.green, C.panel)
    wt(L_X + 2, iy + 3, "В МЭ:", C.text_dim, C.panel)
    wt(L_X + L_W - 4, iy + 3, fmtNum(S.total_items), C.cyan, C.panel)
end

local function drawMain()
    S.row_boxes = {}
    box(M_X, CT_Y, M_W, CT_H, C.border, C.panel)
    if S.tab == "exchange" then
        wt(M_X + 2, CT_Y, " ОБМЕН РЕСУРСОВ ", C.accent, C.panel)
        local hy = CT_Y + 2
        fr(M_X + 1, hy, M_W - 2, 1, C.panel_light)
        wt(M_X + 2, hy, "#", C.text_dim, C.panel_light)
        wt(M_X + 5, hy, "ВИД РУДЫ", C.text_dim, C.panel_light)
        wt(M_X + 26, hy, "В МЭ", C.text_dim, C.panel_light)
        wt(M_X + 34, hy, "КУРС", C.text_dim, C.panel_light)
        wt(M_X + 46, hy, "ВЫДАЕТСЯ", C.text_dim, C.panel_light)
        local filtered = getFiltered()
        local max_r = CT_H - 5
        if S.selected > #filtered then S.selected = math.max(1, #filtered) end
        if S.selected < 1 then S.selected = 1 end
        if S.selected > S.scroll + max_r then S.scroll = S.selected - max_r end
        if S.selected <= S.scroll then S.scroll = S.selected - 1 end
        for i = 1, max_r do
            local idx = S.scroll + i
            local o = filtered[idx]
            if not o then break end
            local y = hy + 2 + i - 1
            local active = (idx == S.selected)
            local bg = active and C.select or C.panel
            local fg = active and C.text or C.text_dim
            fr(M_X + 1, y, M_W - 2, 1, bg)
            local cur = active and ((S.anim % 8 < 4) and "►" or " ") or " "
            wt(M_X + 1, y, cur, C.accent, bg)
            wt(M_X + 2, y, string.format("%02d", idx), fg, bg)
            wt(M_X + 5, y, o.icon .. " " .. padR(o.name, 18), fg, bg)
            wt(M_X + 26, y, fmtNum(o.stock), o.avail and C.cyan or C.red, bg)
            wt(M_X + 34, y, o.ri .. " ► " .. o.ro, C.yellow, bg)
            wt(M_X + 46, y, clip(o.out:gsub("^[^:]+:", ""), 15), o.avail and C.green or C.text_muted, bg)
            S.row_boxes[#S.row_boxes + 1] = { x=M_X + 1, y=y, w=M_W - 2, h=1, id=idx }
        end
    elseif S.tab == "history" then
        wt(M_X + 2, CT_Y, " ИСТОРИЯ ОПЕРАЦИЙ ", C.accent, C.panel)
        if #S.history == 0 then
            wt(M_X + 3, CT_Y + 3, "Нет истории операций", C.text_dim, C.panel)
            wt(M_X + 3, CT_Y + 4, "Обменяйте что-нибудь, чтобы появились записи", C.text_muted, C.panel)
        else
            wt(M_X + 3, CT_Y + 2, "ВРЕМЯ      ОПЕРАЦИЯ", C.text_dim, C.panel)
            for i = 1, math.min(#S.history, CT_H - 5) do
                local h = S.history[i]
                wt(M_X + 3, CT_Y + 3 + i, h.time .. "   " .. clip(h.item, 40) .. " x" .. h.qty, C.text, C.panel)
            end
        end
    elseif S.tab == "stats" then
        wt(M_X + 2, CT_Y, " СТАТИСТИКА ", C.accent, C.panel)
        local sy = CT_Y + 3
        wt(M_X + 3, sy, "📊 Общая статистика", C.accent, C.panel)
        wt(M_X + 3, sy + 2, "Всего видов руды:", C.text_dim, C.panel)
        wt(M_X + 30, sy + 2, tostring(#ores), C.cyan, C.panel)
        local av = 0
        for _, o in ipairs(ores) do if o.avail then av = av + 1 end end
        wt(M_X + 3, sy + 3, "Доступно к обмену:", C.text_dim, C.panel)
        wt(M_X + 30, sy + 3, tostring(av), C.green, C.panel)
        wt(M_X + 3, sy + 4, "Всего в МЭ:", C.text_dim, C.panel)
        wt(M_X + 30, sy + 4, fmtNum(S.total_items), C.yellow, C.panel)
        wt(M_X + 3, sy + 6, "📦 По категориям:", C.accent, C.panel)
        local yy = sy + 8
        for _, c in ipairs(categories) do
            if c.id ~= "all" then
                local cnt, stock = 0, 0
                for _, o in ipairs(ores) do
                    if o.cat == c.id then cnt = cnt + 1; stock = stock + o.stock end
                end
                wt(M_X + 3, yy, c.icon .. " " .. c.label, C.text, C.panel)
                wt(M_X + 25, yy, cnt .. " видов", C.text_dim, C.panel)
                wt(M_X + 38, yy, fmtNum(stock) .. " шт", C.cyan, C.panel)
                yy = yy + 1
            end
        end
    elseif S.tab == "settings" then
        wt(M_X + 2, CT_Y, " НАСТРОЙКИ ", C.accent, C.panel)
        wt(M_X + 3, CT_Y + 3, "⚙ Информация", C.accent, C.panel)
        wt(M_X + 3, CT_Y + 5, "• Тема: Dark Purple", C.text, C.panel)
        wt(M_X + 3, CT_Y + 6, "• Версия: 7.0", C.text, C.panel)
        wt(M_X + 3, CT_Y + 7, "• Автор: KaRMa__", C.text, C.panel)
        wt(M_X + 3, CT_Y + 9, "⌨ Горячие клавиши:", C.accent, C.panel)
        wt(M_X + 3, CT_Y + 11, "  R     - Обновить МЭ", C.text_dim, C.panel)
        wt(M_X + 3, CT_Y + 12, "  E     - Обменять выбранное", C.text_dim, C.panel)
        wt(M_X + 3, CT_Y + 13, "  A     - Обменять ВСЁ", C.text_dim, C.panel)
        wt(M_X + 3, CT_Y + 14, "  ↑↓    - Навигация", C.text_dim, C.panel)
        wt(M_X + 3, CT_Y + 15, "  Tab   - Вкладки", C.text_dim, C.panel)
        wt(M_X + 3, CT_Y + 16, "  1-5   - Категории", C.text_dim, C.panel)
        wt(M_X + 3, CT_Y + 17, "  Esc   - Закрыть модал", C.text_dim, C.panel)
    end
end

local function drawRight()
    box(R_X, CT_Y, R_W, CT_H, C.border, C.panel)
    wt(R_X + 2, CT_Y, " ДЕТАЛИ ", C.accent, C.panel)
    local filtered = getFiltered()
    local o = filtered[S.selected]
    if not o then
        wt(R_X + 3, CT_Y + 3, "Выберите ресурс", C.text_dim, C.panel); return
    end
    local y = CT_Y + 2
    wt(R_X + 3, y, o.icon .. " " .. clip(o.name, R_W - 6), C.accent, C.panel)
    y = y + 2
    wt(R_X + 3, y, "В МЭ:", C.text_dim, C.panel)
    wt(R_X + R_W - 4, y, fmtNum(o.stock), o.avail and C.green or C.red, C.panel)
    y = y + 1
    wt(R_X + 3, y, "Курс:", C.text_dim, C.panel)
    wt(R_X + R_W - 6, y, o.ri .. " ► " .. o.ro, C.yellow, C.panel)
    y = y + 1
    wt(R_X + 3, y, "Выход:", C.text_dim, C.panel)
    wt(R_X + 12, y, clip(o.out, R_W - 14), C.cyan, C.panel)
    y = y + 2
    gpu.setForeground(C.border); gpu.setBackground(C.panel)
    gpu.set(R_X + 1, y, string.rep("─", R_W - 2))
    y = y + 1
    wt(R_X + 3, y, o.avail and "✓ ДОСТУПНО" or "✗ НЕТ В МЭ", o.avail and C.green or C.red, C.panel)
    y = y + 2
    S.btn_boxes = {}
    local bw = R_W - 4
    local btns = {
        { label="ОБМЕНЯТЬ", id="btn_exchange", enabled=o.avail, color=C.green },
        { label="ОБМЕНЯТЬ ВСЁ", id="btn_exchange_all", enabled=true, color=C.yellow },
        { label="ОБНОВИТЬ МЭ", id="btn_refresh", enabled=true, color=C.cyan },
    }
    for _, b in ipairs(btns) do
        local bg = b.enabled and C.panel_med or C.panel
        local fg = b.enabled and b.color or C.text_muted
        fr(R_X + 2, y, bw, 1, bg)
        gpu.setForeground(C.border); gpu.setBackground(bg)
        gpu.set(R_X + 2, y, "▐" .. string.rep(" ", bw - 2) .. "▌")
        wt(R_X + 2 + math.floor((bw - ulen(b.label)) / 2), y, b.label, fg, bg)
        S.btn_boxes[#S.btn_boxes + 1] = { x=R_X + 2, y=y, w=bw, h=1, id=b.id, enabled=b.enabled }
        y = y + 1
    end
    y = y + 1
    wt(R_X + 3, y, "⌨ E - обменять", C.text_muted, C.panel)
end

local function drawBottom()
    box(2, BOT_Y, W - 4, 3, C.border, C.panel)
    wt(3, BOT_Y, " БЫСТРЫЕ ДЕЙСТВИЯ ", C.accent, C.panel)
    S.quick_boxes = {}
    local by = BOT_Y + 1
    local bx = 3
    local quick = {
        { label="⇄ ОБМЕН",    id="quick_exchange" },
        { label="⇄ ВСЁ",      id="quick_all" },
        { label="↻ ОБНОВИТЬ", id="quick_refresh" },
        { label="❐ ИСТОРИЯ",  id="quick_history" },
        { label="⚙ НАСТРОЙКИ",id="quick_settings" },
        { label="? ПОМОЩЬ",   id="quick_help" },
    }
    for _, q in ipairs(quick) do
        local qw = ulen(q.label) + 4
        fr(bx, by, qw, 1, C.panel_med)
        gpu.setForeground(C.border); gpu.setBackground(C.panel_med)
        gpu.set(bx, by, "▐" .. string.rep(" ", qw - 2) .. "▌")
        wt(bx + 2, by, q.label, C.accent, C.panel_med)
        S.quick_boxes[#S.quick_boxes + 1] = { x=bx, y=by, w=qw, h=1, id=q.id }
        bx = bx + qw + 1
    end
end

local function drawStatus()
    fr(2, ST_Y, W - 4, 3, C.panel_light)
    gpu.setForeground(C.border_br); gpu.setBackground(C.panel_light)
    gpu.set(2, ST_Y, "│")
    for i = 1, 2 do gpu.set(2, ST_Y + i, "│") end
    local full = "● " .. S.status .. "  ●  PI SHOP v7.0  ●  Игрок: " .. S.player .. "  ●  "
    local len = ulen(full)
    S.marquee = (S.marquee + 1) % len
    local vw = W - 8
    local disp = ""
    for i = 1, vw do
        local ci = ((S.marquee + i - 2) % len) + 1
        disp = disp .. unicode.sub(full, ci, ci)
    end
    wt(4, ST_Y, disp, S.status_col, C.panel_light)
    wt(4, ST_Y + 2, "Для обмена встаньте на PIM • Клик по элементу для выбора", C.text_dim, C.panel_light)
end

local function drawFooter()
    fr(1, FT_Y, W, 1, C.select)
    gpu.setForeground(C.border_br); gpu.setBackground(C.select)
    gpu.set(1, FT_Y, string.rep("─", W))
    wt(W - 30, FT_Y, "[ " .. S.player .. " ] [ v7.0 ]", C.text, C.select)
    wt(2, FT_Y, "◆ PI SHOP", C.accent, C.select)
end

local function drawModal()
    if not S.modal then return end
    local mw, mh = 50, 10
    local mx = math.floor((W - mw) / 2)
    local my = math.floor((H - mh) / 2)
    box(mx, my, mw, mh, C.border_br, C.panel_light)
    S.modal_boxes = {}
    if S.modal == "confirm" then
        wt(mx + 2, my, " ПОДТВЕРЖДЕНИЕ ", C.accent, C.panel_light)
        wt(mx + 3, my + 3, "Обменять ВСЕ доступные ресурсы?", C.text, C.panel_light)
        wt(mx + 3, my + 4, "Это действие нельзя отменить.", C.text_dim, C.panel_light)
        wt(mx + 5, my + 7, "[ENTER] Да", C.green, C.panel_light)
        wt(mx + 20, my + 7, "[ESC] Отмена", C.red, C.panel_light)
        S.modal_boxes[#S.modal_boxes + 1] = { x=mx + 4, y=my + 7, w=12, h=1, id="modal_yes" }
        S.modal_boxes[#S.modal_boxes + 1] = { x=mx + 19, y=my + 7, w=13, h=1, id="modal_no" }
    elseif S.modal == "help" then
        wt(mx + 2, my, " ПОМОЩЬ ", C.accent, C.panel_light)
        wt(mx + 3, my + 3, "R  - Обновить МЭ", C.text, C.panel_light)
        wt(mx + 3, my + 4, "E  - Обменять выбранное", C.text, C.panel_light)
        wt(mx + 3, my + 5, "A  - Обменять всё", C.text, C.panel_light)
        wt(mx + 3, my + 6, "1-5 - Категории", C.text, C.panel_light)
        wt(mx + 3, my + 7, "ESC - Закрыть", C.text, C.panel_light)
        S.modal_boxes[#S.modal_boxes + 1] = { x=mx + 2, y=my + mh - 2, w=mw - 4, h=1, id="modal_close" }
    end
end

local function drawAll()
    fr(1, 1, W, H, C.bg)
    drawHeader()
    drawTabs()
    drawLeft()
    drawMain()
    drawRight()
    drawBottom()
    drawStatus()
    drawFooter()
    drawModal()
end

local function doExchange(o)
    if not pim or not me then
        S.status = "Ошибка: PIM или МЭ не подключены"; S.status_col = C.red; return
    end
    if not o.avail then
        S.status = "Нет " .. o.name .. " в МЭ"; S.status_col = C.red; return
    end
    local slots = pim.getInventorySize()
    local data = pim.getAllStacks(0)
    local out = 0
    for slot = 1, slots do
        local s = data[slot]
        if s and s.id == o.input and (s.dmg or 0) == (o.di or 0) then
            local take = s.qty - (s.qty % o.ri)
            if take > 0 then
                local need = (take / o.ri) * o.ro
                if o.stock >= need then
                    local ok, got = pcall(pim.pushItem, "DOWN", slot, take)
                    if ok and got and got > 0 then
                        local give = math.floor(got / o.ri) * o.ro
                        local ok2, res = pcall(me.exportItem, { id=o.out, dmg=o.do_ or 0 }, "UP", give)
                        if ok2 and res and res.size then out = out + res.size end
                    end
                end
            end
        end
    end
    if out > 0 then
        S.status = "Обменяно: " .. out .. " шт (" .. o.name .. ")"; S.status_col = C.green
        table.insert(S.history, 1, { time=os.date("%H:%M:%S"), item=o.name, qty=out })
        if #S.history > 100 then table.remove(S.history) end
    else
        S.status = "Нет подходящих ресурсов в инвентаре"; S.status_col = C.yellow
    end
end

local function doExchangeAll()
    local f = getFiltered()
    local cnt = 0
    for _, o in ipairs(f) do
        if o.avail then doExchange(o); cnt = cnt + 1 end
    end
    if cnt > 0 then
        S.status = "Обменяно " .. cnt .. " видов ресурсов"; S.status_col = C.green
    end
end

local function hitTest(x, y, boxes)
    if not boxes then return nil end
    for _, b in ipairs(boxes) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b.id end
    end
    return nil
end

local function handleClick(x, y)
    if S.modal then
        local id = hitTest(x, y, S.modal_boxes)
        if id == "modal_yes" then doExchangeAll(); S.modal = nil
        elseif id == "modal_no" or id == "modal_close" then S.modal = nil
        else S.modal = nil end
        return
    end
    local tid = hitTest(x, y, S.tab_boxes)
    if tid then S.tab = tid; S.selected = 1; S.scroll = 0; return end
    local cid = hitTest(x, y, S.cat_boxes)
    if cid then S.category = cid; S.selected = 1; S.scroll = 0; return end
    local rid = hitTest(x, y, S.row_boxes)
    if rid then S.selected = rid; return end
    local bid = hitTest(x, y, S.btn_boxes)
    if bid == "btn_exchange" then
        local f = getFiltered()
        if f[S.selected] then doExchange(f[S.selected]) end
        return
    elseif bid == "btn_exchange_all" then S.modal = "confirm"; return
    elseif bid == "btn_refresh" then refreshME(); return
    end
    local qid = hitTest(x, y, S.quick_boxes)
    if qid == "quick_exchange" then
        local f = getFiltered()
        if f[S.selected] then doExchange(f[S.selected]) end
    elseif qid == "quick_all" then S.modal = "confirm"
    elseif qid == "quick_refresh" then refreshME()
    elseif qid == "quick_history" then S.tab = "history"
    elseif qid == "quick_settings" then S.tab = "settings"
    elseif qid == "quick_help" then S.modal = "help" end
end

local function handleKey(char, code)
    if S.modal then
        if code == 28 then
            if S.modal == "confirm" then doExchangeAll() end
            S.modal = nil
        elseif code == 1 then S.modal = nil end
        return
    end
    local key = (char and char >= 32 and char <= 126) and string.char(char):lower() or ""
    if code == 200 then S.selected = math.max(1, S.selected - 1)
    elseif code == 208 then S.selected = math.min(#getFiltered(), S.selected + 1)
    elseif key == "r" then refreshME()
    elseif key == "e" then
        local f = getFiltered()
        if f[S.selected] then doExchange(f[S.selected]) end
    elseif key == "a" then S.modal = "confirm"
    elseif code == 15 then
        local tabs = { "exchange", "history", "stats", "settings" }
        for i, t in ipairs(tabs) do
            if t == S.tab then S.tab = tabs[(i % #tabs) + 1]; break end
        end
    elseif char and char >= 49 and char <= 53 then
        if categories[char - 48] then
            S.category = categories[char - 48].id
            S.selected = 1; S.scroll = 0
        end
    end
end

local function main()
    refreshME()
    drawAll()
    local last_anim = computer.uptime()
    while true do
        local ev, p1, p2, p3, p4 = event.pull(0.1)
        if ev == "touch" then handleClick(p3, p4)
        elseif ev == "key_down" then handleKey(p3, p4)
        elseif ev == "player_on" or ev == "pim_player_enter" then
            S.player = p1 or "?"
            S.status = "Приветствую " .. S.player .. "! Сканирование..."
            S.status_col = C.accent
            refreshME()
        elseif ev == "player_off" or ev == "pim_player_leave" then
            S.player = "---"
            S.status = "Ожидание игрока..."
            S.status_col = C.cyan
        end
        local now = computer.uptime()
        if now - last_anim >= 0.15 then
            S.anim = S.anim + 1
            last_anim = now
            drawAll()
        end
    end
end

local ok, err = pcall(main)
if not ok then
    gpu.setBackground(C.bg); gpu.setForeground(C.red)
    gpu.fill(1, 1, W, H, " ")
    gpu.set(2, 2, "Ошибка PI SHOP: " .. tostring(err))
    os.sleep(5)
end
