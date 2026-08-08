-- oc_gui.lua
-- Complete GUI Framework for OpenComputers
-- Includes: Core GUI + 5 Example Interfaces
-- Single file, ready to run

local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local fs = require("filesystem")
local gpu = component.gpu

-- ============================================
-- PART 1: COLOR CONSTANTS
-- ============================================

local COLORS = {
    WHITE = 0xFFFFFF,
    BLACK = 0x000000,
    RED = 0xFF0000,
    GREEN = 0x00FF00,
    BLUE = 0x0000FF,
    YELLOW = 0xFFFF00,
    CYAN = 0x00FFFF,
    MAGENTA = 0xFF00FF,
    GRAY = 0x808080,
    DARK_GRAY = 0x404040,
    LIGHT_GRAY = 0xC0C0C0,
    DARK_BLUE = 0x000080,
    DARK_GREEN = 0x008000,
    DARK_RED = 0x800000,
    DARK_CYAN = 0x008080,
    DARK_MAGENTA = 0x800080,
    DARK_YELLOW = 0x808000,
    ORANGE = 0xFF8800,
    PURPLE = 0x8800FF,
    PINK = 0xFF00FF,
    TRANSPARENT = nil
}

-- ============================================
-- PART 2: BASE COMPONENT CLASS
-- ============================================

local Component = {}
Component.__index = Component

function Component:new(params)
    params = params or {}
    local obj = {
        x = params.x or 0,
        y = params.y or 0,
        width = params.width or 10,
        height = params.height or 1,
        bgColor = params.bgColor or COLORS.DARK_GRAY,
        fgColor = params.fgColor or COLORS.WHITE,
        borderColor = params.borderColor or COLORS.GRAY,
        visible = params.visible ~= false,
        enabled = params.enabled ~= false,
        parent = nil,
        children = {},
        focused = false,
        hover = false,
        onClick = params.onClick,
        onFocus = params.onFocus,
        onBlur = params.onBlur,
        onKey = params.onKey,
        onMouse = params.onMouse,
        data = params.data or {},
        id = params.id or tostring(computer.uptime())
    }
    setmetatable(obj, Component)
    return obj
end

function Component:addChild(child)
    child.parent = self
    table.insert(self.children, child)
    return child
end

function Component:removeChild(child)
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.parent = nil
            return true
        end
    end
    return false
end

function Component:getAbsoluteX()
    local x = self.x
    if self.parent then
        x = x + self.parent:getAbsoluteX()
    end
    return x
end

function Component:getAbsoluteY()
    local y = self.y
    if self.parent then
        y = y + self.parent:getAbsoluteY()
    end
    return y
end

function Component:contains(x, y)
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    return x >= ax and x < ax + self.width and y >= ay and y < ay + self.height
end

function Component:draw()
    -- Override in child classes
end

function Component:drawBorder()
    if not self.visible then return end
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    if self.borderColor then
        gpu.setForeground(self.borderColor)
        gpu.setBackground(self.bgColor or COLORS.BLACK)
        gpu.set(ax, ay, "┌")
        gpu.set(ax + self.width - 1, ay, "┐")
        gpu.set(ax, ay + self.height - 1, "└")
        gpu.set(ax + self.width - 1, ay + self.height - 1, "┘")
        for i = 1, self.height - 2 do
            gpu.set(ax, ay + i, "│")
            gpu.set(ax + self.width - 1, ay + i, "│")
        end
    end
end

function Component:drawBackground()
    if not self.visible then return end
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    if self.bgColor then
        gpu.setBackground(self.bgColor)
        for y = ay + 1, ay + self.height - 2 do
            gpu.set(ax + 1, y, string.rep(" ", self.width - 2))
        end
    end
end

function Component:handleEvent(eventType, ...)
    return false
end

function Component:setFocus(focused)
    self.focused = focused
    if focused and self.onFocus then
        self.onFocus(self)
    elseif not focused and self.onBlur then
        self.onBlur(self)
    end
    return self
end

-- ============================================
-- PART 3: WINDOW CLASS
-- ============================================

local Window = setmetatable({}, Component)
Window.__index = Window

function Window:new(params)
    params = params or {}
    params.bgColor = params.bgColor or COLORS.DARK_BLUE
    params.fgColor = params.fgColor or COLORS.WHITE
    params.borderColor = params.borderColor or COLORS.CYAN
    params.width = params.width or 40
    params.height = params.height or 15
    
    local obj = Component.new(self, params)
    obj.title = params.title or "Window"
    obj.draggable = params.draggable ~= false
    obj.closable = params.closable ~= false
    obj.modal = params.modal or false
    obj.zIndex = params.zIndex or 0
    obj.isDragging = false
    obj.dragOffsetX = 0
    obj.dragOffsetY = 0
    obj.closeCallback = params.onClose
    obj.minWidth = params.minWidth or 20
    obj.minHeight = params.minHeight or 10
    
    setmetatable(obj, Window)
    return obj
end

function Window:draw()
    if not self.visible then return end
    
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    -- Clear window area
    gpu.setBackground(self.bgColor or COLORS.DARK_BLUE)
    for y = ay, ay + self.height - 1 do
        gpu.set(ax, y, string.rep(" ", self.width))
    end
    
    -- Draw border
    gpu.setForeground(self.borderColor)
    gpu.set(ax, ay, "┌")
    gpu.set(ax + self.width - 1, ay, "┐")
    gpu.set(ax, ay + self.height - 1, "└")
    gpu.set(ax + self.width - 1, ay + self.height - 1, "┘")
    for i = 1, self.height - 2 do
        gpu.set(ax, ay + i, "│")
        gpu.set(ax + self.width - 1, ay + i, "│")
    end
    gpu.set(ax + 1, ay, string.rep("─", self.width - 2))
    gpu.set(ax + 1, ay + self.height - 1, string.rep("─", self.width - 2))
    
    -- Draw title
    if self.title then
        gpu.setBackground(self.bgColor)
        gpu.setForeground(self.fgColor)
        local titleStr = " " .. self.title .. " "
        local startX = ax + math.floor((self.width - #titleStr) / 2)
        startX = math.max(startX, ax + 1)
        startX = math.min(startX, ax + self.width - #titleStr - 1)
        if startX < ax + self.width - 1 then
            gpu.set(startX, ay, titleStr)
        end
        
        -- Close button
        if self.closable then
            gpu.setForeground(COLORS.RED)
            gpu.set(ax + self.width - 2, ay, "X")
            gpu.setForeground(self.fgColor)
        end
    end
    
    -- Draw children
    for _, child in ipairs(self.children) do
        if child.visible then
            child:draw()
        end
    end
end

function Window:handleEvent(eventType, ...)
    if not self.visible then return false end
    
    local args = {...}
    local x = args[1] or 0
    local y = args[2] or 0
    local button = args[3] or 0
    
    -- Handle window dragging
    if eventType == "touch" and self.draggable then
        if self:contains(x, y) then
            local ax = self:getAbsoluteX()
            local ay = self:getAbsoluteY()
            if y == ay and x >= ax and x < ax + self.width then
                if self.closable and x == ax + self.width - 2 then
                    if self.closeCallback then
                        self.closeCallback(self)
                    end
                    self.visible = false
                    return true
                end
                self.isDragging = true
                self.dragOffsetX = x - ax
                self.dragOffsetY = y - ay
                return true
            end
        end
    elseif eventType == "touch_move" and self.isDragging then
        self.x = x - self.dragOffsetX
        self.y = y - self.dragOffsetY
        return true
    elseif eventType == "touch_up" and self.isDragging then
        self.isDragging = false
        return true
    end
    
    -- Pass event to children
    for i = #self.children, 1, -1 do
        local child = self.children[i]
        if child.visible and child:handleEvent(eventType, ...) then
            return true
        end
    end
    
    return false
end

-- ============================================
-- PART 4: BUTTON CLASS
-- ============================================

local Button = setmetatable({}, Component)
Button.__index = Button

function Button:new(params)
    params = params or {}
    params.width = params.width or 12
    params.height = params.height or 3
    params.bgColor = params.bgColor or COLORS.DARK_GRAY
    params.fgColor = params.fgColor or COLORS.WHITE
    params.borderColor = params.borderColor or COLORS.LIGHT_GRAY
    
    local obj = Component.new(self, params)
    obj.text = params.text or "Button"
    obj.hoverBgColor = params.hoverBgColor or COLORS.GRAY
    obj.pressedBgColor = params.pressedBgColor or COLORS.DARK_RED
    obj.isPressed = false
    obj.shortcut = params.shortcut
    
    setmetatable(obj, Button)
    return obj
end

function Button:draw()
    if not self.visible then return end
    
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    local bgColor = self.bgColor
    if self.isPressed then
        bgColor = self.pressedBgColor
    elseif self.hover then
        bgColor = self.hoverBgColor
    end
    
    gpu.setBackground(bgColor)
    gpu.setForeground(self.fgColor)
    
    -- Draw background
    for y = ay, ay + self.height - 1 do
        gpu.set(ax, y, string.rep(" ", self.width))
    end
    
    -- Draw border
    gpu.setForeground(self.borderColor)
    gpu.set(ax, ay, "┌")
    gpu.set(ax + self.width - 1, ay, "┐")
    gpu.set(ax, ay + self.height - 1, "└")
    gpu.set(ax + self.width - 1, ay + self.height - 1, "┘")
    for i = 1, self.height - 2 do
        gpu.set(ax, ay + i, "│")
        gpu.set(ax + self.width - 1, ay + i, "│")
    end
    gpu.set(ax + 1, ay, string.rep("─", self.width - 2))
    gpu.set(ax + 1, ay + self.height - 1, string.rep("─", self.width - 2))
    
    -- Draw text
    local textX = ax + math.floor((self.width - #self.text) / 2)
    local textY = ay + math.floor(self.height / 2)
    gpu.setForeground(self.fgColor)
    gpu.set(textX, textY, self.text)
end

function Button:handleEvent(eventType, ...)
    if not self.visible or not self.enabled then return false end
    
    local args = {...}
    local x = args[1] or 0
    local y = args[2] or 0
    local button = args[3] or 0
    local char = args[4] or ""
    local key = args[5] or 0
    
    if eventType == "key_down" and self.shortcut then
        local keyChar = string.char(char)
        if keyChar:upper() == self.shortcut:upper() then
            self:click()
            return true
        end
    end
    
    if eventType == "touch" then
        if self:contains(x, y) then
            self.isPressed = true
            return true
        end
    elseif eventType == "touch_up" then
        if self.isPressed and self:contains(x, y) then
            self:click()
        end
        self.isPressed = false
        return true
    elseif eventType == "touch_move" then
        self.hover = self:contains(x, y)
        if not self.hover then
            self.isPressed = false
        end
        return true
    end
    
    return false
end

function Button:click()
    if self.onClick then
        self.onClick(self)
    end
end

-- ============================================
-- PART 5: TEXT FIELD CLASS
-- ============================================

local TextField = setmetatable({}, Component)
TextField.__index = TextField

function TextField:new(params)
    params = params or {}
    params.width = params.width or 20
    params.height = params.height or 3
    params.bgColor = params.bgColor or COLORS.BLACK
    params.fgColor = params.fgColor or COLORS.GREEN
    
    local obj = Component.new(self, params)
    obj.text = params.text or ""
    obj.placeholder = params.placeholder or ""
    obj.maxLength = params.maxLength or 64
    obj.cursorPos = #obj.text + 1
    obj.scrollOffset = 0
    obj.password = params.password or false
    obj.focusBorderColor = params.focusBorderColor or COLORS.GREEN
    obj.onChange = params.onChange
    obj.onEnter = params.onEnter
    obj.cursorBlink = 0
    obj.showCursor = true
    
    setmetatable(obj, TextField)
    return obj
end

function TextField:draw()
    if not self.visible then return end
    
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    gpu.setBackground(self.bgColor)
    gpu.setForeground(self.fgColor)
    
    -- Draw background
    for y = ay, ay + self.height - 1 do
        gpu.set(ax, y, string.rep(" ", self.width))
    end
    
    -- Draw border
    local borderColor = self.focused and self.focusBorderColor or self.borderColor
    gpu.setForeground(borderColor)
    gpu.set(ax, ay, "┌")
    gpu.set(ax + self.width - 1, ay, "┐")
    gpu.set(ax, ay + self.height - 1, "└")
    gpu.set(ax + self.width - 1, ay + self.height - 1, "┘")
    for i = 1, self.height - 2 do
        gpu.set(ax, ay + i, "│")
        gpu.set(ax + self.width - 1, ay + i, "│")
    end
    gpu.set(ax + 1, ay, string.rep("─", self.width - 2))
    gpu.set(ax + 1, ay + self.height - 1, string.rep("─", self.width - 2))
    
    -- Draw text
    local displayText = self.text
    if self.password and #displayText > 0 then
        displayText = string.rep("*", #displayText)
    end
    
    local textY = ay + 1
    local maxDisplay = self.width - 2
    
    if #displayText > 0 then
        if #displayText > maxDisplay then
            local startPos = self.scrollOffset + 1
            displayText = displayText:sub(startPos, startPos + maxDisplay - 1)
        end
        
        gpu.setForeground(self.fgColor)
        gpu.set(ax + 1, textY, displayText)
        
        -- Draw cursor
        if self.focused then
            local cursorX = ax + 1 + (self.cursorPos - self.scrollOffset - 1)
            if cursorX >= ax + 1 and cursorX <= ax + self.width - 2 then
                local oldBg = gpu.getBackground()
                gpu.setBackground(self.fgColor)
                gpu.setForeground(self.bgColor)
                local char = displayText:sub(self.cursorPos - self.scrollOffset, 
                                             self.cursorPos - self.scrollOffset)
                if char == "" then char = " " end
                gpu.set(cursorX, textY, char)
                gpu.setBackground(oldBg)
                gpu.setForeground(self.fgColor)
            end
        end
    elseif self.placeholder and not self.focused then
        gpu.setForeground(COLORS.GRAY)
        gpu.set(ax + 1, ay + 1, self.placeholder:sub(1, self.width - 2))
    end
end

function TextField:handleEvent(eventType, ...)
    if not self.visible or not self.enabled then return false end
    
    local args = {...}
    local x = args[1] or 0
    local y = args[2] or 0
    local button = args[3] or 0
    local char = args[4] or ""
    local key = args[5] or 0
    
    if eventType == "touch" then
        if self:contains(x, y) then
            self:setFocus(true)
            return true
        end
    end
    
    if self.focused and eventType == "key_down" then
        if key == 28 then -- Enter
            if self.onEnter then
                self.onEnter(self)
            end
            return true
        elseif key == 14 then -- Backspace
            if #self.text > 0 and self.cursorPos > 1 then
                self.text = self.text:sub(1, self.cursorPos - 2) .. 
                           self.text:sub(self.cursorPos)
                self.cursorPos = self.cursorPos - 1
                self:updateScroll()
                if self.onChange then
                    self.onChange(self)
                end
            end
            return true
        elseif key == 199 then -- Home
            self.cursorPos = 1
            self.scrollOffset = 0
            return true
        elseif key == 207 then -- End
            self.cursorPos = #self.text + 1
            self:updateScroll()
            return true
        elseif key == 200 then -- Left
            if self.cursorPos > 1 then
                self.cursorPos = self.cursorPos - 1
                self:updateScroll()
            end
            return true
        elseif key == 205 then -- Right
            if self.cursorPos <= #self.text then
                self.cursorPos = self.cursorPos + 1
                self:updateScroll()
            end
            return true
        elseif key == 211 then -- Delete
            if self.cursorPos <= #self.text then
                self.text = self.text:sub(1, self.cursorPos - 1) .. 
                           self.text:sub(self.cursorPos + 1)
                self:updateScroll()
                if self.onChange then
                    self.onChange(self)
                end
            end
            return true
        elseif char >= 32 and char <= 126 then
            if #self.text < self.maxLength then
                self.text = self.text:sub(1, self.cursorPos - 1) .. 
                           string.char(char) .. 
                           self.text:sub(self.cursorPos)
                self.cursorPos = self.cursorPos + 1
                self:updateScroll()
                if self.onChange then
                    self.onChange(self)
                end
            end
            return true
        end
    end
    
    return false
end

function TextField:updateScroll()
    local maxDisplay = self.width - 2
    if self.cursorPos > self.scrollOffset + maxDisplay then
        self.scrollOffset = self.cursorPos - maxDisplay
    elseif self.cursorPos <= self.scrollOffset then
        self.scrollOffset = self.cursorPos - 1
    end
    if self.scrollOffset < 0 then
        self.scrollOffset = 0
    end
end

function TextField:setText(text)
    self.text = text or ""
    self.cursorPos = #self.text + 1
    self.scrollOffset = 0
    self:updateScroll()
    if self.onChange then
        self.onChange(self)
    end
end

function TextField:getText()
    return self.text
end

-- ============================================
-- PART 6: PROGRESS BAR CLASS
-- ============================================

local ProgressBar = setmetatable({}, Component)
ProgressBar.__index = ProgressBar

function ProgressBar:new(params)
    params = params or {}
    params.width = params.width or 20
    params.height = params.height or 1
    params.bgColor = params.bgColor or COLORS.DARK_GRAY
    
    local obj = Component.new(self, params)
    obj.value = params.value or 0
    obj.max = params.max or 100
    obj.fillColor = params.fillColor or COLORS.GREEN
    obj.showPercent = params.showPercent ~= false
    obj.label = params.label or ""
    obj.showLabel = params.showLabel ~= false
    
    setmetatable(obj, ProgressBar)
    return obj
end

function ProgressBar:draw()
    if not self.visible then return end
    
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    local percent = math.min(1, self.value / self.max)
    local filled = math.floor(percent * self.width)
    
    gpu.setBackground(self.bgColor)
    gpu.setForeground(self.fgColor)
    
    -- Draw background
    gpu.set(ax, ay, string.rep(" ", self.width))
    
    -- Draw filled part
    if filled > 0 then
        gpu.setBackground(self.fillColor)
        gpu.set(ax, ay, string.rep(" ", filled))
    end
    
    -- Draw percentage
    if self.showPercent then
        local pctStr = string.format("%3d%%", math.floor(percent * 100))
        local pctX = ax + math.floor((self.width - 4) / 2)
        gpu.setForeground(COLORS.WHITE)
        gpu.setBackground(COLORS.TRANSPARENT)
        gpu.set(pctX, ay, pctStr)
    end
    
    -- Draw label
    if self.showLabel and self.label and #self.label > 0 then
        gpu.setForeground(COLORS.GRAY)
        gpu.set(ax - #self.label - 1, ay, self.label .. ":")
    end
end

function ProgressBar:setValue(value)
    self.value = math.max(0, math.min(value, self.max))
end

-- ============================================
-- PART 7: CHECKBOX CLASS
-- ============================================

local Checkbox = setmetatable({}, Component)
Checkbox.__index = Checkbox

function Checkbox:new(params)
    params = params or {}
    params.width = params.width or 3
    params.height = params.height or 1
    params.bgColor = params.bgColor or COLORS.BLACK
    
    local obj = Component.new(self, params)
    obj.label = params.label or "Checkbox"
    obj.checked = params.checked or false
    obj.onChange = params.onChange
    obj.labelColor = params.labelColor or COLORS.WHITE
    
    setmetatable(obj, Checkbox)
    return obj
end

function Checkbox:draw()
    if not self.visible then return end
    
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    gpu.setBackground(self.bgColor)
    gpu.setForeground(self.fgColor)
    
    gpu.set(ax, ay, "[")
    if self.checked then
        gpu.setForeground(COLORS.GREEN)
        gpu.set(ax + 1, ay, "X")
        gpu.setForeground(self.fgColor)
    else
        gpu.set(ax + 1, ay, " ")
    end
    gpu.set(ax + 2, ay, "]")
    
    if self.label then
        gpu.setForeground(self.labelColor)
        gpu.set(ax + 4, ay, self.label)
    end
end

function Checkbox:handleEvent(eventType, ...)
    if not self.visible or not self.enabled then return false end
    
    if eventType == "touch" then
        local args = {...}
        local x = args[1] or 0
        local y = args[2] or 0
        
        if self:contains(x, y) then
            self.checked = not self.checked
            if self.onChange then
                self.onChange(self)
            end
            return true
        end
    end
    
    return false
end

function Checkbox:isChecked()
    return self.checked
end

-- ============================================
-- PART 8: LIST BOX CLASS
-- ============================================

local ListBox = setmetatable({}, Component)
ListBox.__index = ListBox

function ListBox:new(params)
    params = params or {}
    params.width = params.width or 30
    params.height = params.height or 10
    params.bgColor = params.bgColor or COLORS.BLACK
    params.fgColor = params.fgColor or COLORS.WHITE
    
    local obj = Component.new(self, params)
    obj.items = params.items or {}
    obj.selectedIndex = params.selectedIndex or 1
    obj.scrollOffset = 0
    obj.onSelect = params.onSelect
    obj.highlightColor = params.highlightColor or COLORS.DARK_BLUE
    obj.selectedColor = params.selectedColor or COLORS.GREEN
    
    setmetatable(obj, ListBox)
    return obj
end

function ListBox:draw()
    if not self.visible then return end
    
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    gpu.setBackground(self.bgColor)
    gpu.setForeground(self.fgColor)
    
    -- Draw border
    gpu.setForeground(self.borderColor)
    gpu.set(ax, ay, "┌")
    gpu.set(ax + self.width - 1, ay, "┐")
    gpu.set(ax, ay + self.height - 1, "└")
    gpu.set(ax + self.width - 1, ay + self.height - 1, "┘")
    for i = 1, self.height - 2 do
        gpu.set(ax, ay + i, "│")
        gpu.set(ax + self.width - 1, ay + i, "│")
    end
    gpu.set(ax + 1, ay, string.rep("─", self.width - 2))
    gpu.set(ax + 1, ay + self.height - 1, string.rep("─", self.width - 2))
    
    -- Draw items
    local displayHeight = self.height - 2
    local maxDisplay = self.width - 2
    
    for i = 1, displayHeight do
        local itemIndex = self.scrollOffset + i
        if itemIndex <= #self.items then
            local item = self.items[itemIndex]
            local displayText = item:sub(1, maxDisplay)
            
            local yPos = ay + i
            local xPos = ax + 1
            
            if itemIndex == self.selectedIndex then
                gpu.setBackground(self.selectedColor)
                gpu.setForeground(COLORS.WHITE)
            elseif itemIndex % 2 == 0 then
                gpu.setBackground(COLORS.DARK_GRAY)
                gpu.setForeground(self.fgColor)
            else
                gpu.setBackground(self.bgColor)
                gpu.setForeground(self.fgColor)
            end
            
            gpu.set(xPos, yPos, string.rep(" ", maxDisplay))
            gpu.set(xPos, yPos, displayText)
        end
    end
    
    gpu.setBackground(COLORS.BLACK)
    gpu.setForeground(COLORS.WHITE)
end

function ListBox:handleEvent(eventType, ...)
    if not self.visible or not self.enabled then return false end
    
    local args = {...}
    local x = args[1] or 0
    local y = args[2] or 0
    local key = args[5] or 0
    
    if eventType == "touch" then
        if self:contains(x, y) then
            local ax = self:getAbsoluteX()
            local ay = self:getAbsoluteY()
            local relativeY = y - ay - 1
            local itemIndex = self.scrollOffset + relativeY
            
            if itemIndex >= 1 and itemIndex <= #self.items then
                self.selectedIndex = itemIndex
                if self.onSelect then
                    self.onSelect(self)
                end
            end
            return true
        end
    elseif eventType == "key_down" then
        if key == 200 then -- Up
            if self.selectedIndex > 1 then
                self.selectedIndex = self.selectedIndex - 1
                if self.selectedIndex <= self.scrollOffset then
                    self.scrollOffset = self.selectedIndex - 1
                end
                if self.onSelect then
                    self.onSelect(self)
                end
            end
            return true
        elseif key == 208 then -- Down
            if self.selectedIndex < #self.items then
                self.selectedIndex = self.selectedIndex + 1
                local maxDisplay = self.height - 2
                if self.selectedIndex >= self.scrollOffset + maxDisplay then
                    self.scrollOffset = self.selectedIndex - maxDisplay + 1
                end
                if self.onSelect then
                    self.onSelect(self)
                end
            end
            return true
        end
    end
    
    return false
end

function ListBox:addItem(item)
    table.insert(self.items, item)
end

function ListBox:getSelectedItem()
    if self.selectedIndex >= 1 and self.selectedIndex <= #self.items then
        return self.items[self.selectedIndex]
    end
    return nil
end

-- ============================================
-- PART 9: TAB VIEW CLASS
-- ============================================

local TabView = setmetatable({}, Component)
TabView.__index = TabView

function TabView:new(params)
    params = params or {}
    params.width = params.width or 40
    params.height = params.height or 15
    params.bgColor = params.bgColor or COLORS.BLACK
    
    local obj = Component.new(self, params)
    obj.tabs = {}
    obj.activeTab = 1
    
    setmetatable(obj, TabView)
    return obj
end

function TabView:addTab(title, content)
    table.insert(self.tabs, {
        title = title,
        content = content,
        visible = true
    })
    if #self.tabs == 1 then
        self.activeTab = 1
    end
end

function TabView:draw()
    if not self.visible then return end
    
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    
    gpu.setBackground(self.bgColor)
    gpu.setForeground(self.fgColor)
    
    -- Draw border
    gpu.setForeground(self.borderColor)
    gpu.set(ax, ay, "┌")
    gpu.set(ax + self.width - 1, ay, "┐")
    gpu.set(ax, ay + self.height - 1, "└")
    gpu.set(ax + self.width - 1, ay + self.height - 1, "┘")
    for i = 1, self.height - 2 do
        gpu.set(ax, ay + i, "│")
        gpu.set(ax + self.width - 1, ay + i, "│")
    end
    
    -- Draw tabs
    local tabX = ax + 1
    for i, tab in ipairs(self.tabs) do
        if i == self.activeTab then
            gpu.setBackground(COLORS.DARK_BLUE)
            gpu.setForeground(COLORS.WHITE)
        else
            gpu.setBackground(COLORS.DARK_GRAY)
            gpu.setForeground(COLORS.LIGHT_GRAY)
        end
        
        local tabStr = " " .. tab.title .. " "
        gpu.set(tabX, ay, tabStr)
        tabX = tabX + #tabStr + 1
    end
end

function TabView:handleEvent(eventType, ...)
    if not self.visible then return false end
    
    if eventType == "touch" then
        local args = {...}
        local x = args[1] or 0
        local y = args[2] or 0
        
        local ax = self:getAbsoluteX()
        local ay = self:getAbsoluteY()
        
        if y == ay and x >= ax and x < ax + self.width then
            local tabX = ax + 1
            for i, tab in ipairs(self.tabs) do
                local tabStr = " " .. tab.title .. " "
                if x >= tabX and x < tabX + #tabStr then
                    self.activeTab = i
                    return true
                end
                tabX = tabX + #tabStr + 1
            end
        end
    end
    
    return false
end

-- ============================================
-- PART 10: GUI MANAGER
-- ============================================

local GUIManager = {}
GUIManager.__index = GUIManager

function GUIManager:new()
    local obj = {
        windows = {},
        focusedWindow = nil,
        running = false,
        lastDraw = 0,
        drawInterval = 0.05
    }
    setmetatable(obj, GUIManager)
    return obj
end

function GUIManager:addWindow(window)
    table.insert(self.windows, window)
    if not self.focusedWindow then
        self.focusedWindow = window
    end
    return window
end

function GUIManager:removeWindow(window)
    for i, w in ipairs(self.windows) do
        if w == window then
            table.remove(self.windows, i)
            if self.focusedWindow == window then
                self.focusedWindow = self.windows[#self.windows]
            end
            return true
        end
    end
    return false
end

function GUIManager:draw()
    term.clear()
    
    table.sort(self.windows, function(a, b)
        return (a.zIndex or 0) < (b.zIndex or 0)
    end)
    
    for _, window in ipairs(self.windows) do
        if window.visible then
            window:draw()
        end
    end
end

function GUIManager:run()
    self.running = true
    self:draw()
    
    while self.running do
        local eventData = event.pull(0.1)
        if eventData then
            local eventType = eventData[1]
            
            if eventType == "key_down" then
                local char = eventData[2] or 0
                local key = eventData[3] or 0
                
                if key == 1 then -- ESC
                    self.running = false
                    break
                end
                
                if self.focusedWindow then
                    self.focusedWindow:handleEvent(eventType, char, key)
                end
                
            elseif eventType == "touch" or eventType == "touch_move" or eventType == "touch_up" then
                local x = eventData[2] or 0
                local y = eventData[3] or 0
                local button = eventData[4] or 0
                
                local foundWindow = nil
                for i = #self.windows, 1, -1 do
                    if self.windows[i].visible and self.windows[i]:contains(x, y) then
                        foundWindow = self.windows[i]
                        break
                    end
                end
                
                if foundWindow then
                    if eventType == "touch" then
                        self.focusedWindow = foundWindow
                    end
                    foundWindow:handleEvent(eventType, x, y, button)
                end
                
                self:draw()
                
            elseif eventType == "interrupted" then
                self.running = false
                break
            end
        end
        
        if computer.uptime() - self.lastDraw > self.drawInterval then
            self:draw()
            self.lastDraw = computer.uptime()
        end
    end
    
    term.clear()
    gpu.setBackground(COLORS.BLACK)
    gpu.setForeground(COLORS.WHITE)
    term.setCursor(1, 1)
    print("GUI closed. Press any key to continue...")
    event.pull("key")
end

-- ============================================
-- PART 11: EXAMPLE 1 - SYSTEM MONITOR
-- ============================================

local function createSystemMonitor()
    local manager = GUIManager:new()
    
    local window = Window:new({
        title = "📊 SYSTEM MONITOR",
        x = 5, y = 2,
        width = 50, height = 20,
        bgColor = 0x1a1a2e,
        borderColor = 0x00ff88,
        closable = true
    })
    
    local cpuBar = ProgressBar:new({
        x = 3, y = 3, width = 40,
        label = "CPU", fillColor = 0x00ff88, value = 0
    })
    window:addChild(cpuBar)
    
    local memBar = ProgressBar:new({
        x = 3, y = 5, width = 40,
        label = "MEM", fillColor = 0x00aaff, value = 0
    })
    window:addChild(memBar)
    
    local diskBar = ProgressBar:new({
        x = 3, y = 7, width = 40,
        label = "DISK", fillColor = 0xffaa00, value = 0
    })
    window:addChild(diskBar)
    
    local uptimeLabel = Component:new({
        x = 3, y = 10, width = 44, height = 1, fgColor = 0x88ccff
    })
    uptimeLabel.draw = function(self)
        local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
        local u = computer.uptime()
        local h, m, s = math.floor(u/3600), math.floor((u%3600)/60), math.floor(u%60)
        gpu.setForeground(self.fgColor)
        gpu.set(ax, ay, string.format("Uptime: %02dh %02dm %02ds", h, m, s))
    end
    window:addChild(uptimeLabel)
    
    local refreshBtn = Button:new({
        x = 3, y = 15, width = 10, height = 3,
        text = "⟳ REFRESH", fgColor = 0xffffff,
        bgColor = 0x00aa55, hoverBgColor = 0x00cc66
    })
    refreshBtn.onClick = function() window:draw() end
    window:addChild(refreshBtn)
    
    manager:addWindow(window)
    
    manager.draw = function(self)
        cpuBar:setValue(math.random(10, 95))
        memBar:setValue(45 + math.random(0, 40))
        diskBar:setValue(30 + math.random(0, 50))
        GUIManager.draw(self)
    end
    
    return manager
end

-- ============================================
-- PART 12: EXAMPLE 2 - FILE MANAGER
-- ============================================

local function createFileManager()
    local manager = GUIManager:new()
    
    local window = Window:new({
        title = "📁 FILE MANAGER",
        x = 3, y = 1,
        width = 55, height = 22,
        bgColor = 0x1a1a2e, borderColor = 0x00aaff
    })
    
    local pathDisplay = TextField:new({
        x = 3, y = 2, width = 47,
        text = "/home", fgColor = 0x88ccff,
        bgColor = 0x0a0a1e, borderColor = 0x00aaff
    })
    window:addChild(pathDisplay)
    
    local function getFileList(path)
        local items = {}
        if not fs.exists(path) then return items end
        for _, file in ipairs(fs.list(path)) do
            local fullPath = path .. "/" .. file
            local isDir = fs.isDirectory(fullPath)
            local icon = isDir and "📁 " or "📄 "
            table.insert(items, icon .. file)
        end
        table.sort(items)
        return items
    end
    
    local fileList = ListBox:new({
        x = 3, y = 8, width = 49, height = 10,
        bgColor = 0x0a0a1e, selectedColor = 0x004466
    })
    fileList.items = getFileList("/home")
    fileList.onSelect = function(self)
        local selected = self:getSelectedItem()
        if selected then
            local name = selected:match("^. (.+)")
            if name then
                local currentPath = pathDisplay:getText()
                local fullPath = currentPath .. "/" .. name
                if fs.isDirectory(fullPath) then
                    pathDisplay:setText(fullPath)
                    fileList.items = getFileList(fullPath)
                end
            end
        end
    end
    window:addChild(fileList)
    
    manager:addWindow(window)
    return manager
end

-- ============================================
-- PART 13: EXAMPLE 3 - TERMINAL
-- ============================================

local function createTerminal()
    local manager = GUIManager:new()
    
    local window = Window:new({
        title = "💻 TERMINAL",
        x = 5, y = 2, width = 50, height = 20,
        bgColor = 0x000000, borderColor = 0x00ff00, fgColor = 0x00ff00
    })
    
    local lines = {"Welcome to OpenComputers Terminal!", "Type 'help' for commands."}
    
    local terminalDisplay = Component:new({
        x = 2, y = 2, width = 46, height = 13, fgColor = 0x00ff00
    })
    terminalDisplay.draw = function(self)
        local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
        gpu.setBackground(0x000000)
        gpu.setForeground(0x00ff00)
        for i = 1, self.height do
            gpu.set(ax, ay + i - 1, string.rep(" ", self.width))
        end
        local startLine = math.max(1, #lines - self.height + 1)
        for i = startLine, #lines do
            gpu.set(ax, ay + (i - startLine), lines[i]:sub(1, self.width))
        end
    end
    window:addChild(terminalDisplay)
    
    local inputField = TextField:new({
        x = 2, y = 16, width = 44, height = 2,
        bgColor = 0x001100, fgColor = 0x00ff00,
        borderColor = 0x00ff00, placeholder = "> "
    })
    inputField.onEnter = function(self)
        local command = self:getText()
        if command == "" then return end
        
        table.insert(lines, "> " .. command)
        
        if command == "help" then
            table.insert(lines, "Commands: help, clear, echo, time, list, info, exit")
        elseif command == "clear" then
            lines = {}
        elseif command:match("^echo ") then
            table.insert(lines, command:sub(6))
        elseif command == "time" then
            table.insert(lines, os.date("%Y-%m-%d %H:%M:%S"))
        elseif command == "list" then
            for addr, name in component.list() do
                table.insert(lines, string.format("  %s: %s", name, addr:sub(1, 8)))
            end
        elseif command == "info" then
            table.insert(lines, string.format("Lua: %s", _VERSION))
            table.insert(lines, string.format("Uptime: %.0fs", computer.uptime()))
        elseif command == "exit" then
            manager.running = false
        else
            table.insert(lines, "Unknown command. Type 'help'")
        end
        
        self:setText("")
    end
    window:addChild(inputField)
    
    manager:addWindow(window)
    return manager
end

-- ============================================
-- PART 14: EXAMPLE 4 - CONFIGURATOR
-- ============================================

local function createConfigurator()
    local manager = GUIManager:new()
    
    local window = Window:new({
        title = "⚙️ CONFIGURATOR",
        x = 8, y = 3, width = 45, height = 18,
        bgColor = 0x1a1a2e, borderColor = 0xff8800
    })
    
    local tabView = TabView:new({
        x = 2, y = 2, width = 41, height = 12,
        bgColor = 0x0a0a1e, borderColor = 0xff8800
    })
    
    -- General tab content
    local generalContent = Component:new({
        x = 4, y = 5, width = 37, height = 8
    })
    generalContent.draw = function(self)
        local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
        gpu.setForeground(0x88ccff)
        gpu.set(ax, ay, "Auto-Start: [X]")
        gpu.set(ax, ay + 1, "Debug Mode: [ ]")
        gpu.set(ax, ay + 2, "Silent Mode: [X]")
        gpu.set(ax, ay + 4, "Language: English")
        gpu.set(ax, ay + 5, "Theme: Dark")
    end
    
    -- Network tab content
    local networkContent = Component:new({
        x = 4, y = 5, width = 37, height = 8
    })
    networkContent.draw = function(self)
        local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
        gpu.setForeground(0x88ccff)
        gpu.set(ax, ay, "Server IP: 192.168.1.100")
        gpu.set(ax, ay + 1, "Port: 8080")
        gpu.set(ax, ay + 2, "Username: admin")
        gpu.set(ax, ay + 4, "Connection: Online")
    end
    
    tabView:addTab("General", generalContent)
    tabView:addTab("Network", networkContent)
    tabView:addTab("Display", generalContent)
    tabView:addTab("Advanced", generalContent)
    
    window:addChild(tabView)
    
    local saveBtn = Button:new({
        x = 4, y = 15, width = 8, height = 2,
        text = "SAVE", bgColor = 0x00aa55, hoverBgColor = 0x00cc66
    })
    window:addChild(saveBtn)
    
    local resetBtn = Button:new({
        x = 16, y = 15, width = 8, height = 2,
        text = "RESET", bgColor = 0xff8800, hoverBgColor = 0xffaa44
    })
    window:addChild(resetBtn)
    
    manager:addWindow(window)
    return manager
end

-- ============================================
-- PART 15: EXAMPLE 5 - AUTOMATION PANEL
-- ============================================

local function createAutomation()
    local manager = GUIManager:new()
    
    local window = Window:new({
        title = "🤖 AUTOMATION PANEL",
        x = 4, y = 2, width = 52, height = 20,
        bgColor = 0x1a1a2e, borderColor = 0x00ff88
    })
    
    -- Task list
    local tasks = {
        "Task 1: Mining [████████░░] 80%",
        "Task 2: Crafting [██████░░░░] 60%",
        "Task 3: Farming [██████████] 100%",
        "Task 4: Building [███░░░░░░░] 30%"
    }
    
    local taskList = ListBox:new({
        x = 3, y = 3, width = 46, height = 8,
        bgColor = 0x0a0a1e, selectedColor = 0x004466
    })
    taskList.items = tasks
    window:addChild(taskList)
    
    -- Control buttons
    local startBtn = Button:new({
        x = 3, y = 13, width = 8, height = 2,
        text = "▶ START", bgColor = 0x00aa55, hoverBgColor = 0x00cc66
    })
    window:addChild(startBtn)
    
    local pauseBtn = Button:new({
        x = 13, y = 13, width = 8, height = 2,
        text = "⏸ PAUSE", bgColor = 0xff8800, hoverBgColor = 0xffaa44
    })
    window:addChild(pauseBtn)
    
    local stopBtn = Button:new({
        x = 23, y = 13, width = 8, height = 2,
        text = "⏹ STOP", bgColor = 0xcc3333, hoverBgColor = 0xff4444
    })
    window:addChild(stopBtn)
    
    -- Status
    local statusLabel = Component:new({
        x = 3, y = 16, width = 46, height = 1, fgColor = 0x88ccff
    })
    statusLabel.draw = function(self)
        local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
        gpu.setForeground(self.fgColor)
        gpu.set(ax, ay, string.format("Total: %d | Running: 2 | Completed: 1 | Failed: 1", #tasks))
    end
    window:addChild(statusLabel)
    
    manager:addWindow(window)
    return manager
end

-- ============================================
-- PART 16: LAUNCHER
-- ============================================

local function showLauncher()
    local manager = GUIManager:new()
    
    local window = Window:new({
        title = "🚀 GUI EXAMPLES",
        x = 10, y = 4, width = 40, height = 15,
        bgColor = 0x1a1a2e, borderColor = 0xff8800
    })
    
    local titleLabel = Component:new({
        x = 2, y = 2, width = 36, height = 1, fgColor = 0xff8800
    })
    titleLabel.draw = function(self)
        local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
        gpu.setForeground(0xff8800)
        gpu.set(ax, ay, "Select an example to run:")
    end
    window:addChild(titleLabel)
    
    local examples = {
        {"📊 System Monitor", createSystemMonitor},
        {"📁 File Manager", createFileManager},
        {"💻 Terminal", createTerminal},
        {"⚙️ Configurator", createConfigurator},
        {"🤖 Automation", createAutomation}
    }
    
    local yPos = 4
    for _, example in ipairs(examples) do
        local btn = Button:new({
            x = 5, y = yPos, width = 30, height = 2,
            text = example[1], bgColor = 0x334466, hoverBgColor = 0x446688
        })
        btn.onClick = function()
            local instance = example[2]()
            instance:run()
        end
        window:addChild(btn)
        yPos = yPos + 3
    end
    
    manager:addWindow(window)
    manager:run()
end

-- ============================================
-- PART 17: MAIN ENTRY POINT
-- ============================================

local function main()
    term.clear()
    gpu.setBackground(COLORS.BLACK)
    gpu.setForeground(COLORS.WHITE)
    
    print("=" .. string.rep("=", 50))
    print("  GUI FRAMEWORK FOR OPENCOMPUTERS")
    print("  Contains: Core GUI + 5 Examples")
    print("=" .. string.rep("=", 50))
    print("")
    print("Press any key to launch GUI...")
    event.pull("key")
    
    showLauncher()
    
    print("Thank you for using GUI Framework!")
    print("Press any key to exit...")
    event.pull("key")
end

-- Run the program
local ok, err = pcall(main)
if not ok then
    print("Error: " .. tostring(err))
    print("Press any key to exit...")
    event.pull("key")
end
