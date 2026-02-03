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
