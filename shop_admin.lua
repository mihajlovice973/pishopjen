-- shop_admin.lua
-- Admin tools for the shop system

local component = require("component")
local fs = require("filesystem")

-- Load shop data
local function loadData()
    if fs.exists("/home/shop_data.lua") then
        local data = dofile("/home/shop_data.lua")
        return data
    end
    return nil
end

-- Save shop data
local function saveData(data)
    local file = io.open("/home/shop_data.lua", "w")
    if file then
        file:write("return " .. require("serialization").serialize(data))
        file:close()
        return true
    end
    return false
end

-- Admin menu
local function adminMenu()
    term.clear()
    print("=" .. string.rep("=", 50))
    print("🔧 SHOP ADMIN TOOLS")
    print("=" .. string.rep("=", 50))
    print("")
    print("1. Add item")
    print("2. Remove item")
    print("3. Update price")
    print("4. Update stock")
    print("5. Give money to player")
    print("6. View all players")
    print("7. View shop stats")
    print("8. Reset all player balances")
    print("9. Export shop data")
    print("0. Exit")
    print("")
    print("Enter choice: ")
    
    return io.read()
end

-- Main admin loop
local function main()
    local data = loadData()
    if not data then
        print("No shop data found!")
        print("Please run the shop first to create data.")
        return
    end
    
    local running = true
    while running do
        local choice = adminMenu()
        
        if choice == "1" then
            print("Enter item ID: ")
            local itemId = io.read()
            print("Enter price: ")
            local price = tonumber(io.read())
            print("Enter stock (0 for unlimited): ")
            local stock = tonumber(io.read())
            
            if itemId and price then
                data.shop[itemId] = {
                    price = price,
                    stock = stock or -1,
                    display_name = itemId:match(":(.+)$") or itemId
                }
                saveData(data)
                print("Item added!")
            end
            
        elseif choice == "2" then
            print("Enter item ID to remove: ")
            local itemId = io.read()
            if itemId and data.shop[itemId] then
                data.shop[itemId] = nil
                saveData(data)
                print("Item removed!")
            else
                print("Item not found")
            end
            
        elseif choice == "5" then
            print("Enter player name: ")
            local player = io.read()
            print("Enter amount: ")
            local amount = tonumber(io.read())
            
            if player and amount then
                if not data.players[player] then
                    data.players[player] = {balance = 0}
                end
                data.players[player].balance = data.players[player].balance + amount
                saveData(data)
                print(string.format("Added %d to %s", amount, player))
            end
            
        elseif choice == "6" then
            print("Players:")
            for name, info in pairs(data.players) do
                print(string.format("  %s: %d %s", 
                    name, info.balance, "Coins"))
            end
            
        elseif choice == "0" then
            running = false
            
        else
            print("Invalid choice")
        end
        
        if running then
            print("Press Enter to continue...")
            io.read()
        end
    end
end

main()
