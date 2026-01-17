-- IndexManager.lua (Upgraded)

local RunService = game:GetService("RunService")
local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)

local IndexManager = {}

-- Cache the index so we don't have to rebuild it constantly
local _indexCache = nil
local _isDirty = true -- "Dirty" flag means we need to rescan

--[[
    Safe Scan: Runs without freezing the main thread.
    Uses 'heartbeat' yielding to keep Studio responsive.
]]
function IndexManager.scanScriptsAsync()
    local scripts = {}
    local breakdown = {}
    local totalProcessed = 0
    
    local startTime = tick()

    for _, locationName in ipairs(Constants.SCAN_LOCATIONS) do
        local location = game:GetService(locationName)
        if not location then continue end
        
        breakdown[locationName] = 0
        
        local descendants = location:GetDescendants() 

        for i, descendant in ipairs(descendants) do
            -- YIELD CHECK: If we've spent more than 10ms this frame, pause.
            if i % 100 == 0 and (tick() - startTime) > 0.01 then
                task.wait()
                startTime = tick()
            end

            -- CATEGORY CHECK
            local isScript = descendant:IsA("LuaSourceContainer")
            local isRemote = descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") or descendant:IsA("BindableEvent") or descendant:IsA("BindableFunction")
            local isContainer = descendant:IsA("Folder") or descendant:IsA("Configuration") or descendant:IsA("Model")
            local isUI = descendant:IsA("ScreenGui") or descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui")

            if isScript or isRemote or isContainer or isUI then
                if descendant.Name == "LuxManifest" then continue end
                
                local scriptData = {
                    instance = descendant,
                    name = descendant.Name,
                    className = descendant.ClassName,
                    path = Utils.getPath(descendant),
                    type = isScript and "script" or (isRemote and "remote" or (isUI and "ui" or "container"))
                }

                if isScript then
                    local success, source = pcall(function() return descendant.Source end)
                    if success then
                        scriptData.lineCount = Utils.countLines(source or "")
                    end
                end

                table.insert(scripts, scriptData)
                breakdown[locationName] = breakdown[locationName] + 1
            end
        end
    end

    -- Update Cache
    _indexCache = {
        items = scripts,
        totalCount = #scripts,
        breakdown = breakdown
    }
    _isDirty = false
    
    return _indexCache
end

--[[
    Get the summary. If cache is valid, return immediately.
    This makes the UI feel "Instant" on subsequent calls.
]]
function IndexManager.getScriptSummary()
    if not _isDirty and _indexCache then
        return IndexManager.formatSummary(_indexCache)
    end
    
    -- If dirty, we must scan (warning: this might yield now!)
    local result = IndexManager.scanScriptsAsync()
    return IndexManager.formatSummary(result)
end

function IndexManager.formatSummary(scanResult)
    local summary = {}
    for _, data in ipairs(scanResult.items) do
        local location = data.path:match("^([^.]+)") or "Unknown"
        if not summary[location] then
            summary[location] = { 
                count = 0, 
                scripts = {},
                remotes = {},
                containers = {},
                ui = {}
            }
        end
        
        summary[location].count = summary[location].count + 1
        
        local entry = {
            name = data.name,
            path = data.path,
            className = data.className
        }
        
        if data.type == "script" then
            entry.lines = data.lineCount
            table.insert(summary[location].scripts, entry)
        elseif data.type == "remote" then
            table.insert(summary[location].remotes, entry)
        elseif data.type == "ui" then
            table.insert(summary[location].ui, entry)
        else
            table.insert(summary[location].containers, entry)
        end
    end
    
    return {
        totalItems = scanResult.totalCount,
        byLocation = summary
    }
end

-- Mark index as dirty if you know something changed (call this from WriteTools)
function IndexManager.invalidate()
    _isDirty = true
end

return IndexManager
