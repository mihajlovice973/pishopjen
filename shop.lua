-- shop.lua
-- Full shop system for OpenComputers
-- Works with chests, ME system, or any inventory component

local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local event = require("event")
local term = require("term")
local sides = require("sides") -- For inventory directions

-- ============================================
-- CONFIGURATION
-- ============================================

local SHOP_CONFIG = {
    -- Currency settings
    currency_name = "Coins",
    currency_symbol = "⛃",
    
    -- File paths
    data_file = "/home/shop_data.lua",
    log_file = "/home/shop_log.txt",
    
    -- UI settings
    items_per_page = 10,
    
    -- Eco system (prevent inflation)
    price_multiplier = 1.0,
    buyback_percentage = 0.7, -- 70% of sell price when buying back
    
    -- Default player starting balance
    starting_balance = 100,
}

-- ============================================
-- DATABASE MANAGEMENT
-- ============================================

local ShopDB = {}
local PlayerDB = {}
local InventoryDB = {}

-- Load saved data
local function loadData()
    if fs.exists(SHOP_CONFIG.data_file) then
        local ok, data = pcall(function()
            return dofile(SHOP_CONFIG.data_file)
        end)
        if ok and data then
            ShopDB = data.shop or {}
            PlayerDB = data.players or {}
            InventoryDB = data.inventory or {}
            return true
        end
    end
    return false
end

-- Save data
local function saveData()
    local data = {
        shop = ShopDB,
        players = PlayerDB,
        inventory = InventoryDB,
        saved_at = os.date("%Y-%m-%d %H:%M:%S")
    }
    
    local file, err = io.open(SHOP_CONFIG.data_file, "w")
    if not file then
        print("Error saving data: " .. tostring(err))
        return false
    end
    
    local str = "return " .. require("serialization").serialize(data) or data
    file:write(str)
    file:close()
    return true
end

-- Log transactions
local function logTransaction(player, action, item, amount, price)
    local file, err = io.open(SHOP_CONFIG.log_file, "a")
    if file then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local line = string.format("[%s] %s: %s - %s x%d - %s %s\n",
            timestamp, player, action, item, amount, price, SHOP_CONFIG.currency_symbol)
        file:write(line)
        file:close()
    end
end

-- ============================================
-- PLAYER MANAGEMENT
-- ============================================

local function getPlayerBalance(player)
    if not PlayerDB[player] then
        PlayerDB[player] = {
            balance = SHOP_CONFIG.starting_balance,
            total_spent = 0,
            total_earned = 0,
            joined = os.date("%Y-%m-%d %H:%M:%S")
        }
    end
    return PlayerDB[player].balance
end

local function addBalance(player, amount)
    if not PlayerDB[player] then
        getPlayerBalance(player)
    end
    PlayerDB[player].balance = PlayerDB[player].balance + amount
    if amount > 0 then
        PlayerDB[player].total_earned = PlayerDB[player].total_earned + amount
    else
        PlayerDB[player].total_spent = PlayerDB[player].total_spent + math.abs(amount)
    end
    saveData()
    return PlayerDB[player].balance
end

local function canAfford(player, amount)
    return getPlayerBalance(player) >= amount
end

-- ============================================
-- INVENTORY MANAGEMENT
-- ============================================

-- Find inventory components (chests, ME interfaces, etc.)
local function findInventoryComponents()
    local inventories = {}
    
    for addr, name in component.list() do
        -- Check for known inventory types
        if name:find("chest") or 
           name:find("inventory") or
           name:find("me_interface") or
           name:find("me_bridge") or
           name:find("me_controller") or
           name:find("openperipheral_selector") or
           name:find("item_selector") or
           name:find("pim") or
           name:find("buffer") or
           name:find("crate") or
           name:find("barrel") or
           name:find("drawer") then
            
            local proxy = component.proxy(addr)
            if proxy and proxy.getInventorySize then
                table.insert(inventories, {
                    address = addr,
                    name = name,
                    proxy = proxy,
                    size = proxy.getInventorySize()
                })
            end
        end
    end
    
    return inventories
end

-- Get all items from all inventories
local function getShopInventory()
    local items = {}
    local inventories = findInventoryComponents()
    
    for _, inv in ipairs(inventories) do
        local size = inv.size
        for slot = 1, size do
            local ok, stack = pcall(function()
                return inv.proxy.getStackInSlot(slot)
            end)
            
            if ok and stack and stack.name then
                local key = stack.name
                if not items[key] then
                    items[key] = {
                        name = key,
                        label = stack.label or key:match(":(.+)$") or key,
                        count = 0,
                        maxStack = stack.maxSize or 64,
                        damage = stack.damage or 0,
                        meta = stack.damage or 0,
                        from = {}
                    }
                end
                items[key].count = items[key].count + stack.size
                table.insert(items[key].from, {
                    inventory = inv,
                    slot = slot,
                    count = stack.size
                })
            end
        end
    end
    
    return items
end

-- ============================================
-- SHOP ITEMS MANAGEMENT
-- ============================================

local function addShopItem(itemName, price, stock, displayName)
    if not ShopDB[itemName] then
        ShopDB[itemName] = {
            price = price,
            stock = stock or -1, -- -1 = unlimited
            display_name = displayName or itemName,
            sold = 0,
            total_revenue = 0
        }
        saveData()
        return true
    end
    return false
end

local function removeShopItem(itemName)
    if ShopDB[itemName] then
        ShopDB[itemName] = nil
        saveData()
        return true
    end
    return false
end

local function updateShopItem(itemName, price, stock)
    if ShopDB[itemName] then
        ShopDB[itemName].price = price
        ShopDB[itemName].stock = stock or -1
        saveData()
        return true
    end
    return false
end

local function getShopItem(itemName)
    return ShopDB[itemName]
end

local function getShopItems()
    return ShopDB
end

-- ============================================
-- TRANSACTION FUNCTIONS
-- ============================================

-- Buy item from shop
local function buyItem(player, itemName, amount)
    local shopItem = getShopItem(itemName)
    if not shopItem then
        return false, "Item not found in shop"
    end
    
    local totalPrice = shopItem.price * amount
    
    -- Check stock
    if shopItem.stock ~= -1 and shopItem.stock < amount then
        return false, "Insufficient stock"
    end
    
    -- Check balance
    if not canAfford(player, totalPrice) then
        return false, string.format("Insufficient balance. Need %d %s",
            totalPrice, SHOP_CONFIG.currency_symbol)
    end
    
    -- Check if items exist in inventory
    local items = getShopInventory()
    local available = items[itemName]
    if not available or available.count < amount then
        return false, "Item not available in shop inventory"
    end
    
    -- Process transaction
    -- 1. Remove items from inventory
    local removed = 0
    local inventories = findInventoryComponents()
    for _, inv in ipairs(inventories) do
        if removed >= amount then break end
        local size = inv.size
        for slot = 1, size do
            if removed >= amount then break end
            local ok, stack = pcall(function()
                return inv.proxy.getStackInSlot(slot)
            end)
            if ok and stack and stack.name == itemName then
                local toRemove = math.min(stack.size, amount - removed)
                pcall(function()
                    inv.proxy.extractItem(slot, toRemove)
                end)
                removed = removed + toRemove
            end
        end
    end
    
    -- 2. Deduct balance
    addBalance(player, -totalPrice)
    
    -- 3. Update shop stats
    ShopDB[itemName].sold = (ShopDB[itemName].sold or 0) + amount
    ShopDB[itemName].total_revenue = (ShopDB[itemName].total_revenue or 0) + totalPrice
    if ShopDB[itemName].stock ~= -1 then
        ShopDB[itemName].stock = ShopDB[itemName].stock - amount
    end
    saveData()
    
    -- 4. Log transaction
    logTransaction(player, "BUY", itemName, amount, totalPrice)
    
    return true, string.format("Bought %d x %s for %d %s",
        amount, itemName, totalPrice, SHOP_CONFIG.currency_symbol)
end

-- Sell item to shop (buyback)
local function sellItem(player, itemName, amount)
    local shopItem = getShopItem(itemName)
    if not shopItem then
        return false, "We don't buy this item"
    end
    
    local price = math.floor(shopItem.price * SHOP_CONFIG.buyback_percentage)
    local totalPrice = price * amount
    
    -- Check player inventory (we need to get items from player somehow)
    -- For simplicity, we check the same inventory system
    local items = getShopInventory()
    local available = items[itemName]
    if not available or available.count < amount then
        return false, "Item not found in your inventory"
    end
    
    -- Process transaction
    -- 1. Add to inventory (move from player to shop)
    -- Actually, we're using shared inventory, so just remove from one place and add to another
    -- For now, we just remove from player's area (this is simplified)
    local removed = 0
    local inventories = findInventoryComponents()
    for _, inv in ipairs(inventories) do
        if removed >= amount then break end
        local size = inv.size
        for slot = 1, size do
            if removed >= amount then break end
            local ok, stack = pcall(function()
                return inv.proxy.getStackInSlot(slot)
            end)
            if ok and stack and stack.name == itemName then
                local toRemove = math.min(stack.size, amount - removed)
                pcall(function()
                    inv.proxy.extractItem(slot, toRemove)
                end)
                removed = removed + toRemove
            end
        end
    end
    
    -- 2. Add balance
    addBalance(player, totalPrice)
    
    -- 3. Log transaction
    logTransaction(player, "SELL", itemName, amount, totalPrice)
    
    saveData()
    
    return true, string.format("Sold %d x %s for %d %s",
        amount, itemName, totalPrice, SHOP_CONFIG.currency_symbol)
end

-- ============================================
-- SHOP UI FUNCTIONS
-- ============================================

-- Format item name for display
local function formatItemName(name)
    local display = name:match(":(.+)$") or name
    display = display:gsub("_", " ")
    display = display:gsub("tile.", "")
    display = display:gsub("item.", "")
    return display
end

-- Show shop catalog
local function showCatalog(player, page)
    page = page or 1
    local items = getShopInventory()
    local shopItems = getShopItems()
    
    term.clear()
    print("=" .. string.rep("=", 50))
    print("🛒 SHOP CATALOG")
    print("=" .. string.rep("=", 50))
    print(string.format("Player: %s | Balance: %d %s",
        player, getPlayerBalance(player), SHOP_CONFIG.currency_symbol))
    print(string.rep("-", 52))
    
    local itemList = {}
    for name, data in pairs(shopItems) do
        local inventory = items[name]
        local stock = data.stock == -1 and "∞" or tostring(data.stock)
        local available = inventory and inventory.count or 0
        
        table.insert(itemList, {
            name = name,
            display = data.display_name or formatItemName(name),
            price = data.price,
            stock = data.stock,
            available = available,
            sold = data.sold or 0
        })
    end
    
    table.sort(itemList, function(a, b)
        return a.name < b.name
    end)
    
    if #itemList == 0 then
        print("  No items in shop!")
        print("  Use /shop_admin to add items")
    else
        local startIndex = (page - 1) * SHOP_CONFIG.items_per_page + 1
        local endIndex = math.min(startIndex + SHOP_CONFIG.items_per_page - 1, #itemList)
        
        for i = startIndex, endIndex do
            local item = itemList[i]
            local stockDisplay = item.stock == -1 and "∞" or tostring(item.stock)
            local availDisplay = item.available > 0 and tostring(item.available) or "0"
            
            print(string.format("[%d] %s", i, item.display))
            print(string.format("    Price: %d %s | Stock: %s | Available: %s",
                item.price, SHOP_CONFIG.currency_symbol, stockDisplay, availDisplay))
            print("")
        end
        
        local totalPages = math.ceil(#itemList / SHOP_CONFIG.items_per_page)
        print(string.rep("-", 52))
        print(string.format("Page %d/%d | Items: %d", page, totalPages, #itemList))
        print("")
        print("Commands:")
        print("  buy <number> [amount] - Buy item")
        print("  sell <number> [amount] - Sell item")
        print("  info <number> - Show item info")
        print("  next/prev - Navigate pages")
        print("  balance - Show balance")
        print("  admin - Admin panel")
        print("  quit - Exit")
    end
    
    print("=" .. string.rep("=", 52))
    return itemList
end

-- Show admin panel
local function showAdminPanel(player)
    -- Check if player is admin (simple check - can be improved)
    local isAdmin = true -- For demo, everyone is admin
    if not isAdmin then
        print("Access denied. Admin privileges required.")
        return
    end
    
    term.clear()
    print("=" .. string.rep("=", 50))
    print("🔧 SHOP ADMIN PANEL")
    print("=" .. string.rep("=", 50))
    print("")
    print("1. Add item to shop")
    print("2. Remove item from shop")
    print("3. Update item price")
    print("4. Update item stock")
    print("5. Give money to player")
    print("6. View player stats")
    print("7. View shop stats")
    print("8. Refresh inventory")
    print("9. Reset shop")
    print("0. Back to catalog")
    print("")
    print("Enter command number: ")
    
    local choice = io.read()
    return choice
end

-- ============================================
-- MAIN SHOP LOOP
-- ============================================

local function runShop(playerName)
    if not playerName or playerName == "" then
        playerName = os.getenv("USER") or "Player"
    end
    
    loadData()
    
    -- Initialize player
    getPlayerBalance(playerName)
    
    local currentPage = 1
    local itemList = {}
    local running = true
    
    while running do
        -- Display catalog
        local newList = showCatalog(playerName, currentPage)
        if newList then
            itemList = newList
        end
        
        print("")
        print("> " .. string.rep("-", 50) .. " >")
        print("Enter command: ")
        local input = io.read()
        
        if not input or input == "quit" or input == "exit" then
            running = false
            break
        end
        
        -- Parse commands
        local cmd = input:match("^(%S+)")
        local args = {}
        for arg in input:gmatch("%S+") do
            table.insert(args, arg)
        end
        
        if cmd == "buy" and #args >= 2 then
            local itemNum = tonumber(args[2])
            local amount = tonumber(args[3]) or 1
            
            if itemNum and itemNum >= 1 and itemNum <= #itemList then
                local itemName = itemList[itemNum].name
                local ok, msg = buyItem(playerName, itemName, amount)
                if ok then
                    print("✓ " .. msg)
                else
                    print("✗ " .. msg)
                end
                print("Press Enter to continue...")
                io.read()
            else
                print("Invalid item number")
            end
            
        elseif cmd == "sell" and #args >= 2 then
            local itemNum = tonumber(args[2])
            local amount = tonumber(args[3]) or 1
            
            if itemNum and itemNum >= 1 and itemNum <= #itemList then
                local itemName = itemList[itemNum].name
                local ok, msg = sellItem(playerName, itemName, amount)
                if ok then
                    print("✓ " .. msg)
                else
                    print("✗ " .. msg)
                end
                print("Press Enter to continue...")
                io.read()
            else
                print("Invalid item number")
            end
            
        elseif cmd == "info" and #args >= 2 then
            local itemNum = tonumber(args[2])
            if itemNum and itemNum >= 1 and itemNum <= #itemList then
                local item = itemList[itemNum]
                term.clear()
                print("=" .. string.rep("=", 50))
                print("📦 ITEM DETAILS")
                print("=" .. string.rep("=", 50))
                print(string.format("Name: %s", item.display))
                print(string.format("ID: %s", item.name))
                print(string.format("Price: %d %s", item.price, SHOP_CONFIG.currency_symbol))
                print(string.format("Stock: %s", item.stock == -1 and "∞" or tostring(item.stock)))
                print(string.format("Available: %d", item.available))
                print(string.format("Sold: %d", item.sold or 0))
                print("")
                print("Press Enter to continue...")
                io.read()
            end
            
        elseif cmd == "balance" then
            local balance = getPlayerBalance(playerName)
            print(string.format("Your balance: %d %s", balance, SHOP_CONFIG.currency_symbol))
            print("Press Enter to continue...")
            io.read()
            
        elseif cmd == "next" then
            currentPage = currentPage + 1
            
        elseif cmd == "prev" or cmd == "back" then
            if currentPage > 1 then
                currentPage = currentPage - 1
            end
            
        elseif cmd == "admin" then
            local choice = showAdminPanel(playerName)
            if choice == "1" then
                print("Enter item ID (e.g., minecraft:stone): ")
                local itemId = io.read()
                print("Enter price: ")
                local price = tonumber(io.read())
                print("Enter stock (0 for unlimited): ")
                local stock = tonumber(io.read())
                if itemId and price then
                    addShopItem(itemId, price, stock or -1)
                    print("Item added successfully!")
                else
                    print("Invalid input")
                end
                print("Press Enter to continue...")
                io.read()
                
            elseif choice == "2" then
                print("Enter item ID to remove: ")
                local itemId = io.read()
                if itemId and removeShopItem(itemId) then
                    print("Item removed successfully!")
                else
                    print("Item not found")
                end
                print("Press Enter to continue...")
                io.read()
                
            elseif choice == "3" then
                print("Enter item ID: ")
                local itemId = io.read()
                print("Enter new price: ")
                local price = tonumber(io.read())
                if itemId and price and updateShopItem(itemId, price) then
                    print("Price updated!")
                else
                    print("Update failed")
                end
                print("Press Enter to continue...")
                io.read()
                
            elseif choice == "5" then
                print("Enter player name: ")
                local targetPlayer = io.read()
                print("Enter amount: ")
                local amount = tonumber(io.read())
                if targetPlayer and amount then
                    addBalance(targetPlayer, amount)
                    print(string.format("Added %d %s to %s",
                        amount, SHOP_CONFIG.currency_symbol, targetPlayer))
                end
                print("Press Enter to continue...")
                io.read()
                
            elseif choice == "8" then
                itemList = {}
                print("Inventory refreshed!")
                print("Press Enter to continue...")
                io.read()
                
            elseif choice == "0" then
                -- Back to catalog
            end
            
        else
            if input ~= "" then
                print("Unknown command. Use: buy, sell, info, next, prev, balance, admin, quit")
                print("Press Enter to continue...")
                io.read()
            end
        end
    end
    
    saveData()
    print("Thank you for using the shop!")
end

-- ============================================
-- ADMIN COMMANDS (for initial setup)
-- ============================================

local function setupShop()
    print("Setting up shop...")
    loadData()
    
    -- Add some default items
    local defaultItems = {
        {"minecraft:stone", 10, 64},
        {"minecraft:dirt", 5, 64},
        {"minecraft:cobblestone", 5, 64},
        {"minecraft:oak_log", 20, 32},
        {"minecraft:iron_ingot", 50, 16},
        {"minecraft:gold_ingot", 100, 8},
        {"minecraft:diamond", 200, 4},
    }
    
    local count = 0
    for _, item in ipairs(defaultItems) do
        if not ShopDB[item[1]] then
            addShopItem(item[1], item[2], item[3])
            count = count + 1
        end
    end
    
    print(string.format("Added %d default items to shop", count))
    saveData()
    print("Setup complete!")
end

-- ============================================
-- MAIN ENTRY POINT
-- ============================================

local function main()
    term.clear()
    print("=" .. string.rep("=", 50))
    print("🏪 WELCOME TO THE SHOP")
    print("=" .. string.rep("=", 50))
    print("")
    
    -- Check if shop exists
    loadData()
    if not next(ShopDB) then
        print("No shop items found!")
        print("Would you like to setup default items? (yes/no)")
        local response = io.read()
        if response and response:lower():match("^y") then
            setupShop()
        end
    end
    
    print("Loading shop...")
    print("")
    
    print("Enter your name (or press Enter for default):")
    local playerName = io.read()
    if not playerName or playerName == "" then
        playerName = os.getenv("USER") or "Player"
    end
    
    runShop(playerName)
end

-- Run the program
local ok, err = pcall(main)
if not ok then
    print("Error: " .. tostring(err))
    print("Press any key to exit...")
    event.pull("key")
end
