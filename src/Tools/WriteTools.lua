--[[
	WriteTools.lua
	Write/modify tool implementations that require user approval

	Handles:
	- Script patching and editing
	- Script creation
	- Instance creation and property modification
	- Instance deletion
	- All operations that modify game state

	All write operations are queued to ApprovalQueue for user confirmation.

	Creator Store Compliant - No dynamic code execution
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Utils = require(script.Parent.Parent.Shared.Utils)
local IndexManager = require(script.Parent.Parent.Shared.IndexManager)
local ProjectGraph = require(script.Parent.Parent.Shared.ProjectGraph)
local ContextSelector = require(script.Parent.Parent.Context.ContextSelector)
local ApprovalQueue = require(script.Parent.ApprovalQueue)

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local WriteTools = {}

--============================================================
-- HELPER FUNCTIONS
--============================================================

--- Get instance by path (e.g., "ServerScriptService.PlayerManager")
--- @param path string
--- @return Instance|nil
local function getInstanceByPath(path)
	return Utils.getScriptByPath(path)
end

--- Check if a path will exist after pending operations are applied
--- This allows queueing dependent operations (e.g., create Frame inside a ScreenGui that's also queued)
--- @param path string
--- @return boolean
local function willPathExist(path)
	-- First check if it exists now
	if Utils.getScriptByPath(path) then
		return true
	end

	-- Check if any pending OR recently approved operation will create this path
	-- (approved operations in the current batch may not yet be findable via getInstanceByPath)
	local ApprovalQueue = require(script.Parent.ApprovalQueue)
	local pendingOps = ApprovalQueue.getAll()

	for _, op in ipairs(pendingOps) do
		if op.status == "pending" or op.status == "approved" then
			if op.type == "create_instance" then
				local willCreatePath = op.data.parent .. "." .. op.data.name
				if willCreatePath == path then
					return true
				end
			elseif op.type == "create_script" then
				if op.data.path == path then
					return true
				end
			end
		end
	end

	return false
end

--============================================================
-- PROPERTY TYPE HINTS (CLASS-AWARE)
-- This system understands that the same property name can mean
-- different types on different classes (e.g., Size on Part vs Frame)
--============================================================

-- GUI classes that use UDim2 for Size/Position (not Vector3)
local GUI_CLASSES = {
	-- Core GUI containers
	Frame = true, ScrollingFrame = true, ViewportFrame = true,
	CanvasGroup = true, VideoFrame = true,
	-- Text elements
	TextLabel = true, TextButton = true, TextBox = true,
	-- Image elements
	ImageLabel = true, ImageButton = true,
	-- Screen containers (these also use UDim2 for child positioning)
	ScreenGui = true, SurfaceGui = true, BillboardGui = true,
	-- Layout modifiers (some use UDim2)
	UIListLayout = true, UIGridLayout = true, UITableLayout = true, UIPageLayout = true,
}

-- Properties that are UDim2 on GUI classes (4 numbers: scaleX, offsetX, scaleY, offsetY)
local UDIM2_PROPERTIES_ON_GUI = {
	Size = true, Position = true, CanvasSize = true,
}

-- Properties that are ALWAYS UDim2 regardless of class
local UDIM2_PROPERTIES_ALWAYS = {
	CanvasSize = true, -- ScrollingFrame specific
}

-- Properties that are ALWAYS UDim (2 numbers: scale, offset)
local UDIM_PROPERTIES = {
	CornerRadius = true, -- UICorner
	Padding = true, -- UIListLayout, UIGridLayout
	PaddingBottom = true, PaddingLeft = true, PaddingRight = true, PaddingTop = true, -- UIPadding
	CellPadding = true, CellSize = true, -- UIGridLayout (these are UDim2 actually)
}

-- Properties that should ALWAYS be treated as strings (never Color/BrickColor)
local STRING_PROPERTIES = {
	Text = true, PlaceholderText = true, Name = true, ContentText = true,
	Title = true, Message = true, GroupName = true, ToolTip = true,
	Source = true, LinkedSource = true, Value = true, -- StringValue.Value
	Image = true, -- ImageLabel/ImageButton asset string
	SoundId = true, AnimationId = true, MeshId = true, TextureId = true, -- Asset IDs
}

-- Properties that should ALWAYS be treated as Vector3 (for non-GUI classes)
local VECTOR3_PROPERTIES = {
	-- Note: Size and Position are NOT here - they're handled by class-aware logic
	Velocity = true, RotVelocity = true,
	AssemblyLinearVelocity = true, AssemblyAngularVelocity = true,
	ExtentsOffset = true, StudsOffset = true, WorldPivot = true,
	PivotOffset = true, Orientation = true,
}

-- Properties that are Vector3 ONLY on non-GUI classes
local VECTOR3_PROPERTIES_ON_BASEPART = {
	Size = true, Position = true,
}

-- Properties that are Enum types (maps property name to Enum type)
local ENUM_PROPERTIES = {
	Font = "Font",
	FontFace = "Font", -- Legacy compat
	Material = "Material",
	Shape = "PartType",
	BorderMode = "BorderMode",
	ScaleType = "ScaleType",
	SizeConstraint = "SizeConstraint",
	TextXAlignment = "TextXAlignment",
	TextYAlignment = "TextYAlignment",
	HorizontalAlignment = "HorizontalAlignment",
	VerticalAlignment = "VerticalAlignment",
	FillDirection = "FillDirection",
	SortOrder = "SortOrder",
	ScrollingDirection = "ScrollingDirection",
	AutomaticSize = "AutomaticSize",
	ZIndexBehavior = "ZIndexBehavior",
	SelectionBehavior = "SelectionBehavior",
	TextTruncate = "TextTruncate",
	EasingStyle = "EasingStyle",
	EasingDirection = "EasingDirection",
	SurfaceType = "SurfaceType",
	ApplyStrokeMode = "ApplyStrokeMode", -- UIStroke
	LineJoinMode = "LineJoinMode", -- UIStroke
}

-- Properties that should use BrickColor (the ONLY properties that should)
local BRICKCOLOR_PROPERTIES = {
	BrickColor = true
}

-- Properties that are NumberRange (2 numbers: min, max OR 1 number: both)
local NUMBERRANGE_PROPERTIES = {
	Lifetime = true, Speed = true, RotSpeed = true, Rate = true,
	Drag = true, VelocitySpread = true,
}

-- Properties that are Vector2
local VECTOR2_PROPERTIES = {
	AnchorPoint = true,
	ImageRectOffset = true, ImageRectSize = true, -- ImageLabel/ImageButton
	StudsPerTileU = true, StudsPerTileV = true, -- Texture
	CanvasPosition = true, -- ScrollingFrame (this is Vector2, not UDim2)
}

--- Parse property value from string to correct type
--- CLASS-AWARE: Uses className to determine correct property types
--- @param propertyName string
--- @param value any
--- @param className string|nil - Optional class name for context-aware parsing
--- @return any
local function parsePropertyValue(propertyName, value, className)
	if type(value) ~= "string" then
		return value
	end

	-- Normalize value: strip whitespace for numeric parsing
	-- This allows "0, 10, 0, 50" to work the same as "0,10,0,50"
	local cleanValue = value:gsub("%s", "")

	-- Determine if this is a GUI class (uses UDim2 for Size/Position)
	local isGuiClass = className and GUI_CLASSES[className]

	-- Debug logging for property parsing
	if Constants.DEBUG then
		print(string.format("[Lux Parse] Property: %s, Value: %s, Class: %s, IsGUI: %s",
			propertyName, value:sub(1,30), className or "nil", tostring(isGuiClass)))
	end

	-- =====================================================
	-- PRIORITY 1: String properties - return as-is
	-- =====================================================
	if STRING_PROPERTIES[propertyName] then
		return value
	end

	-- =====================================================
	-- PRIORITY 2: Enum properties
	-- =====================================================
	local enumType = ENUM_PROPERTIES[propertyName]
	if enumType then
		-- Strip "Enum.TypeName." prefix if present (e.g., "Enum.Material.Neon" -> "Neon")
		local enumValue = value:match("^Enum%.%w+%.(.+)$") or value

		local success, result = pcall(function()
			return Enum[enumType][enumValue]
		end)
		if success and result then
			return result
		end
		return value
	end

	-- =====================================================
	-- PRIORITY 3: CLASS-AWARE Size/Position handling
	-- This is the KEY fix - Size/Position mean different things on different classes!
	-- =====================================================
	if UDIM2_PROPERTIES_ON_GUI[propertyName] then
		if isGuiClass then
			-- GUI class: Parse as UDim2 (4 numbers: scaleX, offsetX, scaleY, offsetY)
			local sx, ox, sy, oy = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
			if sx and ox and sy and oy then
				return UDim2.new(tonumber(sx), tonumber(ox), tonumber(sy), tonumber(oy))
			end
			-- If 4-number format fails, return as-is and let Roblox error clearly
			warn(string.format("[Lux] UDim2 expected for %s.%s but got: %s (format: scaleX,offsetX,scaleY,offsetY)",
				className, propertyName, value))
			return value
		else
			-- Non-GUI class (BasePart, Model, etc.): Parse as Vector3
			local x, y, z = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
			if x and y and z then
				return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
			end
			return value
		end
	end

	-- =====================================================
	-- PRIORITY 4: UDim properties (CornerRadius, Padding, etc.)
	-- =====================================================
	if UDIM_PROPERTIES[propertyName] then
		-- UDim: 2 numbers (scale, offset)
		local scale, offset = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		if scale and offset then
			return UDim.new(tonumber(scale), tonumber(offset))
		end
		-- Single number = offset only (common for CornerRadius)
		if tonumber(cleanValue) then
			return UDim.new(0, tonumber(cleanValue))
		end
		return value
	end

	-- =====================================================
	-- PRIORITY 5: Vector2 properties (AnchorPoint, ImageRectOffset, etc.)
	-- =====================================================
	if VECTOR2_PROPERTIES[propertyName] then
		local x, y = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		if x and y then
			return Vector2.new(tonumber(x), tonumber(y))
		end
		return value
	end

	-- =====================================================
	-- PRIORITY 6: Always-Vector3 properties (Velocity, Orientation, etc.)
	-- =====================================================
	if VECTOR3_PROPERTIES[propertyName] then
		local x, y, z = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		if x and y and z then
			return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
		end
		return value
	end

	-- =====================================================
	-- PRIORITY 7: CFrame property
	-- =====================================================
	if propertyName == "CFrame" then
		-- Try 3-component format (position only): "X,Y,Z"
		local x, y, z = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		if x and y and z then
			return CFrame.new(tonumber(x), tonumber(y), tonumber(z))
		end
		-- Try 12-component format
		local components = {}
		for num in cleanValue:gmatch("%-?%d+%.?%d*") do
			table.insert(components, tonumber(num))
		end
		if #components == 12 then
			return CFrame.new(
				components[1], components[2], components[3],
				components[4], components[5], components[6],
				components[7], components[8], components[9],
				components[10], components[11], components[12]
			)
		end
		return value
	end

	-- =====================================================
	-- PRIORITY 8: Color properties (ends with Color3 or Color)
	-- =====================================================
	if propertyName:match("Color3$") or propertyName:match("Color$") then
		-- Hex: "#RRGGBB" or "RRGGBB"
		local hex = value:match("^#?(%x%x%x%x%x%x)$")
		if hex then
			return Color3.fromHex(hex)
		end

		-- RGB: "R,G,B"
		local rStr, gStr, bStr = cleanValue:match("^(%d+%.?%d*),(%d+%.?%d*),(%d+%.?%d*)$")
		if rStr and gStr and bStr then
			local r, g, b = tonumber(rStr), tonumber(gStr), tonumber(bStr)
			if r > 1 or g > 1 or b > 1 then
				return Color3.fromRGB(r, g, b)
			else
				return Color3.new(r, g, b)
			end
		end
		return value
	end

	-- =====================================================
	-- PRIORITY 9: BrickColor properties
	-- =====================================================
	if BRICKCOLOR_PROPERTIES[propertyName] then
		local success, brickColor = pcall(function() return BrickColor.new(value) end)
		if success then
			return brickColor
		end
		return value
	end

	-- =====================================================
	-- PRIORITY 10: NumberRange properties (particle effects)
	-- =====================================================
	if NUMBERRANGE_PROPERTIES[propertyName] then
		-- Two numbers: "min,max"
		local minVal, maxVal = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		if minVal and maxVal then
			return NumberRange.new(tonumber(minVal), tonumber(maxVal))
		end
		-- Single number: both min and max
		if tonumber(cleanValue) then
			local n = tonumber(cleanValue)
			return NumberRange.new(n, n)
		end
		return value
	end

	-- =====================================================
	-- PRIORITY 11: Generic fallback based on number count
	-- =====================================================

	-- 4 numbers ? UDim2 (likely)
	if cleanValue:match("^%-?%d+%.?%d*,%-?%d+%.?%d*,%-?%d+%.?%d*,%-?%d+%.?%d*$") then
		local sx, ox, sy, oy = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		return UDim2.new(tonumber(sx), tonumber(ox), tonumber(sy), tonumber(oy))
	end

	-- 3 numbers ? Vector3 (likely)
	if cleanValue:match("^%-?%d+%.?%d*,%-?%d+%.?%d*,%-?%d+%.?%d*$") then
		local x, y, z = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
	end

	-- 2 numbers ? Vector2 (likely)
	if cleanValue:match("^%-?%d+%.?%d*,%-?%d+%.?%d*$") then
		local x, y = cleanValue:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		return Vector2.new(tonumber(x), tonumber(y))
	end

	-- =====================================================
	-- PRIORITY 12: Boolean
	-- =====================================================
	if value == "true" then return true end
	if value == "false" then return false end

	-- =====================================================
	-- PRIORITY 13: Number
	-- =====================================================
	if tonumber(value) then return tonumber(value) end

	-- =====================================================
	-- PRIORITY 14: Return as string (safe default)
	-- =====================================================
	return value
end

--- Count different lines between two strings
--- @param oldSource string
--- @param newSource string
--- @return number
local function countDifferentLines(oldSource, newSource)
	local oldLines = Utils.splitLines(oldSource)
	local newLines = Utils.splitLines(newSource)

	local changed = 0
	local maxLen = math.max(#oldLines, #newLines)

	for i = 1, maxLen do
		if oldLines[i] ~= newLines[i] then
			changed = changed + 1
		end
	end

	return changed
end

--============================================================
-- HELPER: Check if path will exist after pending operations
--============================================================

--- Check if a path will exist after pending operations are applied
--- This allows queueing dependent operations (e.g., create Frame inside a ScreenGui that's also queued)
--- @param path string
--- @param pendingOperations table
--- @return boolean
local function willPathExist(path, pendingOperations)
	-- First check if it exists now
	if getInstanceByPath(path) then
		return true
	end

	-- Check if any pending OR recently approved operation will create this path
	-- (approved operations in the current batch may not yet be findable via getInstanceByPath)
	for _, op in ipairs(pendingOperations) do
		if op.status == "pending" or op.status == "approved" then
			if op.type == "create_instance" then
				local willCreatePath = op.data.parent .. "." .. op.data.name
				if willCreatePath == path then
					return true
				end
			elseif op.type == "create_script" then
				if op.data.path == path then
					return true
				end
			end
		end
	end

	return false
end

--============================================================
-- WRITE OPERATION APPLIERS
--============================================================

--- Internal: Apply patch_script operation
--- @param data table
--- @return table result
function WriteTools.applyPatchScript(data)
	local script = getInstanceByPath(data.path)
	if not script or not script:IsA("LuaSourceContainer") then
		return {
			error = "Script not found: " .. data.path
		}
	end

	local source = script.Source
	local searchContent = data.search_content
	local replaceContent = data.replace_content

	-- 1. Normalization: Strip \r
	source = source:gsub("\r", "")
	searchContent = searchContent:gsub("\r", "")
	replaceContent = replaceContent:gsub("\r", "")

	local matchStart, matchEnd

	-- 2. Exact Match Attempt
	matchStart, matchEnd = source:find(searchContent, 1, true)

	-- 3. Fuzzy Match Fallback
	if not matchStart then
		local searchLines = Utils.splitLines(searchContent)
		local sourceLines = Utils.splitLines(source)

		-- Normalize a line: trim + collapse internal whitespace
		local function normalize(str)
			return Utils.trim(str):gsub("%s+", " ")
		end

		-- Strip whitespace from search lines for matching
		local cleanSearchLines = {}
		for _, line in ipairs(searchLines) do
			local normalized = normalize(line)
			if normalized ~= "" then -- Ignore empty lines in search block
				table.insert(cleanSearchLines, normalized)
			end
		end

		if #cleanSearchLines == 0 then
			return { error = "Search content cannot be empty or just whitespace" }
		end

		-- Scan source line-by-line
		local matches = {}
		for i = 1, #sourceLines do
			-- Optimization: Check first line match
			if normalize(sourceLines[i]) == cleanSearchLines[1] then
				-- Check subsequent lines
				local match = true
				local currentSourceIdx = i

				for j = 2, #cleanSearchLines do
					local searchLine = cleanSearchLines[j]

					local foundNext = false
					while currentSourceIdx < #sourceLines do
						currentSourceIdx = currentSourceIdx + 1
						local sourceNorm = normalize(sourceLines[currentSourceIdx])
						if sourceNorm ~= "" then
							if sourceNorm == searchLine then
								foundNext = true
							else
								match = false -- Mismatch on content
							end
							break
						end
					end

					if not foundNext or not match then
						match = false
						break
					end
				end

				if match then
					-- Store start and ACTUAL end index (including skipped lines)
					table.insert(matches, {startLine = i, endLine = currentSourceIdx})
				end
			end
		end

		-- 4. Uniqueness Check
		if #matches == 0 then
			return {
				error = "Search content not found. Please verify the code exists exactly as specified."
			}
		elseif #matches > 1 then
			-- Build line numbers string from match tables
			local lineNums = {}
			for _, m in ipairs(matches) do
				table.insert(lineNums, tostring(m.startLine))
			end
			return {
				error = string.format("Ambiguous match: Found %d occurrences at lines %s. Please provide more context.", #matches, table.concat(lineNums, ", "))
			}
		end

		-- Calculate byte positions for the unique match
		local matchInfo = matches[1]
		local startLine = matchInfo.startLine
		local endLine = matchInfo.endLine

		-- Reconstruct source up to startLine to find byte offset
		local preMatch = table.concat(sourceLines, "\n", 1, startLine - 1)
		if startLine > 1 then preMatch = preMatch .. "\n" end

		local matchContent = table.concat(sourceLines, "\n", startLine, endLine)

		matchStart = #preMatch + 1
		matchEnd = matchStart + #matchContent - 1
	else
		-- Check for multiple exact matches
		local secondStart = source:find(searchContent, matchEnd + 1, true)
		if secondStart then
			return {
				error = "Ambiguous match: Search content found multiple times. Please provide more context."
			}
		end
	end

	-- Apply the patch
	local newSource = source:sub(1, matchStart - 1) .. replaceContent .. source:sub(matchEnd + 1)

	-- Create undo waypoint
	ChangeHistoryService:SetWaypoint("Lux: Patch " .. data.path)

	-- Apply edit
	script.Source = newSource

	-- SYSTEM UPDATE: We modified a script, manifest might need refresh
	IndexManager.invalidate()
	ProjectGraph.updateScript(data.path)

	return {
		path = data.path,
		linesChanged = Utils.countLines(replaceContent),
		patchedLines = string.format("%d-%d", Utils.countLines(source:sub(1, matchStart)), Utils.countLines(source:sub(1, matchEnd)))
	}
end

--- Internal: Apply edit_script operation
--- @param data table
--- @return table result
function WriteTools.applyEditScript(data)
	local script = getInstanceByPath(data.path)
	if not script or not script:IsA("LuaSourceContainer") then
		return {
			error = "Script not found: " .. data.path
		}
	end

	local oldSource = script.Source

	-- Create undo waypoint
	ChangeHistoryService:SetWaypoint("Lux: " .. (data.explanation or "Edit"))

	-- Apply edit
	script.Source = data.newSource

	-- SYSTEM UPDATE: We modified a script
	IndexManager.invalidate()
	ProjectGraph.updateScript(data.path)

	return {
		path = data.path,
		linesChanged = countDifferentLines(oldSource, data.newSource)
	}
end

--- Internal: Apply create_script operation
--- @param data table
--- @return table result
function WriteTools.applyCreateScript(data)
	-- Parse path to get parent and script name
	local pathParts = Utils.splitPath(data.path)
	local scriptName = pathParts[#pathParts]
	local parentPath = table.concat(pathParts, ".", 1, #pathParts - 1)

	local parent = getInstanceByPath(parentPath)
	if not parent then
		return {
			error = "Parent not found: " .. parentPath
		}
	end

	-- Check for existing script
	if parent:FindFirstChild(scriptName) then
		return {
			error = "Script already exists: " .. data.path
		}
	end

	-- Create undo waypoint
	ChangeHistoryService:SetWaypoint("Lux: Create " .. scriptName)

	-- Create script
	local newScript = Instance.new(data.scriptType)
	newScript.Name = scriptName
	newScript.Source = data.source
	newScript.Parent = parent

	-- SYSTEM UPDATE: Tell IndexManager the world has changed
	IndexManager.invalidate()
	ProjectGraph.updateScript(data.path)

	return {
		path = data.path,
		scriptType = data.scriptType,
		lineCount = Utils.countLines(data.source)
	}
end

--- Internal: Apply create_instance operation
--- @param data table
--- @return table result
function WriteTools.applyCreateInstance(data)
	local parent = getInstanceByPath(data.parent)
	if not parent then
		return {
			error = "Parent not found: " .. data.parent
		}
	end

	-- Create undo waypoint
	ChangeHistoryService:SetWaypoint("Lux: Create " .. data.name)

	local instance = Instance.new(data.className)
	instance.Name = data.name

	-- Apply properties with detailed tracking
	local propErrors = {}
	local propsApplied = {}
	local criticalFailures = {} -- Track important properties that failed

	-- Define critical properties that should cause warnings if they fail
	local CRITICAL_PROPERTIES = {
		Size = true, Position = true, Material = true, BrickColor = true,
		Text = true, Font = true, TextColor3 = true, BackgroundColor3 = true
	}

	if data.properties then
		for prop, value in pairs(data.properties) do
			-- CLASS-AWARE: Pass className so parser knows how to interpret Size/Position etc.
			local parsedValue = parsePropertyValue(prop, value, data.className)
			local ok, err = pcall(function()
				instance[prop] = parsedValue
			end)
			if ok then
				table.insert(propsApplied, prop)
			else
				local errorMsg = string.format("%s: %s (value was: %s, parsed as: %s)",
					prop, tostring(err), tostring(value), typeof(parsedValue))
				table.insert(propErrors, errorMsg)
				if CRITICAL_PROPERTIES[prop] then
					table.insert(criticalFailures, prop)
				end
			end
		end
	end

	instance.Parent = parent

	-- SYSTEM UPDATE: Only invalidate if we created a container that might hold scripts
	-- or if we created a script instance directly
	if data.className:match("Script") or data.className:match("Folder") or data.className:match("Model") then
		IndexManager.invalidate()
	end

	-- Brief yield to ensure Roblox hierarchy is updated (prevents race conditions)
	task.wait()

	local result = {
		path = data.parent .. "." .. data.name,
		className = data.className
	}

	if #propsApplied > 0 then
		result.propertiesApplied = propsApplied
	end

	if #propErrors > 0 then
		result.propertyErrors = propErrors
		-- Add a prominent warning if critical properties failed
		if #criticalFailures > 0 then
			result.warning = string.format(
				"Instance created but %d critical properties failed: %s. The instance may not look or behave as expected.",
				#criticalFailures,
				table.concat(criticalFailures, ", ")
			)
		end
	end

	return result
end

--- Internal: Apply set_instance_properties operation
--- @param data table
--- @return table result
function WriteTools.applySetProperties(data)
	local instance = getInstanceByPath(data.path)
	if not instance then
		return {
			error = "Instance not found: " .. data.path
		}
	end

	-- Get className for class-aware property parsing
	local className = instance.ClassName

	-- Create undo waypoint
	ChangeHistoryService:SetWaypoint("Lux: Modify " .. instance.Name)

	local changed = {}
	local errors = {}
	for prop, value in pairs(data.newProperties) do
		-- CLASS-AWARE: Pass className so parser knows how to interpret Size/Position etc.
		local parsedValue = parsePropertyValue(prop, value, className)
		local ok, err = pcall(function()
			instance[prop] = parsedValue
		end)
		if ok then
			table.insert(changed, prop)
		else
			table.insert(errors, string.format("%s: %s (value: %s, parsed as: %s)",
				prop, tostring(err), tostring(value), typeof(parsedValue)))
		end
	end

	-- Don't return empty arrays
	local result = {
		path = data.path
	}
	if #changed > 0 then
		result.propertiesChanged = changed
	end

	if #errors > 0 then
		result.propertyErrors = errors
	end

	if #changed == 0 and #errors == 0 then
		result.message = "No properties were changed"
	end

	return result
end

--- Internal: Apply delete_instance operation
--- @param data table
--- @return table result
function WriteTools.applyDeleteInstance(data)
	local instance = getInstanceByPath(data.path)
	if not instance then
		return {
			error = "Instance not found: " .. data.path
		}
	end

	local instanceName = instance.Name

	-- Create undo waypoint
	ChangeHistoryService:SetWaypoint("Lux: Delete " .. instanceName)

	instance:Destroy()

	-- SYSTEM UPDATE: We removed something, map is dirty
	IndexManager.invalidate()
	ProjectGraph.updateScript(data.path)

	return {
		deleted = data.path
	}
end

--============================================================
-- WRITE TOOLS (USER-FACING)
--============================================================

--- Patch a specific block of code in a script
--- @param args table {path: string, search_content: string, replace_content: string}
--- @param approvalQueue table - ApprovalQueue module
--- @param contextSelector table - ContextSelector module
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function WriteTools.patch_script(args, approvalQueue, contextSelector)
	if Constants.DEBUG then
		print(string.format("[Lux WriteTools] patch_script(%s)", args.path))
	end

	-- Validate target exists
	local script = getInstanceByPath(args.path)
	if not script or not script:IsA("LuaSourceContainer") then
		return {
			error = "Script not found: " .. args.path
		}
	end

	-- SAFETY CHECK: Warn about very large scripts (fuzzy matching is O(n*m))
	local source = script.Source
	local lineCount = Utils.countLines(source)
	local LARGE_SCRIPT_THRESHOLD = 5000
	local VERY_LARGE_SCRIPT_THRESHOLD = 20000

	if lineCount > VERY_LARGE_SCRIPT_THRESHOLD then
		return {
			error = string.format("⚠️ Script is very large (%d lines). Use edit_script with line-specific changes instead of patch_script to avoid performance issues.", lineCount)
		}
	elseif lineCount > LARGE_SCRIPT_THRESHOLD then
		-- Warning but allow - will be included in result
		if Constants.DEBUG then
			warn(string.format("[Lux WriteTools] Large script warning: %s has %d lines", args.path, lineCount))
		end
	end

	-- SAFETY CHECK: Block edits if script was modified since last read
	local freshness = contextSelector.getFreshness(args.path)
	if freshness.modifiedAfterRead then
		return {
			error = "⚠️ Script was modified since you last read it. Use get_script first to see the current state, then try again."
		}
	end

	-- Validate input
	if not args.search_content or args.search_content == "" then
		return {
			error = "search_content is required"
		}
	end
	if not args.replace_content then
		return {
			error = "replace_content is required"
		}
	end

	-- Queue for approval
	local opId = approvalQueue.queue("patch_script", {
		path = args.path,
		search_content = args.search_content,
		replace_content = args.replace_content
	})

	return {
		pending = true,
		operationId = opId,
		message = string.format('Patch queued for approval: "%s"', args.path)
	}
end

--- Edit an entire script
--- @param args table {path: string, newSource: string, explanation: string}
--- @param approvalQueue table - ApprovalQueue module
--- @param contextSelector table - ContextSelector module
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function WriteTools.edit_script(args, approvalQueue, contextSelector)
	if Constants.DEBUG then
		print(string.format("[Lux WriteTools] edit_script(%s)", args.path))
	end

	-- Validate target exists
	local script = getInstanceByPath(args.path)
	if not script or not script:IsA("LuaSourceContainer") then
		return {
			error = "Script not found: " .. args.path
		}
	end

	-- SAFETY CHECK: Block edits if script was modified since last read
	local freshness = contextSelector.getFreshness(args.path)
	if freshness.modifiedAfterRead then
		return {
			error = "⚠️ Script was modified since you last read it. Use get_script first to see the current state, then try again."
		}
	end

	-- Validate input
	if not args.newSource then
		return {
			error = "newSource is required"
		}
	end

	-- Capture old source for diff display
	local oldSource = script.Source
	local linesChanged = countDifferentLines(oldSource, args.newSource)

	-- SAFETY WARNING: Calculate how many lines are being removed
	local oldLines = Utils.splitLines(oldSource)
	local newLines = Utils.splitLines(args.newSource)
	local linesRemoved = #oldLines - #newLines

	-- If removing significant amount of code, add warning to operation data
	local deletionWarning = nil
	if linesRemoved > 10 then
		-- Extract sample of what's being removed (first few removed lines)
		local removedSample = {}
		local sampleCount = 0
		for i = 1, #oldLines do
			if sampleCount >= 5 then break end
			local found = false
			for j = 1, #newLines do
				if oldLines[i] == newLines[j] then
					found = true
					break
				end
			end
			if not found and Utils.trim(oldLines[i]) ~= "" then
				table.insert(removedSample, Utils.trim(oldLines[i]):sub(1, 60))
				sampleCount = sampleCount + 1
			end
		end

		if #removedSample > 0 then
			deletionWarning = string.format(
				"⚠️ This edit will REMOVE %d lines. Sample of removed code:\n  %s",
				linesRemoved,
				table.concat(removedSample, "\n  ")
			)
		end
	end

	-- Queue for approval
	local opId = approvalQueue.queue("edit_script", {
		path = args.path,
		oldSource = oldSource,
		newSource = args.newSource,
		explanation = args.explanation,
		linesChanged = linesChanged,
		linesRemoved = linesRemoved,
		deletionWarning = deletionWarning
	})

	return {
		pending = true,
		operationId = opId,
		message = string.format('Edit queued for approval: "%s" (%d lines changed)', args.path, linesChanged)
	}
end

--- Create a new script
--- @param args table {path: string, scriptType: string, source: string, purpose: string}
--- @param approvalQueue table - ApprovalQueue module
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function WriteTools.create_script(args, approvalQueue)
	if Constants.DEBUG then
		print(string.format("[Lux WriteTools] create_script(%s, %s)", args.path, args.scriptType))
	end

	-- Validate script type
	local validTypes = { Script = true, LocalScript = true, ModuleScript = true }
	if not validTypes[args.scriptType] then
		return {
			error = "Invalid scriptType. Must be Script, LocalScript, or ModuleScript."
		}
	end

	-- Validate input
	if not args.path or args.path == "" then
		return {
			error = "path is required"
		}
	end
	if not args.source then
		return {
			error = "source is required"
		}
	end

	-- Parse path to validate parent exists (or will exist)
	local pathParts = Utils.splitPath(args.path)
	local parentPath = table.concat(pathParts, ".", 1, #pathParts - 1)

	if not willPathExist(parentPath, approvalQueue.getAll()) then
		return {
			error = "Parent not found and not queued for creation: " .. parentPath
		}
	end

	-- Check if script already exists
	if getInstanceByPath(args.path) then
		return {
			error = "Script already exists: " .. args.path
		}
	end

	-- Queue for approval
	local opId = approvalQueue.queue("create_script", {
		path = args.path,
		scriptType = args.scriptType,
		source = args.source,
		purpose = args.purpose or "No purpose specified",
		lineCount = Utils.countLines(args.source)
	})

	return {
		pending = true,
		operationId = opId,
		message = string.format('Script creation queued: %s (%s, %d lines)', args.path, args.scriptType, Utils.countLines(args.source))
	}
end

--- Create a new Instance (non-script)
--- @param args table {className: string, parent: string, name: string, properties: table}
--- @param approvalQueue table - ApprovalQueue module
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function WriteTools.create_instance(args, approvalQueue)
	if Constants.DEBUG then
		print(string.format("[Lux WriteTools] create_instance(%s, %s, %s)", args.className, args.parent, args.name))
	end

	-- Validate parent exists OR will exist after pending operations
	if not willPathExist(args.parent, approvalQueue.getAll()) then
		return {
			error = "Parent not found and not queued for creation: " .. args.parent
		}
	end

	-- Check if child already exists (only if parent exists now)
	local parent = getInstanceByPath(args.parent)
	if parent and parent:FindFirstChild(args.name) then
		return {
			error = "A child named '" .. args.name .. "' already exists in " .. args.parent
		}
	end

	-- Validate className (test creation)
	local testSuccess = pcall(function()
		return Instance.new(args.className)
	end)

	if not testSuccess then
		return {
			error = "Invalid className: " .. args.className
		}
	end

	-- Queue for approval
	local opId = approvalQueue.queue("create_instance", {
		className = args.className,
		parent = args.parent,
		name = args.name,
		properties = args.properties or {}
	})

	return {
		pending = true,
		operationId = opId,
		message = string.format('Instance creation queued: %s "%s" in %s', args.className, args.name, args.parent)
	}
end

--- Set properties on an existing Instance
--- @param args table {path: string, properties: table}
--- @param approvalQueue table - ApprovalQueue module
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function WriteTools.set_instance_properties(args, approvalQueue)
	if Constants.DEBUG then
		print(string.format("[Lux WriteTools] set_instance_properties(%s)", args.path))
	end

	-- Validate instance exists OR will exist after pending operations
	if not willPathExist(args.path, approvalQueue.getAll()) then
		return {
			error = "Instance not found and not queued for creation: " .. args.path
		}
	end

	-- Capture old properties for comparison (only if instance exists now)
	local oldProperties = {}
	local instance = getInstanceByPath(args.path)
	if instance then
		for propName, _ in pairs(args.properties) do
			local success, value = pcall(function()
				return instance[propName]
			end)
			if success then
				oldProperties[propName] = value
			end
		end
	end

	-- Queue for approval
	local opId = approvalQueue.queue("set_instance_properties", {
		path = args.path,
		oldProperties = oldProperties,
		newProperties = args.properties
	})

	return {
		pending = true,
		operationId = opId,
		message = string.format('Property changes queued for "%s"', args.path)
	}
end

--- Delete an Instance
--- @param args table {path: string}
--- @param approvalQueue table - ApprovalQueue module
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function WriteTools.delete_instance(args, approvalQueue)
	if Constants.DEBUG then
		print(string.format("[Lux WriteTools] delete_instance(%s)", args.path))
	end

	-- Validate instance exists
	local instance = getInstanceByPath(args.path)
	if not instance then
		return {
			error = "Instance not found: " .. args.path
		}
	end

	-- Capture info about what's being deleted
	local childCount = #instance:GetChildren()
	local descendantCount = #instance:GetDescendants()
	local hasScripts = false
	for _, child in ipairs(instance:GetDescendants()) do
		if child:IsA("LuaSourceContainer") then
			hasScripts = true
			break
		end
	end

	-- Queue for approval
	local opId = approvalQueue.queue("delete_instance", {
		path = args.path,
		instanceInfo = {
			className = instance.ClassName,
			children = childCount,
			descendants = descendantCount,
			hasScripts = hasScripts
		}
	})

	return {
		pending = true,
		operationId = opId,
		message = string.format('Deletion queued: %s (%s with %d descendants)', args.path, instance.ClassName, descendantCount)
	}
end

--- Request user feedback/verification
--- This pauses the agent loop and waits for user to verify something
--- @param args table {question: string, context: string, verification_type: string, suggestions: table}
--- @param approvalQueue table - ApprovalQueue module
--- @return table {awaitingFeedback: boolean, feedbackRequest: table}
function WriteTools.request_user_feedback(args, approvalQueue)
	if Constants.DEBUG then
		print(string.format("[Lux WriteTools] request_user_feedback: %s", args.question or "?"))
	end

	-- Validate required fields
	if not args.question or args.question == "" then
		return {
			error = "question is required"
		}
	end

	if not args.context then
		return {
			error = "context is required"
		}
	end

	-- Validate verification_type
	local validTypes = { visual = true, functional = true, both = true }
	local verType = args.verification_type or "visual"
	if not validTypes[verType] then
		verType = "visual"
	end

	-- Build the feedback request
	local feedbackRequest = {
		question = args.question,
		context = args.context,
		verificationType = verType,
		suggestions = args.suggestions or {}
	}

	-- Queue an operation-like structure for the feedback
	local opId = approvalQueue.queue("user_feedback", feedbackRequest)

	return {
		awaitingFeedback = true,
		operationId = opId,
		feedbackRequest = feedbackRequest,
		message = "Awaiting user verification"
	}
end

--============================================================
-- TOOL DISPATCHER
--============================================================

--- Execute a write tool by name
--- @param toolName string
--- @param args table
--- @param approvalQueue table - ApprovalQueue module
--- @param contextSelector table - ContextSelector module (optional, for edit safety checks)
--- @return table result
function WriteTools.execute(toolName, args, approvalQueue, contextSelector)
	if toolName == "patch_script" then
		return WriteTools.patch_script(args, approvalQueue, contextSelector)
	elseif toolName == "edit_script" then
		return WriteTools.edit_script(args, approvalQueue, contextSelector)
	elseif toolName == "create_script" then
		return WriteTools.create_script(args, approvalQueue)
	elseif toolName == "create_instance" then
		return WriteTools.create_instance(args, approvalQueue)
	elseif toolName == "set_instance_properties" then
		return WriteTools.set_instance_properties(args, approvalQueue)
	elseif toolName == "delete_instance" then
		return WriteTools.delete_instance(args, approvalQueue)
	elseif toolName == "request_user_feedback" then
		return WriteTools.request_user_feedback(args, approvalQueue)
	else
		return {
			error = "Unknown write tool: " .. toolName
		}
	end
end

--- Apply a pending operation
--- @param operationType string
--- @param data table
--- @return table result
function WriteTools.apply(operationType, data)
	if operationType == "patch_script" then
		return WriteTools.applyPatchScript(data)
	elseif operationType == "edit_script" then
		return WriteTools.applyEditScript(data)
	elseif operationType == "create_script" then
		return WriteTools.applyCreateScript(data)
	elseif operationType == "create_instance" then
		return WriteTools.applyCreateInstance(data)
	elseif operationType == "set_instance_properties" then
		return WriteTools.applySetProperties(data)
	elseif operationType == "delete_instance" then
		return WriteTools.applyDeleteInstance(data)
	else
		return {
			error = "Unknown operation type: " .. operationType
		}
	end
end

return WriteTools
