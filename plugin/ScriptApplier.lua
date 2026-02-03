--[[
    ScriptApplier: Applies script changes from the agent's response to the game.

    Handles three actions:
    - modify: Overwrites an existing script's source
    - create: Creates a new script at a specified parent
    - delete: Removes a script
]]

local ScriptApplier = {}

local function findScript(name)
	name = name:gsub("%.lua$", "")

	local function searchIn(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name == name and child:IsA("LuaSourceContainer") then
				return child
			end
			local found = searchIn(child)
			if found then return found end
		end
		return nil
	end

	return searchIn(game)
end

local function findParent(parentPath)
	-- parentPath like "game.ServerScriptService" or "game.Workspace.Enemy"
	local current = game
	for part in parentPath:gmatch("[^%.]+") do
		if part ~= "game" then
			local child = current:FindFirstChild(part)
			if not child then
				return nil
			end
			current = child
		end
	end
	return current
end

local SCRIPT_CLASS = {
	Script = "Script",
	LocalScript = "LocalScript",
	ModuleScript = "ModuleScript",
}

function ScriptApplier.apply(scriptChanges)
	local results = {}

	for _, change in ipairs(scriptChanges) do
		if change.action == "modify" then
			local scriptObj = findScript(change.name)
			if scriptObj then
				scriptObj.Source = change.source
				table.insert(results, "Modified: " .. change.name)
			else
				table.insert(results, "ERROR: Could not find " .. change.name)
			end

		elseif change.action == "create" then
			local parent = findParent(change.parent)
			if parent then
				-- Default to Script if we can't determine type
				local newScript = Instance.new("Script")
				newScript.Name = change.name
				newScript.Source = change.source
				newScript.Parent = parent
				table.insert(results, "Created: " .. change.name .. " in " .. change.parent)
			else
				table.insert(results, "ERROR: Parent not found: " .. change.parent)
			end

		elseif change.action == "delete" then
			local scriptObj = findScript(change.name)
			if scriptObj then
				scriptObj:Destroy()
				table.insert(results, "Deleted: " .. change.name)
			else
				table.insert(results, "ERROR: Could not find " .. change.name)
			end
		end
	end

	return results
end

return ScriptApplier
