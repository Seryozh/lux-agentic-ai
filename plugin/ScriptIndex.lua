--[[
    ScriptIndex: Maintains a searchable index of all scripts in the game.

    Used by the search_project() tool to quickly find scripts without
    needing to traverse the entire game tree.

    Index format:
    {
        ["HealPlayer"] = "game.ServerScriptService.Combat.HealPlayer",
        ["DamageHandler"] = "game.ServerScriptService.Combat.DamageHandler",
        ["JumpBoost"] = "game.StarterPlayer.StarterCharacterScripts.JumpBoost"
    }
]]

local ScriptIndex = {}

local INDEX = {}  -- script_name -> full_path mapping

-- Containers to scan for scripts
local CONTAINERS = {
	"Workspace",
	"ServerStorage",
	"ServerScriptService",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"StarterPlayer",
	"StarterGui",
	"StarterPack",
}

-- Skip the plugin's own scripts
local IGNORED_NAMES = {
	Luxembourg = true,
}

local function scanForScripts(parent, basePath)
	for _, child in ipairs(parent:GetChildren()) do
		if IGNORED_NAMES[child.Name] then
			continue
		end

		local fullPath = basePath .. "." .. child.Name

		-- Index scripts
		if child:IsA("LuaSourceContainer") then
			INDEX[child.Name] = fullPath
		end

		-- Recurse into children
		if #child:GetChildren() > 0 then
			scanForScripts(child, fullPath)
		end
	end
end

function ScriptIndex.build()
	INDEX = {}  -- Clear existing index

	for _, containerName in ipairs(CONTAINERS) do
		local container = game:FindFirstChild(containerName)
		if container then
			scanForScripts(container, "game." .. containerName)
		end
	end

	return INDEX
end

function ScriptIndex.search(query)
	-- Normalize query (lowercase, trim)
	query = query:lower():gsub("^%s*(.-)%s*$", "%1")

	local results = {}

	-- Search strategy:
	-- 1. Exact match (case-insensitive)
	-- 2. Contains match
	-- 3. Fuzzy match (all query chars present in order)

	for scriptName, fullPath in pairs(INDEX) do
		local lowerName = scriptName:lower()

		-- Exact match
		if lowerName == query then
			table.insert(results, { name = scriptName, path = fullPath, score = 100 })
		-- Contains match
		elseif lowerName:find(query, 1, true) then
			table.insert(results, { name = scriptName, path = fullPath, score = 50 })
		-- Fuzzy match (all chars present in order)
		else
			local fuzzy = true
			local pos = 1
			for i = 1, #query do
				local char = query:sub(i, i)
				pos = lowerName:find(char, pos, true)
				if not pos then
					fuzzy = false
					break
				end
				pos = pos + 1
			end
			if fuzzy then
				table.insert(results, { name = scriptName, path = fullPath, score = 25 })
			end
		end
	end

	-- Sort by score (highest first)
	table.sort(results, function(a, b)
		return a.score > b.score
	end)

	return results
end

function ScriptIndex.get(scriptName)
	return INDEX[scriptName]
end

function ScriptIndex.getAll()
	return INDEX
end

return ScriptIndex
