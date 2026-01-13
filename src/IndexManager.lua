--[[
    IndexManager.lua
    Handles local script scanning only
]]

local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)

local IndexManager = {}

--[[
    Extract clean code (for hash calculation or other purposes)
    @param source string - Full script source
    @return string - Clean code with normalized line endings
]]
function IndexManager.getCleanCode(source)
	-- Normalize line endings
	return Utils.normalizeLineEndings(source)
end

--[[
    Scan all script locations for scripts
    @return table - {scripts: table, totalCount: number, breakdown: table}
]]
function IndexManager.scanScripts()
	local scripts = {}
	local breakdown = {}

	for _, locationName in ipairs(Constants.SCAN_LOCATIONS) do
		local location = game:GetService(locationName)
		breakdown[locationName] = 0

		for _, descendant in ipairs(location:GetDescendants()) do
			if descendant:IsA("LuaSourceContainer") then
				-- Skip the manifest itself
				if descendant.Name == "LuxManifest" then
					continue
				end

				local source = descendant.Source

				-- Skip empty scripts
				if Utils.trim(source) ~= "" then
					local scriptData = {
						instance = descendant,
						name = descendant.Name,
						className = descendant.ClassName,
						path = Utils.getPath(descendant),
						lineCount = Utils.countLines(source)
					}

					table.insert(scripts, scriptData)
					breakdown[locationName] = breakdown[locationName] + 1
				end
			end
		end
	end

	return {
		scripts = scripts,
		totalCount = #scripts,
		breakdown = breakdown
	}
end

--[[
    Get a summary of scripts (for large projects)
    @return table - {totalScripts: number, byLocation: table}
]]
function IndexManager.getScriptSummary()
	local scanResult = IndexManager.scanScripts()
	local summary = {}

	-- Group by location
	for _, scriptData in ipairs(scanResult.scripts) do
		local location = scriptData.path:match("^([^.]+)")
		if not summary[location] then
			summary[location] = { count = 0, scripts = {} }
		end
		summary[location].count = summary[location].count + 1
		table.insert(summary[location].scripts, {
			name = scriptData.name,
			path = scriptData.path,
			lines = scriptData.lineCount
		})
	end

	return {
		totalScripts = scanResult.totalCount,
		byLocation = summary
	}
end

return IndexManager
