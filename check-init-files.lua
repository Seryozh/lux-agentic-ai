--[[
    Quick diagnostic: Check if init ModuleScripts exist in folders

    Run this in Command Bar in Roblox Studio:
]]

local lux = game.ServerStorage.Lux
local src = lux.src

print("=== Checking init files ===")

local folders = {"Context", "Coordination", "Core", "Memory", "Planning", "Safety", "Shared", "Tools", "UI"}

for _, folderName in ipairs(folders) do
    local folder = src:FindFirstChild(folderName)
    if folder then
        local init = folder:FindFirstChild("init")
        if init then
            if init:IsA("ModuleScript") then
                print(string.format("✓ %s has init ModuleScript (%d chars)", folderName, #init.Source))
            else
                warn(string.format("✗ %s has 'init' but it's a %s, not ModuleScript!", folderName, init.ClassName))
            end
        else
            warn(string.format("✗ %s MISSING init!", folderName))
            print("  Children:")
            for _, child in ipairs(folder:GetChildren()) do
                print(string.format("    - %s (%s)", child.Name, child.ClassName))
            end
        end
    else
        warn(string.format("✗ Folder '%s' doesn't exist!", folderName))
    end
end

print("=== Done ===")
