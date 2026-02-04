--[[
    ActionExecutor: Executes any action the agent wants to perform in Studio.

    Supports:
    - set_property: Change properties on any instance
    - create_instance: Create any Roblox instance
    - delete_instance: Remove any instance
    - move_instance: Reparent an instance
    - clone_instance: Clone an instance to a new parent
    - create_script: Create a new script with source code
    - modify_script: Overwrite a script's source
    - delete_script: Remove a script
]]

local ActionExecutor = {}

-- Resolve a path like "game.Workspace.Enemy.EnemyAI" to an actual instance
local function resolvePath(path)
	local current = game
	for part in path:gmatch("[^%.]+") do
		if part ~= "game" then
			local child = current:FindFirstChild(part)
			if not child then
				return nil, "Could not find '" .. part .. "' in " .. current:GetFullName()
			end
			current = child
		end
	end
	return current, nil
end

-- Like resolvePath but creates missing Folder containers along the way
local function resolveOrCreatePath(path)
	local current = game
	for part in path:gmatch("[^%.]+") do
		if part ~= "game" then
			local child = current:FindFirstChild(part)
			if not child then
				-- Try to create it as a Folder
				local success, newChild = pcall(function()
					local folder = Instance.new("Folder")
					folder.Name = part
					folder.Parent = current
					return folder
				end)
				if success then
					child = newChild
				else
					return nil, "Could not find or create '" .. part .. "' in " .. current:GetFullName()
				end
			end
			current = child
		end
	end
	return current, nil
end

-- Properties that expect specific types
local COLOR_PROPS = {
	Color = true, Color3 = true, BackgroundColor3 = true, TextColor3 = true,
	BorderColor3 = true, ImageColor3 = true, PlaceholderColor3 = true,
}
local UDIM2_PROPS = {
	Size = true, Position = true, CanvasSize = true, AnchorPoint = false,
}

-- Convert JSON property values to Roblox types
local function convertValue(key, value)
	if type(value) == "table" then
		if #value == 4 then
			-- UDim2: [xScale, xOffset, yScale, yOffset]
			return UDim2.new(value[1], value[2], value[3], value[4])
		elseif #value == 3 then
			if COLOR_PROPS[key] then
				return Color3.fromRGB(value[1], value[2], value[3])
			else
				return Vector3.new(value[1], value[2], value[3])
			end
		elseif #value == 2 then
			-- Could be Vector2 or UDim2 shorthand (just scales)
			if key == "AnchorPoint" then
				return Vector2.new(value[1], value[2])
			else
				-- Treat as UDim2 with scale only: [xScale, yScale]
				return UDim2.new(value[1], 0, value[2], 0)
			end
		end
	elseif type(value) == "string" then
		-- Check if it's an Enum value like "Enum.Material.Grass"
		if value:match("^Enum%.") then
			local success, result = pcall(function()
				local parts = {}
				for part in value:gmatch("[^%.]+") do
					table.insert(parts, part)
				end
				-- parts = {"Enum", "Material", "Grass"}
				return Enum[parts[2]][parts[3]]
			end)
			if success then return result end
		end
		-- Check if it's a BrickColor
		local success, bc = pcall(function() return BrickColor.new(value) end)
		if success and key == "BrickColor" then return bc end
	end
	return value
end

local function setProperties(instance, properties)
	local results = {}
	for key, value in pairs(properties) do
		local converted = convertValue(key, value)
		local success, err = pcall(function()
			instance[key] = converted
		end)
		if not success then
			table.insert(results, "  WARNING: Could not set " .. key .. ": " .. tostring(err))
		end
	end
	return results
end

-- ============================================================
-- Action handlers
-- ============================================================

local handlers = {}

function handlers.set_property(action)
	local instance, err = resolvePath(action.target)
	if not instance then return { "ERROR: " .. err } end

	local results = { "Set properties on " .. action.target }
	local propResults = setProperties(instance, action.properties)
	for _, r in ipairs(propResults) do table.insert(results, r) end
	return results
end

function handlers.create_instance(action)
	local parent, err = resolveOrCreatePath(action.target)
	if not parent then return { "ERROR: " .. err } end

	local success, instance = pcall(function()
		return Instance.new(action.class_name)
	end)
	if not success then return { "ERROR: Invalid class: " .. action.class_name } end

	instance.Name = action.name or action.class_name

	-- Set properties before parenting (avoids issues with some properties)
	if action.properties then
		setProperties(instance, action.properties)
	end

	instance.Parent = parent
	return { "Created " .. action.class_name .. " '" .. instance.Name .. "' in " .. action.target }
end

function handlers.delete_instance(action)
	local instance, err = resolvePath(action.target)
	if not instance then return { "ERROR: " .. err } end

	local name = instance:GetFullName()
	instance:Destroy()
	return { "Deleted " .. name }
end

function handlers.move_instance(action)
	local instance, err = resolvePath(action.target)
	if not instance then return { "ERROR: " .. err } end

	local newParent, err2 = resolvePath(action.new_parent)
	if not newParent then return { "ERROR: " .. err2 } end

	instance.Parent = newParent
	return { "Moved " .. action.target .. " to " .. action.new_parent }
end

function handlers.clone_instance(action)
	local instance, err = resolvePath(action.target)
	if not instance then return { "ERROR: " .. err } end

	local newParent, err2 = resolvePath(action.new_parent)
	if not newParent then return { "ERROR: " .. err2 } end

	local clone = instance:Clone()
	if action.name and action.name ~= "" then
		clone.Name = action.name
	end
	clone.Parent = newParent
	return { "Cloned " .. action.target .. " to " .. action.new_parent }
end

function handlers.create_script(action)
	local parent, err = resolveOrCreatePath(action.target)
	if not parent then return { "ERROR: " .. err } end

	local className = action.class_name
	if className ~= "Script" and className ~= "LocalScript" and className ~= "ModuleScript" then
		className = "Script"  -- default
	end

	local scriptObj = Instance.new(className)
	scriptObj.Name = action.name or "NewScript"
	scriptObj.Source = action.source or ""

	if action.properties then
		setProperties(scriptObj, action.properties)
	end

	scriptObj.Parent = parent
	return { "Created " .. className .. " '" .. scriptObj.Name .. "' in " .. action.target }
end

function handlers.modify_script(action)
	local instance, err = resolvePath(action.target)
	if not instance then return { "ERROR: " .. err } end

	if not instance:IsA("LuaSourceContainer") then
		return { "ERROR: " .. action.target .. " is not a script" }
	end

	-- HASH VERIFICATION: Check if script was modified since AI last saw it
	if action.original_hash then
		local HttpService = game:GetService("HttpService")
		local currentSource = instance.Source
		local currentHash = HttpService:GenerateGUID(false):sub(1, 8)  -- Simple hash substitute

		-- Better hash: Use string length + first/last chars as proxy
		local actualHash = #currentSource .. currentSource:sub(1, math.min(10, #currentSource)) .. currentSource:sub(-math.min(10, #currentSource))

		if actualHash ~= action.original_hash then
			return {
				"⚠️  WARNING: Script was modified since AI analyzed it!",
				"Current hash: " .. actualHash:sub(1, 20),
				"Expected hash: " .. action.original_hash:sub(1, 20),
				"SKIPPED modification to prevent data loss.",
				"Suggestion: Ask AI to re-analyze the script first."
			}
		end
	end

	instance.Source = action.source
	return { "✓ Modified " .. action.target }
end

function handlers.delete_script(action)
	return handlers.delete_instance(action)
end

-- ============================================================
-- Main execute function
-- ============================================================

function ActionExecutor.execute(actions)
	local allResults = {}

	for _, action in ipairs(actions) do
		local handler = handlers[action.type]
		if handler then
			local results = handler(action)
			for _, r in ipairs(results) do
				table.insert(allResults, r)
			end
		else
			table.insert(allResults, "ERROR: Unknown action type: " .. tostring(action.type))
		end
	end

	return allResults
end

-- Describe an action in human-readable form (for approval UI)
function ActionExecutor.describe(action)
	if action.type == "set_property" then
		local props = {}
		for k, v in pairs(action.properties or {}) do
			table.insert(props, k .. " = " .. tostring(v))
		end
		return "Set " .. action.target .. ": " .. table.concat(props, ", ")
	elseif action.type == "create_instance" then
		return "Create " .. (action.class_name or "?") .. " '" .. (action.name or "?") .. "' in " .. action.target
	elseif action.type == "delete_instance" or action.type == "delete_script" then
		return "Delete " .. action.target
	elseif action.type == "move_instance" then
		return "Move " .. action.target .. " to " .. (action.new_parent or "?")
	elseif action.type == "clone_instance" then
		return "Clone " .. action.target .. " to " .. (action.new_parent or "?")
	elseif action.type == "create_script" then
		return "Create " .. (action.class_name or "Script") .. " '" .. (action.name or "?") .. "' in " .. action.target
	elseif action.type == "modify_script" then
		return "Modify script " .. action.target
	else
		return "Unknown: " .. tostring(action.type)
	end
end

return ActionExecutor
