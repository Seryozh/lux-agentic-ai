--[[
    ProjectMap: Scans the game tree and builds a text representation.

    This is Level 1 of the three-level exploration. Just names, types,
    and hierarchy. No script content, no metadata, no analysis.

    Output looks like:
    Game
      Workspace
        SpawnLocation (SpawnLocation)
        Baseplate (Part)
      ServerStorage
        Humanoid (ModuleScript)
]]

local ProjectMap = {}

-- Types worth including in the map (things the AI needs to see)
local RELEVANT_TYPES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	BindableEvent = true,
	BindableFunction = true,
	Model = true,
	Part = true,
	MeshPart = true,
	SpawnLocation = true,
	ScreenGui = true,
	Frame = true,
	TextButton = true,
	TextLabel = true,
	ImageButton = true,
	ImageLabel = true,
	ScrollingFrame = true,
	Folder = true,
}

-- Containers we always scan into (top-level game services)
local CONTAINERS = {
	"Workspace",
	"ServerStorage",
	"ServerScriptService",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"StarterPlayer",
	"StarterGui",
	"StarterPack",
	"Lighting",
	"SoundService",
}

-- Skip the plugin's own scripts
local IGNORED_NAMES = {
	Luxembourg = true,
}

local function scanInstance(instance, indent, lines)
	if IGNORED_NAMES[instance.Name] then return end

	local typeName = instance.ClassName
	local displayName = instance.Name

	-- Show type in parentheses if it's not obvious from the name
	if displayName ~= typeName then
		displayName = displayName .. " (" .. typeName .. ")"
	end

	table.insert(lines, string.rep("  ", indent) .. displayName)

	-- Recurse into children
	for _, child in ipairs(instance:GetChildren()) do
		-- Include if it's a relevant type OR has children worth scanning
		if RELEVANT_TYPES[child.ClassName] or #child:GetChildren() > 0 then
			scanInstance(child, indent + 1, lines)
		end
	end
end

-- LAZY LOADING: Build only top-level view
function ProjectMap.buildLazy()
	local lines = { "Game" }

	for _, containerName in ipairs(CONTAINERS) do
		local container = game:FindFirstChild(containerName)
		if container then
			local childCount = #container:GetChildren()
			local status = childCount > 0 and (" [" .. childCount .. " children]") or " [empty]"
			table.insert(lines, "  " .. containerName .. status)
		end
	end

	return table.concat(lines, "\n")
end

-- Get children of a specific path (for list_children tool)
function ProjectMap.listChildren(targetPath)
	-- Parse path like "game.Workspace" or "game.ServerScriptService.CombatSystem"
	local parts = {}
	for part in targetPath:gmatch("[^.]+") do
		table.insert(parts, part)
	end

	-- Navigate to target
	local current = game
	for i = 2, #parts do  -- Skip "game"
		current = current:FindFirstChild(parts[i])
		if not current then
			return "Error: Path not found: " .. targetPath
		end
	end

	-- Build children list
	local lines = {}
	for _, child in ipairs(current:GetChildren()) do
		if not IGNORED_NAMES[child.Name] then
			local typeName = child.ClassName
			local displayName = child.Name

			if displayName ~= typeName then
				displayName = displayName .. " (" .. typeName .. ")"
			end

			local childCount = #child:GetChildren()
			if childCount > 0 then
				displayName = displayName .. " [" .. childCount .. " children]"
			end

			table.insert(lines, "  " .. displayName)
		end
	end

	if #lines == 0 then
		return targetPath .. " [empty]"
	end

	return targetPath .. ":\n" .. table.concat(lines, "\n")
end

-- Legacy full scan (kept for backwards compatibility)
function ProjectMap.build()
	local lines = { "Game" }

	for _, containerName in ipairs(CONTAINERS) do
		local container = game:FindFirstChild(containerName)
		if container and #container:GetChildren() > 0 then
			scanInstance(container, 1, lines)
		end
	end

	return table.concat(lines, "\n")
end

return ProjectMap
