--[[
    ScriptReader: Reads script content from the game when the agent asks for it.

    Handles three request types:
    - get_metadata: Returns a short description of what a script does
    - get_full_script: Returns the complete source code
    - list_children: Returns children of a specific path (lazy loading)

    For metadata, we generate a simple summary from the script's source.
    In the future this could be cached or use attributes.
]]

local ScriptReader = {}
local ProjectMap = require(script.Parent.ProjectMap)
local ScriptIndex = require(script.Parent.ScriptIndex)

-- Find a script by name or path (e.g. "SetNightTime" or "ServerScriptService.SetNightTime")
local function findScript(name)
	-- Strip .lua extension if present
	name = name:gsub("%.lua$", "")

	-- Try as a path first (e.g. "game.ServerScriptService.SetNightTime" or "ServerScriptService.SetNightTime")
	local pathName = name:gsub("^game%.", "")
	local current = game
	local isPath = pathName:find("%.")
	if isPath then
		for part in pathName:gmatch("[^%.]+") do
			local child = current:FindFirstChild(part)
			if child then
				current = child
			else
				current = nil
				break
			end
		end
		if current and current:IsA("LuaSourceContainer") then
			return current
		end
	end

	-- Fall back to searching by just the last part of the name
	local simpleName = name:match("[^%.]+$") or name

	local function searchIn(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name == simpleName and child:IsA("LuaSourceContainer") then
				return child
			end
			local found = searchIn(child)
			if found then return found end
		end
		return nil
	end

	return searchIn(game)
end

-- Generate a basic metadata summary from source code
local function generateMetadata(scriptObj)
	local source = scriptObj.Source
	local lines = {}
	for line in source:gmatch("[^\n]+") do
		table.insert(lines, line)
	end

	local lineCount = #lines
	local scriptType = scriptObj.ClassName
	local parent = scriptObj.Parent and scriptObj.Parent:GetFullName() or "unknown"

	-- Find require statements (dependencies)
	local requires = {}
	for _, line in ipairs(lines) do
		local req = line:match('require%(.-"(.-)"%)')
			or line:match("require%(.-'(.-)'%)")
			or line:match("require%((.-)%)")
		if req then
			table.insert(requires, req)
		end
	end

	-- First few meaningful lines (skip comments and blank lines)
	local preview = {}
	for _, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed ~= "" and not trimmed:match("^%-%-") then
			table.insert(preview, trimmed)
			if #preview >= 5 then break end
		end
	end

	local summary = string.format(
		"%s in %s. %d lines. Dependencies: %s. Preview: %s",
		scriptType,
		parent,
		lineCount,
		#requires > 0 and table.concat(requires, ", ") or "none",
		table.concat(preview, " | ")
	)

	return summary
end

function ScriptReader.handleRequest(requestType, target)
	-- LAZY LOADING: Handle list_children separately (doesn't need script lookup)
	if requestType == "list_children" then
		local result = ProjectMap.listChildren(target)
		return { children = result }
	end

	-- SEMANTIC SEARCH: Handle search_project separately
	if requestType == "search_project" then
		local results = ScriptIndex.search(target)
		if #results == 0 then
			return { results = "No scripts found matching: " .. target }
		end

		local lines = {}
		for i, result in ipairs(results) do
			table.insert(lines, result.name .. " -> " .. result.path)
			if i >= 10 then  -- Limit to top 10 results
				break
			end
		end

		return { results = table.concat(lines, "\n") }
	end

	-- Original script-based requests
	local scriptObj = findScript(target)
	if not scriptObj then
		return { error = "Script not found: " .. target }
	end

	if requestType == "get_metadata" then
		return { metadata = generateMetadata(scriptObj) }
	elseif requestType == "get_full_script" then
		local source = scriptObj.Source
		-- Compute hash for verification (simple hash: length + first/last chars)
		local hash = #source .. source:sub(1, math.min(10, #source)) .. source:sub(-math.min(10, #source))
		return {
			source = source,
			hash = hash,
			path = scriptObj:GetFullName()
		}
	else
		return { error = "Unknown request type: " .. requestType }
	end
end

return ScriptReader
