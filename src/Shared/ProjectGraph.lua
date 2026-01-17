--[[
    ProjectGraph.lua
    Structural analyst for the codebase.
    Maps out script dependencies and network interactions to provide AI with architectural context.
]]

local RunService = game:GetService("RunService")
local IndexManager = require(script.Parent.IndexManager)
local Utils = require(script.Parent.Utils)
local Constants = require(script.Parent.Constants)

local ProjectGraph = {}

--============================================================
-- STATE
--============================================================
local _dependencies = {} -- path -> { targetPath1, targetPath2, ... }
local _dependents = {}   -- path -> { dependentPath1, dependentPath2, ... }
local _hubs = {}         -- array of { path, count } sorted by count
local _isScanning = false

--============================================================
-- INTERNAL PARSING
--============================================================

--- Parse source code to find requires and network calls
--- @param source string
--- @return table dependencies
local function parseSource(source)
	local deps = {}
	
	-- 1. Extract require() paths
	-- Matches: require(game.ReplicatedStorage.Module) or require(script.Parent.Module)
	-- We look for common patterns. Note: This is a simple regex approach.
	for path in source:gmatch("require%s*%(([%w%.%:]+)%)") do
		table.insert(deps, path)
	end
    
    -- Also match string-based requires if they exist in the project style
    -- for path in source:gmatch("require%s*%(['\"]([%w%.%_%/]+)['\"]%)") do
	-- 	table.insert(deps, path)
	-- end

	-- 2. Extract network interactions
	-- Matches: :FireServer, :FireClient, :InvokeServer, :InvokeClient
	for call in source:gmatch(":(F%w+Server)") do
		table.insert(deps, "Network." .. call)
	end
	for call in source:gmatch(":(F%w+Client)") do
		table.insert(deps, "Network." .. call)
	end

	return deps
end

--============================================================
-- CORE METHODS
--============================================================

--- Re-calculate the dependents map and hubs from the dependencies map
local function updateInvertedIndex()
	local newDependents = {}
	
	for sourcePath, targetPaths in pairs(_dependencies) do
		for _, targetPath in ipairs(targetPaths) do
			if not newDependents[targetPath] then
				newDependents[targetPath] = {}
			end
			table.insert(newDependents[targetPath], sourcePath)
		end
	end
	
	_dependents = newDependents
	
	-- Calculate Hubs
	local hubList = {}
	for path, dependentList in pairs(_dependents) do
		-- Only hub-ify modules/scripts, not "Network" tags
		if not path:find("^Network%.") then
			table.insert(hubList, {
				path = path,
				count = #dependentList
			})
		end
	end
	
	table.sort(hubList, function(a, b)
		return a.count > b.count
	end)
	
	_hubs = hubList
end

--- Full scan of all scripts in the project
function ProjectGraph.rebuildAsync()
	if _isScanning then return end
	_isScanning = true
	
	if Constants.DEBUG then
		print("[ProjectGraph] Starting full rebuild...")
	end
	
	local scanResult = IndexManager.scanScriptsAsync()
	local newDeps = {}
	local processedCount = 0
	local startTime = tick()
	
	for _, item in ipairs(scanResult.items) do
		if item.type == "script" then
			local script = item.instance
			if script and script:IsA("LuaSourceContainer") then
				local success, source = pcall(function() return script.Source end)
				if success and source then
					newDeps[item.path] = parseSource(source)
				end
			end
			
			processedCount = processedCount + 1
			
			-- Yield every 50 scripts or 10ms
			if processedCount % 50 == 0 or (tick() - startTime) > 0.01 then
				task.wait()
				startTime = tick()
			end
		end
	end
	
	_dependencies = newDeps
	updateInvertedIndex()
	
	_isScanning = false
	if Constants.DEBUG then
		print(string.format("[ProjectGraph] Rebuild complete. Found %d hubs.", #_hubs))
	end
end

--- Incremental update for a single script
--- @param path string
function ProjectGraph.updateScript(path)
	local script = Utils.getScriptByPath(path)
	if script and script:IsA("LuaSourceContainer") then
		local success, source = pcall(function() return script.Source end)
		if success and source then
			_dependencies[path] = parseSource(source)
			updateInvertedIndex()
		end
	else
		-- Script was deleted
		_dependencies[path] = nil
		updateInvertedIndex()
	end
end

--- Get architectural overview for prompt
--- @return string
function ProjectGraph.getArchitectureOverview()
	if #_hubs == 0 then
		return "PROJECT ARCHITECTURE: Initializing map..."
	end
	
	local lines = { "PROJECT ARCHITECTURE (Core Hubs):" }
	
	-- Show top 8 hubs
	for i = 1, math.min(8, #_hubs) do
		local hub = _hubs[i]
		-- Extract just the name for brevity if possible, or keep short path
		local name = hub.path:match("([^%.]+)$") or hub.path
		table.insert(lines, string.format("- %s (Used by %d)", name, hub.count))
	end
	
	return table.concat(lines, "\n")
end

--- Get neighbors for a specific script
--- @param scriptPath string
--- @return table { dependencies: array, dependents: array }
function ProjectGraph.getDependenciesFor(scriptPath)
	return {
		dependencies = _dependencies[scriptPath] or {},
		dependents = _dependents[scriptPath] or {}
	}
end

function ProjectGraph.isScanning()
	return _isScanning
end

return ProjectGraph
