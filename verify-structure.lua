--[[
    Roblox Studio Structure Verification Script

    Run this in Command Bar to verify your plugin structure is correct.

    Usage:
    1. Copy this entire script
    2. Open Roblox Studio
    3. View → Command Bar (if not visible)
    4. Paste this script into Command Bar
    5. Press Enter
    6. Check Output window for results
]]

local function verifyStructure()
    print("=== Lux Plugin Structure Verification ===")
    print("")

    -- Find the Lux folder - try multiple locations
    local lux = nil
    local searchLocations = {
        game.ServerStorage,
        game.ReplicatedStorage,
        workspace,
        game:GetService("ServerScriptService")
    }

    for _, location in ipairs(searchLocations) do
        local found = location:FindFirstChild("Lux")
        if found then
            lux = found
            print("✓ Found Lux folder in: " .. location:GetFullName())
            break
        end
    end

    if not lux then
        warn("✗ CRITICAL: Cannot find 'Lux' folder anywhere!")
        warn("  Searched in: ServerStorage, ReplicatedStorage, Workspace, ServerScriptService")
        return false
    end

    print("")

    -- Check Main script
    local main = lux:FindFirstChild("Main")
    if not main then
        warn("✗ CRITICAL: Missing 'Main' script in Lux folder")
        return false
    elseif not main:IsA("Script") then
        warn("✗ ERROR: 'Main' should be a Script, found: " .. main.ClassName)
        return false
    else
        print("✓ Main script exists and is correct type")
    end

    -- Check src folder
    local src = lux:FindFirstChild("src")
    if not src then
        warn("✗ CRITICAL: Missing 'src' folder in Lux")
        return false
    elseif not src:IsA("Folder") then
        warn("✗ ERROR: 'src' should be a Folder, found: " .. src.ClassName)
        return false
    else
        print("✓ src folder exists")
    end

    print("")
    print("=== Checking Module Folders ===")

    -- Required folders with their required ModuleScripts
    local requiredFolders = {
        "Core", "Memory", "Safety", "Context",
        "Planning", "Tools", "Coordination", "UI", "Shared"
    }

    local allValid = true

    for _, folderName in ipairs(requiredFolders) do
        local folder = src:FindFirstChild(folderName)

        if not folder then
            warn("✗ MISSING: " .. folderName .. " folder")
            allValid = false
        elseif not folder:IsA("Folder") then
            warn("✗ ERROR: " .. folderName .. " should be a Folder, found: " .. folder.ClassName)
            allValid = false
        else
            -- Check for init ModuleScript
            local init = folder:FindFirstChild("init")

            if not init then
                warn("✗ MISSING: " .. folderName .. "/init ModuleScript")
                warn("  Found children: " .. table.concat((function()
                    local names = {}
                    for _, child in ipairs(folder:GetChildren()) do
                        table.insert(names, child.Name .. " (" .. child.ClassName .. ")")
                    end
                    return names
                end)(), ", "))
                allValid = false
            elseif not init:IsA("ModuleScript") then
                warn("✗ ERROR: " .. folderName .. "/init should be a ModuleScript, found: " .. init.ClassName)
                allValid = false
            else
                -- Check if init has content
                local source = init.Source
                if source == "" or source == "return {}" or source:match("^%s*$") then
                    warn("⚠ WARNING: " .. folderName .. "/init is empty or default")
                    allValid = false
                else
                    print("✓ " .. folderName .. "/init exists and has content (" .. #source .. " chars)")
                end
            end
        end
    end

    print("")
    print("=== Checking OpenRouterClient ===")

    -- Check OpenRouterClient
    local openRouterClient = src:FindFirstChild("OpenRouterClient")
    if not openRouterClient then
        warn("✗ MISSING: OpenRouterClient ModuleScript in src")
        allValid = false
    elseif not openRouterClient:IsA("ModuleScript") then
        warn("✗ ERROR: OpenRouterClient should be a ModuleScript, found: " .. openRouterClient.ClassName)
        allValid = false
    else
        local source = openRouterClient.Source
        if source == "" or source:match("^%s*$") then
            warn("⚠ WARNING: OpenRouterClient is empty")
            allValid = false
        else
            print("✓ OpenRouterClient exists and has content (" .. #source .. " chars)")
        end
    end

    print("")
    print("=== Summary ===")

    if allValid then
        print("✓✓✓ ALL CHECKS PASSED! ✓✓✓")
        print("Your plugin structure is correct and ready to publish.")
        return true
    else
        warn("✗✗✗ STRUCTURE HAS ERRORS ✗✗✗")
        warn("Fix the errors above before publishing.")
        return false
    end
end

-- Run the verification
local success, result = pcall(verifyStructure)

if not success then
    warn("Script failed with error: " .. tostring(result))
end
