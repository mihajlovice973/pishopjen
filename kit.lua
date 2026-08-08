-- oc_diagnostic.lua
-- Full diagnostic script for OpenComputers
-- Safe read-only inspection of all components

local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local event = require("event")
local term = require("term")
local os = require("os")

-- Configuration
local REPORT_PATH = "/home/oc_diagnostic_report.txt"
local REPORT_PATH_FALLBACK = "/oc_diagnostic_report.txt"
local OUTPUT_BUFFER = {}
local START_TIME = os.time()

-- Known component types for special handling
local KNOWN_TYPES = {
    gpu = true,
    screen = true,
    keyboard = true,
    computer = true,
    filesystem = true,
    modem = true,
    internet = true,
    pim = true,
    me_interface = true,
    me_bridge = true,
    me_controller = true,
    aemultipart = true,
    openperipheral_selector = true,
    item_selector = true,
    selector = true,
    openperipheral_bridge = true,
    openperipheral_sensor = true,
    sensor = true,
    entity_sensor = true,
    playerDetector = true,
    player_detector = true,
    entityDetector = true,
    entity_detector = true,
    radar = true,
    average_counter = true,
}

-- Methods that should never be called (dangerous)
local DANGEROUS_METHODS = {
    pushItem = true,
    pullItem = true,
    pushItemIntoSlot = true,
    pullItemIntoSlot = true,
    destroyStack = true,
    swapStacks = true,
    condenseItems = true,
    expandStack = true,
    exportItem = true,
    importItem = true,
    requestCrafting = true,
    craft = true,
    shutdown = true,
    reboot = true,
    format = true,
    remove = true,
    delete = true,
    write = true,
    open = true,
    close = true,
    send = true,
    broadcast = true,
    setText = true,
    clear = true,
    fill = true,
}

-- Safe read-only methods that can be tested
local SAFE_METHODS = {
    getInventorySize = true,
    getStackInSlot = true,
    getAllStacks = true,
    listSources = true,
    getItemsInNetwork = true,
    getItemDetail = true,
    getCraftables = true,
    getCpus = true,
    getCraftingCPUs = true,
    getStoredPower = true,
    getMaxStoredPower = true,
    getInventoryName = true,
    getSize = true,
    getLabel = true,
    getSpeed = true,
    getResolution = true,
    getMaxResolution = true,
    getDepth = true,
    getMaxDepth = true,
    isActive = true,
    isOnline = true,
    isPresent = true,
}

-- Output functions
local function addLine(str)
    str = str or ""
    table.insert(OUTPUT_BUFFER, str)
    print(str)
end

local function addSeparator(char)
    char = char or "="
    addLine(string.rep(char, 70))
end

local function addHeader(text)
    addSeparator()
    addLine(text)
    addSeparator()
end

local function addSubHeader(text)
    addSeparator("-")
    addLine(text)
    addSeparator("-")
end

-- Safe pcall wrapper
local function safeCall(func, ...)
    local args = {...}
    local ok, result = pcall(function()
        return func(table.unpack(args))
    end)
    if ok then
        return true, result
    else
        return false, result
    end
end

-- Get component methods safely
local function getComponentMethods(addr)
    local methods = {}
    
    -- Try component.methods
    local ok, result = safeCall(component.methods, addr)
    if ok and type(result) == "table" then
        for k, v in pairs(result) do
            if type(v) == "function" or type(v) == "string" then
                methods[k] = true
            end
        end
        return methods
    end
    
    -- Try proxy methods
    local ok, proxy = safeCall(component.proxy, addr)
    if ok and type(proxy) == "table" then
        local seen = {}
        local function scanTable(t, prefix)
            prefix = prefix or ""
            for k, v in pairs(t) do
                if type(k) == "string" and not seen[k] then
                    seen[k] = true
                    if type(v) == "function" then
                        methods[k] = true
                    elseif type(v) == "table" and prefix ~= "" then
                        scanTable(v, prefix .. "." .. k)
                    end
                end
            end
        end
        scanTable(proxy)
    end
    
    return methods
end

-- Get component documentation
local function getMethodDoc(addr, method)
    local ok, doc = safeCall(component.doc, addr, method)
    if ok and doc and doc ~= "" then
        return doc
    end
    
    -- Try proxy.doc
    local ok, proxy = safeCall(component.proxy, addr)
    if ok and type(proxy) == "table" and type(proxy.doc) == "function" then
        local ok2, doc2 = safeCall(proxy.doc, method)
        if ok2 and doc2 and doc2 ~= "" then
            return doc2
        end
    end
    
    return nil
end

-- Safe method call for read-only methods
local function safeInvoke(addr, method, ...)
    local args = {...}
    local ok, result = pcall(function()
        return component.invoke(addr, method, table.unpack(args))
    end)
    if ok then
        return true, result
    else
        return false, result
    end
end

-- Analyze a single component
local function analyzeComponent(addr, name, index)
    addHeader(string.format("COMPONENT #%d", index))
    addLine(string.format("Address: %s", addr))
    addLine(string.format("Type: %s", name))
    
    -- Short address
    local shortAddr = string.sub(addr, 1, 8)
    addLine(string.format("Short Address: %s...", shortAddr))
    
    -- Check if primary
    local isPrimary = false
    for primaryName, primaryAddr in pairs(component) do
        if primaryAddr == addr then
            isPrimary = true
            addLine(string.format("Primary: YES (accessible as component.%s)", primaryName))
            break
        end
    end
    if not isPrimary then
        addLine("Primary: NO")
    end
    
    -- Test proxy
    local ok, proxy = safeCall(component.proxy, addr)
    if ok and type(proxy) == "table" then
        addLine("Proxy: OK")
    else
        addLine(string.format("Proxy: FAILED (%s)", tostring(proxy or "unknown")))
    end
    
    -- Get methods
    addLine("\nMethods:")
    addLine("------------------------------------------------")
    local methods = getComponentMethods(addr)
    
    if not methods or next(methods) == nil then
        addLine("  (No methods found or unable to retrieve)")
    else
        local methodList = {}
        for methodName, _ in pairs(methods) do
            table.insert(methodList, methodName)
        end
        table.sort(methodList)
        
        for i, methodName in ipairs(methodList) do
            local display = string.format("  %d. %s", i, methodName)
            
            -- Check if dangerous
            if DANGEROUS_METHODS[methodName] then
                display = display .. " ⚠️  [DANGEROUS - NOT CALLED]"
            elseif SAFE_METHODS[methodName] then
                display = display .. " ✓ [SAFE]"
            end
            
            addLine(display)
            
            -- Try to get documentation
            local doc = getMethodDoc(addr, methodName)
            if doc then
                addLine(string.format("     DOC: %s", doc:gsub("\n", "\n     ")))
            else
                addLine("     DOC: unavailable")
            end
            
            -- Test safe read-only methods
            if SAFE_METHODS[methodName] then
                local ok2, result = safeInvoke(addr, methodName)
                if ok2 then
                    if type(result) == "table" then
                        if next(result) ~= nil then
                            addLine(string.format("     TEST: OK (returns table with %d entries)", table.maxn(result)))
                        else
                            addLine("     TEST: OK (returns empty table)")
                        end
                    else
                        addLine(string.format("     TEST: OK (returns: %s)", tostring(result)))
                    end
                else
                    addLine(string.format("     TEST: FAILED (%s)", tostring(result or "unknown")))
                end
            end
        end
    end
    addLine("")
end

-- Check primary components
local function checkPrimaryComponents()
    addHeader("PRIMARY COMPONENTS")
    
    local primaryList = {
        "gpu", "screen", "keyboard", "computer", 
        "filesystem", "modem", "internet", "pim"
    }
    
    for _, name in ipairs(primaryList) do
        local ok, comp = safeCall(component.__index, component, name)
        if ok and comp then
            addLine(string.format("%s: FOUND", string.upper(name)))
            addLine(string.format("  Address: %s", tostring(comp)))
        else
            addLine(string.format("%s: NOT FOUND", string.upper(name)))
        end
    end
    addLine("")
end

-- Special check for Modem
local function checkModem(addr)
    if not addr then return end
    
    addHeader("MODEM DETAILED DIAGNOSTIC")
    addLine(string.format("Address: %s", addr))
    
    -- Check wireless capability
    local ok, isWireless = safeInvoke(addr, "isWireless")
    if ok then
        addLine(string.format("Wireless: %s", tostring(isWireless)))
    else
        addLine("Wireless: unknown (method not available)")
    end
    
    -- Check maximum packet size
    local ok, maxSize = safeInvoke(addr, "getMaxPacketSize")
    if ok then
        addLine(string.format("Max Packet Size: %s", tostring(maxSize)))
    end
    
    -- Check signal strength (if available)
    local ok, strength = safeInvoke(addr, "getStrength")
    if ok then
        addLine(string.format("Signal Strength: %s", tostring(strength)))
    end
    
    -- Check open ports (read-only)
    local ok, ports = safeInvoke(addr, "getOpenPorts")
    if ok and type(ports) == "table" then
        local portList = {}
        for _, p in ipairs(ports) do
            table.insert(portList, tostring(p))
        end
        if #portList > 0 then
            addLine(string.format("Open Ports: %s", table.concat(portList, ", ")))
        else
            addLine("Open Ports: none")
        end
    else
        addLine("Open Ports: unable to retrieve")
    end
    
    -- Check network functions
    local methods = getComponentMethods(addr)
    if methods then
        local networkMethods = {}
        for m, _ in pairs(methods) do
            if m:find("send") or m:find("broadcast") or m:find("listen") or 
               m:find("transmit") or m:find("receive") then
                table.insert(networkMethods, m)
            end
        end
        if #networkMethods > 0 then
            table.sort(networkMethods)
            addLine("Network functions available:")
            for _, m in ipairs(networkMethods) do
                addLine(string.format("  - %s", m))
            end
        end
    end
    addLine("")
end

-- Special check for Internet
local function checkInternet(addr)
    if not addr then return end
    
    addHeader("INTERNET DETAILED DIAGNOSTIC")
    addLine(string.format("Address: %s", addr))
    
    local methods = getComponentMethods(addr)
    if methods then
        addLine("Available methods:")
        local methodList = {}
        for m, _ in pairs(methods) do
            table.insert(methodList, m)
        end
        table.sort(methodList)
        for _, m in ipairs(methodList) do
            addLine(string.format("  - %s", m))
        end
        
        -- Check specific methods
        addLine("\nAPI Support:")
        addLine(string.format("  request: %s", methods.request and "YES" or "NO"))
        addLine(string.format("  connect: %s", methods.connect and "YES" or "NO"))
        addLine(string.format("  http: %s", methods.http and "YES" or "NO"))
    end
    addLine("")
end

-- Special check for PIM
local function checkPIM(addr)
    if not addr then return end
    
    addHeader("PIM DETAILED DIAGNOSTIC")
    addLine(string.format("Address: %s", addr))
    
    local methods = getComponentMethods(addr)
    if methods then
        addLine("Available methods:")
        local methodList = {}
        for m, _ in pairs(methods) do
            table.insert(methodList, m)
        end
        table.sort(methodList)
        for _, m in ipairs(methodList) do
            addLine(string.format("  - %s", m))
        end
        
        addLine("\nPIM-specific methods check:")
        local pimMethods = {
            "getInventorySize", "getStackInSlot", "getAllStacks",
            "pushItem", "pullItem", "pushItemIntoSlot", "pullItemIntoSlot",
            "listSources"
        }
        for _, m in ipairs(pimMethods) do
            if methods[m] then
                addLine(string.format("  %s: ✓ EXISTS", m))
                -- Test safe ones
                if SAFE_METHODS[m] then
                    local ok, result = safeInvoke(addr, m)
                    if ok then
                        if type(result) == "table" then
                            addLine(string.format("    TEST: OK (returns table)"))
                        else
                            addLine(string.format("    TEST: OK (returns: %s)", tostring(result)))
                        end
                    else
                        addLine(string.format("    TEST: FAILED (%s)", tostring(result or "unknown")))
                    end
                else
                    addLine("    [SAFE TEST NOT PERFORMED - dangerous method]")
                end
            else
                addLine(string.format("  %s: ✗ NOT FOUND", m))
            end
        end
    end
    addLine("")
end

-- Special check for Item Selector
local function checkItemSelector(addr)
    if not addr then return end
    
    addHeader("ITEM SELECTOR DETAILED DIAGNOSTIC")
    addLine(string.format("Address: %s", addr))
    
    local methods = getComponentMethods(addr)
    if methods then
        addLine("Available methods:")
        local methodList = {}
        for m, _ in pairs(methods) do
            table.insert(methodList, m)
        end
        table.sort(methodList)
        for _, m in ipairs(methodList) do
            addLine(string.format("  - %s", m))
        end
        
        addLine("\nSelector-specific methods check:")
        local selectorMethods = {
            "pushItem", "pullItem", "pushItemIntoSlot", "pullItemIntoSlot",
            "getInventorySize", "getStackInSlot", "getAllStacks",
            "listSources", "expandStack", "condenseItems", "swapStacks",
            "destroyStack", "getInventoryName", "doc"
        }
        for _, m in ipairs(selectorMethods) do
            if methods[m] then
                local danger = DANGEROUS_METHODS[m] and " ⚠️ DANGEROUS" or ""
                addLine(string.format("  %s: ✓ EXISTS%s", m, danger))
                if SAFE_METHODS[m] then
                    local ok, result = safeInvoke(addr, m)
                    if ok then
                        addLine(string.format("    TEST: OK"))
                    else
                        addLine(string.format("    TEST: FAILED (%s)", tostring(result or "unknown")))
                    end
                elseif not DANGEROUS_METHODS[m] and m ~= "doc" then
                    addLine("    [SAFE TEST NOT PERFORMED - unknown safety]")
                end
            else
                addLine(string.format("  %s: ✗ NOT FOUND", m))
            end
        end
    end
    addLine("")
end

-- Special check for AE2/ME
local function checkAE2(addr)
    if not addr then return end
    
    addHeader("AE2 / ME SYSTEM DETAILED DIAGNOSTIC")
    addLine(string.format("Address: %s", addr))
    
    local methods = getComponentMethods(addr)
    if methods then
        addLine("Available methods:")
        local methodList = {}
        for m, _ in pairs(methods) do
            table.insert(methodList, m)
        end
        table.sort(methodList)
        for _, m in ipairs(methodList) do
            addLine(string.format("  - %s", m))
        end
        
        addLine("\nAE2-specific methods check:")
        local ae2Methods = {
            "getItemsInNetwork", "getItemDetail", "getCraftables",
            "getCpus", "getCraftingCPUs", "getStoredPower",
            "getMaxStoredPower", "exportItem", "importItem",
            "requestCrafting", "craft"
        }
        for _, m in ipairs(ae2Methods) do
            if methods[m] then
                local danger = DANGEROUS_METHODS[m] and " ⚠️ DANGEROUS" or ""
                addLine(string.format("  %s: ✓ EXISTS%s", m, danger))
                if SAFE_METHODS[m] then
                    local ok, result = safeInvoke(addr, m)
                    if ok then
                        if type(result) == "table" then
                            addLine(string.format("    TEST: OK (returns table)"))
                        else
                            addLine(string.format("    TEST: OK (returns: %s)", tostring(result)))
                        end
                    else
                        addLine(string.format("    TEST: FAILED (%s)", tostring(result or "unknown")))
                    end
                elseif not DANGEROUS_METHODS[m] then
                    addLine("    [SAFE TEST NOT PERFORMED - unknown safety]")
                end
            else
                addLine(string.format("  %s: ✗ NOT FOUND", m))
            end
        end
    end
    addLine("")
end

-- Special check for Sensor/Radar
local function checkSensor(addr)
    if not addr then return end
    
    addHeader("SENSOR / RADAR DETAILED DIAGNOSTIC")
    addLine(string.format("Address: %s", addr))
    
    local methods = getComponentMethods(addr)
    if methods then
        addLine("Available methods:")
        local methodList = {}
        for m, _ in pairs(methods) do
            table.insert(methodList, m)
        end
        table.sort(methodList)
        for _, m in ipairs(methodList) do
            addLine(string.format("  - %s", m))
        end
        
        addLine("\nCapabilities check:")
        local capabilities = {
            "getPlayers", "getPlayer", "getPlayerName", "getPlayersByUUID",
            "getEntities", "getEntity", "getEntitiesByType",
            "getDistance", "getMaxDistance", "getRange",
            "scan", "detect"
        }
        for _, m in ipairs(capabilities) do
            if methods[m] then
                addLine(string.format("  %s: ✓ AVAILABLE", m))
                if SAFE_METHODS[m] then
                    local ok, result = safeInvoke(addr, m)
                    if ok then
                        if type(result) == "table" then
                            addLine(string.format("    TEST: OK (returns table)"))
                        else
                            addLine(string.format("    TEST: OK (returns: %s)", tostring(result)))
                        end
                    else
                        addLine(string.format("    TEST: FAILED (%s)", tostring(result or "unknown")))
                    end
                end
            else
                addLine(string.format("  %s: ✗ NOT AVAILABLE", m))
            end
        end
    end
    addLine("")
end

-- Main diagnostic function
local function runDiagnostic()
    -- Clear terminal
    term.clear()
    
    addHeader("OPENCOMPUTERS FULL DIAGNOSTIC REPORT")
    addLine(string.format("Generated: %s", os.date("%Y-%m-%d %H:%M:%S")))
    addLine(string.format("Lua Version: %s", _VERSION or "unknown"))
    
    -- System information
    addHeader("SYSTEM INFORMATION")
    local ok, uptime = safeCall(computer.uptime)
    if ok and uptime then
        local hours = math.floor(uptime / 3600)
        local minutes = math.floor((uptime % 3600) / 60)
        local seconds = math.floor(uptime % 60)
        addLine(string.format("Uptime: %dh %dm %ds", hours, minutes, seconds))
    else
        addLine("Uptime: unavailable")
    end
    
    local ok, totalMem = safeCall(computer.totalMemory)
    if ok and totalMem then
        addLine(string.format("Total Memory: %d MB", math.floor(totalMem / 1024 / 1024)))
    end
    
    local ok, freeMem = safeCall(computer.freeMemory)
    if ok and freeMem then
        addLine(string.format("Free Memory: %d MB", math.floor(freeMem / 1024 / 1024)))
    end
    
    local ok, compAddr = safeCall(computer.address)
    if ok and compAddr then
        addLine(string.format("Computer Address: %s", compAddr))
    end
    
    -- GPU info
    local ok, gpu = safeCall(component.__index, component, "gpu")
    if ok and gpu then
        local ok2, resX, resY = safeCall(component.invoke, gpu, "getResolution")
        if ok2 then
            addLine(string.format("GPU Resolution: %dx%d", resX or 0, resY or 0))
        end
        local ok2, maxX, maxY = safeCall(component.invoke, gpu, "getMaxResolution")
        if ok2 then
            addLine(string.format("GPU Max Resolution: %dx%d", maxX or 0, maxY or 0))
        end
        local ok2, depth = safeCall(component.invoke, gpu, "getDepth")
        if ok2 then
            addLine(string.format("GPU Depth: %d", depth or 0))
        end
    else
        addLine("GPU: not found")
    end
    
    -- Screen info
    local ok, screen = safeCall(component.__index, component, "screen")
    if ok and screen then
        addLine(string.format("Screen Address: %s", tostring(screen)))
    else
        addLine("Screen: not found")
    end
    
    -- Filesystem info
    local ok, fsys = safeCall(component.__index, component, "filesystem")
    if ok and fsys then
        addLine(string.format("Filesystem Address: %s", tostring(fsys)))
    else
        addLine("Filesystem: not found")
    end
    
    -- Count components
    local componentCount = 0
    for _, _ in component.list() do
        componentCount = componentCount + 1
    end
    addLine(string.format("Total Components Detected: %d", componentCount))
    
    -- List all components
    addHeader("ALL COMPONENTS (COMPLETE LIST)")
    local compList = {}
    for addr, name in component.list() do
        table.insert(compList, {addr = addr, name = name})
    end
    
    -- Sort by name
    table.sort(compList, function(a, b)
        return a.name < b.name
    end)
    
    -- Show summary list first
    addLine("Component summary:")
    for i, comp in ipairs(compList) do
        local shortAddr = string.sub(comp.addr, 1, 8)
        addLine(string.format("  %d. %s (%s...)", i, comp.name, shortAddr))
    end
    addLine("")
    
    -- Detailed analysis of each component
    local componentIndex = 0
    local foundTypes = {}
    
    for _, comp in ipairs(compList) do
        componentIndex = componentIndex + 1
        local addr = comp.addr
        local name = comp.name
        
        -- Track found types
        foundTypes[name] = true
        
        analyzeComponent(addr, name, componentIndex)
        
        -- Special detailed checks for specific types
        if name == "modem" or name:find("modem") then
            checkModem(addr)
        elseif name == "internet" or name:find("internet") then
            checkInternet(addr)
        elseif name == "pim" then
            checkPIM(addr)
        elseif name:find("selector") or name:find("Selector") then
            checkItemSelector(addr)
        elseif name:find("me_") or name:find("ME") or name:find("aemultipart") then
            checkAE2(addr)
        elseif name:find("sensor") or name:find("radar") or name:find("detector") then
            checkSensor(addr)
        end
    end
    
    -- Summary
    addHeader("SUMMARY")
    addLine(string.format("Total components: %d", componentCount))
    addLine("")
    
    addLine("Key components status:")
    local keyComponents = {
        "gpu", "screen", "keyboard", "computer", "filesystem",
        "modem", "internet", "pim"
    }
    for _, name in ipairs(keyComponents) do
        local ok, comp = safeCall(component.__index, component, name)
        if ok and comp then
            addLine(string.format("  %s: YES", string.upper(name)))
        else
            addLine(string.format("  %s: NO", string.upper(name)))
        end
    end
    
    addLine("")
    addLine("Found component types:")
    local typeList = {}
    for t, _ in pairs(foundTypes) do
        table.insert(typeList, t)
    end
    table.sort(typeList)
    for _, t in ipairs(typeList) do
        local known = KNOWN_TYPES[t] and " (known)" or " (custom/unknown)"
        addLine(string.format("  - %s%s", t, known))
    end
    
    -- Unknown components summary
    addLine("")
    local unknownTypes = {}
    for t, _ in pairs(foundTypes) do
        if not KNOWN_TYPES[t] then
            table.insert(unknownTypes, t)
        end
    end
    if #unknownTypes > 0 then
        addLine("⚠️ Custom/Unknown components detected:")
        for _, t in ipairs(unknownTypes) do
            addLine(string.format("  - %s", t))
        end
    end
    
    -- End
    addSeparator()
    addLine("DIAGNOSTIC COMPLETE")
    addSeparator()
    
    local endTime = os.time()
    local duration = endTime - START_TIME
    addLine(string.format("Scan duration: %d seconds", duration))
end

-- Save report to file
local function saveReport()
    local fullReport = table.concat(OUTPUT_BUFFER, "\n")
    
    local reportPath = REPORT_PATH
    local ok = fs.exists(fs.path(REPORT_PATH))
    if not ok then
        reportPath = REPORT_PATH_FALLBACK
    end
    
    local file, err = io.open(reportPath, "w")
    if not file then
        -- Try fallback
        file, err = io.open(REPORT_PATH_FALLBACK, "w")
        if not file then
            addLine(string.format("\nERROR: Could not save report: %s", tostring(err)))
            addLine("Report is only shown on screen.")
            return
        end
        reportPath = REPORT_PATH_FALLBACK
    end
    
    file:write(fullReport)
    file:close()
    
    addLine("\n========================================")
    addLine("Report saved to:")
    addLine(reportPath)
    addLine("========================================")
end

-- Main execution with error handling
local function main()
    local ok, err = pcall(function()
        runDiagnostic()
        saveReport()
    end)
    
    if not ok then
        addLine(string.format("\n⚠️ CRITICAL ERROR: %s", tostring(err)))
        addLine("Some components may not have been fully analyzed.")
        addLine("The report is still partial.")
        
        -- Try to save what we have
        saveReport()
    end
    
    addLine("\nInstructions:")
    addLine("1. Copy this entire output or")
    addLine("2. Use: edit /home/oc_diagnostic_report.txt")
    addLine("3. Send the report to an AI for analysis")
    addLine("")
end

-- Run the script
main()
