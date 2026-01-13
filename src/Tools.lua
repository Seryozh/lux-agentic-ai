--[[
    Tools.lua
    Implementation of all AI tools for the agentic loop

    Creator Store Compliant - No dynamic code execution
]]

local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)
local IndexManager = require(script.Parent.IndexManager)
local ProjectContext = require(script.Parent.ProjectContext)
local ContextSelector = require(script.Parent.ContextSelector)

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")

local Tools = {}

--============================================================
-- PENDING OPERATIONS QUEUE (for user approval)
--============================================================

local pendingOperations = {}
local nextOperationId = 1
local OPERATION_TTL_SECONDS = 600  -- Operations expire after 10 minutes
local MAX_PENDING_OPERATIONS = 50  -- Maximum operations to keep in queue

--- Clean up old/stale operations from the queue
local function cleanupOperations()
	local now = tick()
	local removed = 0

	-- Remove expired and processed operations
	for i = #pendingOperations, 1, -1 do
		local op = pendingOperations[i]
		local age = now - op.timestamp

		-- Remove if: expired, or processed (approved/rejected) and older than 60s
		if age > OPERATION_TTL_SECONDS then
			table.remove(pendingOperations, i)
			removed = removed + 1
		elseif op.status ~= "pending" and age > 60 then
			table.remove(pendingOperations, i)
			removed = removed + 1
		end
	end

	-- If still over max, remove oldest processed operations
	while #pendingOperations > MAX_PENDING_OPERATIONS do
		-- Find oldest non-pending operation
		local oldestIdx = nil
		local oldestTime = math.huge
		for i, op in ipairs(pendingOperations) do
			if op.status ~= "pending" and op.timestamp < oldestTime then
				oldestTime = op.timestamp
				oldestIdx = i
			end
		end

		if oldestIdx then
			table.remove(pendingOperations, oldestIdx)
			removed = removed + 1
		else
			-- All are pending - remove oldest pending as last resort
			table.remove(pendingOperations, 1)
			removed = removed + 1
		end
	end

	if Constants.DEBUG and removed > 0 then
		print(string.format("[Lux Tools] Cleaned up %d stale operations", removed))
	end
end

--- Queue an operation for user approval
--- @param operationType string
--- @param data table
--- @return number operationId
local function queueOperation(operationType, data)
	-- Cleanup old operations before adding new one
	cleanupOperations()

	local operation = {
		id = nextOperationId,
		type = operationType,
		timestamp = tick(),
		status = "pending",  -- "pending" | "approved" | "rejected"
		data = data
	}

	nextOperationId = nextOperationId + 1
	table.insert(pendingOperations, operation)

	if Constants.DEBUG then
		print(string.format("[Lux Tools] Queued operation #%d: %s (queue size: %d)", operation.id, operationType, #pendingOperations))
	end

	return operation.id
end

--============================================================
-- FAILURE TRACKING (to prevent infinite loops)
--============================================================

local failureHistory = {}

local function recordFailure(toolName, args, error)
	-- Create a more robust key to avoid collisions (Priority 4.2)
	local identifier = args.path or args.code or args.query or args.url or ""
	-- Simple hash for long content
	if #identifier > 50 then
		identifier = string.sub(identifier, 1, 20) .. "..." .. string.sub(identifier, -20)
	end
	local key = toolName .. ":" .. identifier

	if not failureHistory[key] then
		failureHistory[key] = {
			count = 0,
			lastError = "",
			timestamp = tick()
		}
	end

	local entry = failureHistory[key]
	entry.count = entry.count + 1
	entry.lastError = error
	entry.timestamp = tick()

	-- Clear old failures (older than 30 seconds - reduced from 120s to allow faster retry)
	for k, v in pairs(failureHistory) do
		if tick() - v.timestamp > 30 then
			failureHistory[k] = nil
		end
	end
end

local function checkRepeatedFailures(toolName, args)
	local identifier = args.path or args.code or args.query or args.url or ""
	if #identifier > 50 then
		identifier = string.sub(identifier, 1, 20) .. "..." .. string.sub(identifier, -20)
	end
	local key = toolName .. ":" .. identifier
	local entry = failureHistory[key]

	if entry and entry.count >= 3 then
		return {
			shouldWarn = true,
			count = entry.count,
			lastError = entry.lastError
		}
	end

	return nil
end

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

-- Properties that are Rect (4 numbers: minX, minY, maxX, maxY)
local RECT_PROPERTIES = {
	ImageRectOffset = true, ImageRectSize = true, -- These are actually Vector2, will handle
	SliceCenter = true, -- Rect
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
-- INTERNAL APPLY FUNCTIONS (called after user approval)
--============================================================

--- Internal: Apply patch_script operation
--- @param data table
--- @return table result
local function applyPatchScript(data)
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

		-- Normalize a line: trim + collapse internal whitespace (Priority 2.3)
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

					-- Advance source index (skipping empty lines in source if needed?) 
					-- For now, strict line following but tolerant of empty source lines if search has them?
					-- Actually, simpler: Search block ignored empty lines. So we should skip empty lines in source too?
					-- Risk: "end \n \n local x" matching "end \n local x". 
					-- Let's stick to contiguous match but skip empty lines in SOURCE too to match the "ignore empty lines in Search" strategy.

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

	return {
		path = data.path,
		linesChanged = Utils.countLines(replaceContent),
		patchedLines = string.format("%d-%d", Utils.countLines(source:sub(1, matchStart)), Utils.countLines(source:sub(1, matchEnd)))
	}
end

--- Internal: Apply edit_script operation
--- @param data table
--- @return table result
local function applyEditScript(data)
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

	return {
		path = data.path,
		linesChanged = countDifferentLines(oldSource, data.newSource)
	}
end

--- Internal: Apply create_script operation
--- @param data table
--- @return table result
local function applyCreateScript(data)
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

	return {
		path = data.path,
		scriptType = data.scriptType,
		lineCount = Utils.countLines(data.source)
	}
end

--- Internal: Apply create_instance operation
--- @param data table
--- @return table result
local function applyCreateInstance(data)
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
local function applySetProperties(data)
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
local function applyDeleteInstance(data)
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

	return {
		deleted = data.path
	}
end


--============================================================
-- SCRIPT TOOLS
--============================================================

--- Get complete source code of a script
--- @param args table {path: string}
--- @return table {success: boolean, path: string, source: string, className: string, lineCount: number} or {success: false, error: string}
function Tools.get_script(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] get_script(%s)", args.path))
	end

	local script = getInstanceByPath(args.path)
	if not script or not script:IsA("LuaSourceContainer") then
		return {
			error = "Script not found: " .. args.path
		}
	end

	local source = script.Source
	local lineCount = Utils.countLines(source)

	return {
		path = args.path,
		source = source,
		className = script.ClassName,
		lineCount = lineCount
	}
end

--- Patch a specific block of code in a script
--- @param args table {path: string, search_content: string, replace_content: string}
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function Tools.patch_script(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] patch_script(%s)", args.path))
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
			error = string.format("?? Script is very large (%d lines). Use edit_script with line-specific changes instead of patch_script to avoid performance issues.", lineCount)
		}
	elseif lineCount > LARGE_SCRIPT_THRESHOLD then
		-- Warning but allow - will be included in result
		if Constants.DEBUG then
			warn(string.format("[Lux Tools] Large script warning: %s has %d lines", args.path, lineCount))
		end
	end

	-- SAFETY CHECK: Block edits if script was modified since last read
	local freshness = ContextSelector.getFreshness(args.path)
	if freshness.modifiedAfterRead then
		return {
			error = "?? Script was modified since you last read it. Use get_script first to see the current state, then try again."
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

	-- Validate syntax of replacement (if it's a complete block/statement)
	-- Note: This is harder for patches as they might be partial code, but we can try
	-- to validate if it looks like a complete statement. For now, we skip strict syntax check
	-- on patches to allow flexibility, but we could add heuristics later.

	-- Queue for approval
	local opId = queueOperation("patch_script", {
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
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function Tools.edit_script(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] edit_script(%s)", args.path))
	end

	-- Validate target exists
	local script = getInstanceByPath(args.path)
	if not script or not script:IsA("LuaSourceContainer") then
		return {
			error = "Script not found: " .. args.path
		}
	end

	-- SAFETY CHECK: Block edits if script was modified since last read
	local freshness = ContextSelector.getFreshness(args.path)
	if freshness.modifiedAfterRead then
		return {
			error = "?? Script was modified since you last read it. Use get_script first to see the current state, then try again."
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
				"?? This edit will REMOVE %d lines. Sample of removed code:\n  %s",
				linesRemoved,
				table.concat(removedSample, "\n  ")
			)
		end
	end

	-- Queue for approval
	local opId = queueOperation("edit_script", {
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
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function Tools.create_script(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] create_script(%s, %s)", args.path, args.scriptType))
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

	if not willPathExist(parentPath) then
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
	local opId = queueOperation("create_script", {
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

--- Search for scripts containing specific code patterns
--- @param args table {query: string}
--- @return table {success: boolean, query: string, matches: table[], count: number} or {success: false, error: string}
function Tools.search_scripts(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] search_scripts(%s)", args.query))
	end

	if not args.query or args.query == "" then
		return {
			error = "query is required"
		}
	end

	local results = {}

	-- Search indexed scripts
	local index = IndexManager.getIndex()
	if index and index.scripts then
		for path, scriptData in pairs(index.scripts) do
			local script = getInstanceByPath(path)
			if script and script:IsA("LuaSourceContainer") then
				local source = script.Source
				local startPos = source:find(args.query, 1, true)

				if startPos then
					-- Find line number
					local lineNum = 1
					for i = 1, startPos do
						if source:sub(i, i) == "\n" then
							lineNum = lineNum + 1
						end
					end

					-- Get context (the line containing the match)
					local lineStart = source:sub(1, startPos):match(".*\n()") or 1
					local lineEnd = source:find("\n", startPos) or #source
					local context = Utils.trim(source:sub(lineStart, lineEnd))

					table.insert(results, {
						path = path,
						line = lineNum,
						context = context:sub(1, 100) -- Truncate long lines
					})
				end
			end
		end
	end

	if #results == 0 then
		return {
			query = args.query,
			count = 0,
			message = "No matches found"
		}
	end

	return {
		query = args.query,
		matches = results,
		count = #results
	}
end

--============================================================
-- CONTEXT TOOLS
--============================================================

function Tools.update_project_context(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] update_project_context(%s): %s",
			args.contextType, args.content:sub(1, 50)))
	end

	-- Build anchor if path provided
	local anchor = nil
	if args.anchorPath and args.anchorPath ~= "" then
		-- Determine anchor type based on what exists
		local instance = Utils.getScriptByPath(args.anchorPath)
		if instance then
			if instance:IsA("LuaSourceContainer") then
				anchor = { type = "script_exists", path = args.anchorPath }
			else
				anchor = { type = "instance_exists", path = args.anchorPath }
			end
		end
	end

	local result = ProjectContext.addEntry(args.contextType, args.content, anchor)
	return result
end

function Tools.get_project_context(args)
	if Constants.DEBUG then
		print("[Lux Tools] get_project_context()")
	end

	local entries = ProjectContext.getEntries(args.includeStale or false)
	local sessionInfo = ProjectContext.getSessionInfo()

	if #entries == 0 then
		return {
			hasContext = false,
			message = "No project context exists yet. Use update_project_context to add discoveries.",
			sessionInfo = sessionInfo
		}
	end

	return {
		hasContext = true,
		entries = entries,
		sessionInfo = sessionInfo,
		formatted = ProjectContext.formatForPrompt()
	}
end

function Tools.discover_project(args)
	if Constants.DEBUG then
		print("[Lux Tools] discover_project()")
	end

	local hints = ProjectContext.getDiscoveryHints()
	local sessionInfo = ProjectContext.getSessionInfo()

	return {
		scriptCount = hints.scriptCount,
		hasExistingScripts = hints.hasScripts,
		locations = hints.locations,
		potentialFrameworks = hints.potentialFrameworks,
		existingContext = sessionInfo.hasContext,
		staleContextCount = sessionInfo.staleCount,
		suggestion = hints.hasScripts and not sessionInfo.hasContext
			and "This game has scripts but no context. Consider reading key scripts and documenting architecture."
			or nil
	}
end

function Tools.validate_context(args)
	if Constants.DEBUG then
		print("[Lux Tools] validate_context()")
	end

	local results = ProjectContext.validateAll()

	local response = {
		validEntries = results.valid,
		staleEntries = results.stale,
		message = results.stale > 0
			and string.format("%d entries are stale and should be reviewed or removed", results.stale)
			or "All context entries are valid"
	}

	if results.stale > 0 then
		response.staleDetails = results.staleEntries
	end

	return response
end

--============================================================
-- USER FEEDBACK TOOL
--============================================================

--- Request user feedback/verification
--- This pauses the agent loop and waits for user to verify something
--- @param args table {question: string, context: string, verification_type: string, suggestions: table}
--- @return table {awaitingFeedback: boolean, feedbackRequest: table}
function Tools.request_user_feedback(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] request_user_feedback: %s", args.question or "?"))
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
	local opId = queueOperation("user_feedback", feedbackRequest)

	return {
		awaitingFeedback = true,
		operationId = opId,
		feedbackRequest = feedbackRequest,
		message = "Awaiting user verification"
	}
end

--============================================================
-- WEB TOOLS
--============================================================

function Tools.web_fetch(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] web_fetch(%s)", args.url))
	end

	-- Validate URL
	if not args.url:match("^https://") then
		return {
			error = "Only HTTPS URLs are supported"
		}
	end

	-- Block potentially dangerous domains
	local blockedDomains = { "localhost", "127.0.0.1", "0.0.0.0", "internal" }
	for _, blocked in ipairs(blockedDomains) do
		if args.url:lower():find(blocked) then
			return {
				error = "This domain is blocked"
			}
		end
	end

	local maxLength = args.maxLength or 10000

	local success, result = pcall(function()
		return HttpService:GetAsync(args.url)
	end)

	if not success then
		return {
			error = "Failed to fetch URL: " .. tostring(result)
		}
	end

	-- Truncate if too long
	if #result > maxLength then
		result = result:sub(1, maxLength) .. "\n... [truncated]"
	end

	return {
		url = args.url,
		content = result,
		length = #result
	}
end

--============================================================
-- INSTANCE INSPECTION TOOLS
--============================================================

--- Serialize a value for JSON-safe output
--- @param value any
--- @param depth number
--- @return any
local function serializeValue(value, depth)
	depth = depth or 0
	if depth > 3 then return "<max depth>" end

	local valueType = typeof(value)

	if valueType == "string" then
		return value
	elseif valueType == "number" or valueType == "boolean" then
		return value
	elseif valueType == "nil" then
		return nil
	elseif valueType == "Vector3" then
		return string.format("Vector3(%g, %g, %g)", value.X, value.Y, value.Z)
	elseif valueType == "Vector2" then
		return string.format("Vector2(%g, %g)", value.X, value.Y)
	elseif valueType == "CFrame" then
		return string.format("CFrame(%g, %g, %g)", value.Position.X, value.Position.Y, value.Position.Z)
	elseif valueType == "Color3" then
		return string.format("Color3(%d, %d, %d)", math.floor(value.R * 255), math.floor(value.G * 255), math.floor(value.B * 255))
	elseif valueType == "BrickColor" then
		return "BrickColor(" .. value.Name .. ")"
	elseif valueType == "UDim2" then
		return string.format("UDim2(%g, %d, %g, %d)", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
	elseif valueType == "UDim" then
		return string.format("UDim(%g, %d)", value.Scale, value.Offset)
	elseif valueType == "Enum" then
		return tostring(value)
	elseif valueType == "EnumItem" then
		return tostring(value)
	elseif valueType == "Instance" then
		return "<Instance: " .. value:GetFullName() .. ">"
	elseif valueType == "table" then
		local result = {}
		for k, v in pairs(value) do
			result[tostring(k)] = serializeValue(v, depth + 1)
		end
		return result
	else
		return "<" .. valueType .. ">"
	end
end

--- Get common readable properties for an instance
--- @param instance Instance
--- @return table
local function getReadableProperties(instance)
	local props = {}

	-- Universal properties
	props.Name = instance.Name
	props.ClassName = instance.ClassName
	props.Parent = instance.Parent and instance.Parent:GetFullName() or nil

	-- Common properties by class type
	local className = instance.ClassName

	-- Try to read common properties safely
	local commonProps = {
		-- BasePart properties
		"Position", "Size", "CFrame", "Anchored", "CanCollide", "Transparency",
		"BrickColor", "Color", "Material", "Shape",
		-- GuiObject properties
		"Visible", "BackgroundColor3", "BackgroundTransparency", "BorderColor3",
		"AnchorPoint", "ZIndex", "LayoutOrder", "Active", "ClipsDescendants",
		-- Text properties
		"Text", "TextColor3", "TextSize", "Font", "TextScaled", "RichText",
		-- Image properties
		"Image", "ImageColor3", "ImageTransparency", "ScaleType",
		-- Frame/ScrollingFrame
		"AutomaticSize", "CanvasSize", "ScrollingDirection",
		-- Value objects
		"Value",
		-- Model properties
		"PrimaryPart", "WorldPivot",
		-- Script properties (Source is readable but we use get_script for that)
		"Enabled", "Disabled",
		-- Light properties
		"Brightness", "Range", "Shadows",
		-- Sound properties
		"SoundId", "Volume", "Looped", "Playing",
		-- Animation
		"AnimationId",
	}

	for _, propName in ipairs(commonProps) do
		local success, value = pcall(function()
			return instance[propName]
		end)
		if success and value ~= nil then
			props[propName] = serializeValue(value)
		end
	end

	return props
end

--- Get detailed information about an instance
--- @param args table {path: string, properties: table (optional list of specific properties)}
--- @return table
function Tools.get_instance(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] get_instance(%s)", args.path))
	end

	local instance = getInstanceByPath(args.path)
	if not instance then
		return { error = "Instance not found: " .. args.path }
	end

	local result = {
		path = args.path,
		className = instance.ClassName,
		fullName = instance:GetFullName(),
		properties = {},
		childCount = #instance:GetChildren(),
		descendantCount = #instance:GetDescendants()
	}

	-- If specific properties requested, get those
	if args.properties and type(args.properties) == "table" then
		for _, propName in ipairs(args.properties) do
			local success, value = pcall(function()
				return instance[propName]
			end)
			if success then
				result.properties[propName] = serializeValue(value)
			else
				result.properties[propName] = "<unreadable>"
			end
		end
	else
		-- Get common readable properties
		result.properties = getReadableProperties(instance)
	end

	return result
end

--- List children of an instance with basic info
--- @param args table {path: string, classFilter: string (optional)}
--- @return table
function Tools.list_children(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] list_children(%s)", args.path))
	end

	local instance = getInstanceByPath(args.path)
	if not instance then
		return { error = "Instance not found: " .. args.path }
	end

	local children = {}
	for _, child in ipairs(instance:GetChildren()) do
		-- Apply class filter if specified
		if not args.classFilter or child:IsA(args.classFilter) then
			local childInfo = {
				name = child.Name,
				className = child.ClassName,
				path = args.path .. "." .. child.Name
			}

			-- Add useful summary info based on class
			if child:IsA("LuaSourceContainer") then
				childInfo.lineCount = Utils.countLines(child.Source)
			elseif child:IsA("BasePart") then
				childInfo.size = serializeValue(child.Size)
				childInfo.position = serializeValue(child.Position)
			elseif child:IsA("GuiObject") then
				childInfo.visible = child.Visible
				local sizeSuccess, size = pcall(function() return child.Size end)
				if sizeSuccess then childInfo.size = serializeValue(size) end
			elseif child:IsA("ValueBase") then
				local valSuccess, val = pcall(function() return child.Value end)
				if valSuccess then childInfo.value = serializeValue(val) end
			end

			childInfo.childCount = #child:GetChildren()
			table.insert(children, childInfo)
		end
	end

	return {
		path = args.path,
		className = instance.ClassName,
		childCount = #children,
		children = children
	}
end

--- Get a tree view of descendants (useful for understanding UI/model structure)
--- @param args table {path: string, maxDepth: number (default 3), classFilter: string (optional)}
--- @return table
function Tools.get_descendants_tree(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] get_descendants_tree(%s)", args.path))
	end

	local instance = getInstanceByPath(args.path)
	if not instance then
		return { error = "Instance not found: " .. args.path }
	end

	local maxDepth = args.maxDepth or 3

	local function buildTree(inst, depth, parentPath)
		if depth > maxDepth then
			local remaining = #inst:GetDescendants()
			if remaining > 0 then
				return { _truncated = true, remaining = remaining }
			end
			return nil
		end

		local node = {
			name = inst.Name,
			className = inst.ClassName,
			path = parentPath
		}

		-- Add key properties based on type
		if inst:IsA("LuaSourceContainer") then
			node.lineCount = Utils.countLines(inst.Source)
		elseif inst:IsA("GuiObject") then
			node.visible = inst.Visible
		elseif inst:IsA("ValueBase") then
			local success, val = pcall(function() return inst.Value end)
			if success then node.value = serializeValue(val) end
		end

		local children = inst:GetChildren()
		if #children > 0 then
			node.children = {}
			for _, child in ipairs(children) do
				-- Apply class filter if specified
				if not args.classFilter or child:IsA(args.classFilter) then
					local childPath = parentPath .. "." .. child.Name
					local childNode = buildTree(child, depth + 1, childPath)
					if childNode then
						table.insert(node.children, childNode)
					end
				end
			end
			if #node.children == 0 then
				node.children = nil
			end
		end

		return node
	end

	local tree = buildTree(instance, 1, args.path)

	return {
		path = args.path,
		maxDepth = maxDepth,
		tree = tree
	}
end

--============================================================
-- INSTANCE MODIFICATION TOOLS
--============================================================

--- Create a new Instance (non-script)
--- @param args table {className: string, parent: string, name: string, properties: table}
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function Tools.create_instance(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] create_instance(%s, %s, %s)", args.className, args.parent, args.name))
	end

	-- Validate parent exists OR will exist after pending operations
	if not willPathExist(args.parent) then
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
	local opId = queueOperation("create_instance", {
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
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function Tools.set_instance_properties(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] set_instance_properties(%s)", args.path))
	end

	-- Validate instance exists OR will exist after pending operations
	if not willPathExist(args.path) then
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
	local opId = queueOperation("set_instance_properties", {
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
--- @return table {success: boolean, pending: boolean, operationId: number, message: string} or {success: false, error: string}
function Tools.delete_instance(args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] delete_instance(%s)", args.path))
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
	local descendantCount = #instance:GetDescendants() -- Priority 4.1
	local hasScripts = false
	for _, child in ipairs(instance:GetDescendants()) do
		if child:IsA("LuaSourceContainer") then
			hasScripts = true
			break
		end
	end

	-- Queue for approval
	local opId = queueOperation("delete_instance", {
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

--============================================================
-- TOOL DISPATCHER
--============================================================

--- Execute a tool call
--- @param toolName string
--- @param args table
--- @return table result
function Tools.execute(toolName, args)
	if Constants.DEBUG then
		print(string.format("[Lux Tools] Executing: %s", toolName))
	end

	-- Check for repeated failures
	local repeatedFailure = checkRepeatedFailures(toolName, args)
	if repeatedFailure then
		return {
			error = string.format(
				"This operation has failed %d times recently. Last error: %s",
				repeatedFailure.count,
				repeatedFailure.lastError
			),
			hint = "Try a different approach or ask the user for help. Don't repeat the same failing operation."
		}
	end

	-- Dispatch to appropriate handler
	local result
	if toolName == "get_script" then
		result = Tools.get_script(args)
	elseif toolName == "patch_script" then
		result = Tools.patch_script(args)
	elseif toolName == "edit_script" then
		result = Tools.edit_script(args)
	elseif toolName == "create_script" then
		result = Tools.create_script(args)
	elseif toolName == "search_scripts" then
		result = Tools.search_scripts(args)
	elseif toolName == "get_instance" then
		result = Tools.get_instance(args)
	elseif toolName == "list_children" then
		result = Tools.list_children(args)
	elseif toolName == "get_descendants_tree" then
		result = Tools.get_descendants_tree(args)
	elseif toolName == "create_instance" then
		result = Tools.create_instance(args)
	elseif toolName == "set_instance_properties" then
		result = Tools.set_instance_properties(args)
	elseif toolName == "delete_instance" then
		result = Tools.delete_instance(args)
	elseif toolName == "update_project_context" then
		result = Tools.update_project_context(args)
	elseif toolName == "get_project_context" then
		result = Tools.get_project_context(args)
	elseif toolName == "discover_project" then
		result = Tools.discover_project(args)
	elseif toolName == "validate_context" then
		result = Tools.validate_context(args)
	elseif toolName == "web_fetch" then
		result = Tools.web_fetch(args)
	elseif toolName == "request_user_feedback" then
		result = Tools.request_user_feedback(args)
	else
		result = {
			error = "Unknown tool: " .. toolName
		}
	end

	-- Track failures for loop prevention
	if result and result.error then
		recordFailure(toolName, args, result.error)
	end

	return result
end

--============================================================
-- PENDING OPERATIONS MANAGEMENT
--============================================================

--- Get all pending operations
--- @return table - Array of pending operations
function Tools.getPendingOperations()
	return pendingOperations
end

--- Apply a pending operation
--- @param operationId number
--- @return table result
function Tools.applyOperation(operationId)
	local operation = nil
	for _, op in ipairs(pendingOperations) do
		if op.id == operationId then
			operation = op
			break
		end
	end

	if not operation then
		return {
			error = "Operation not found: " .. tostring(operationId)
		}
	end

	if operation.status ~= "pending" then
		return {
			error = "Operation already processed (status: " .. operation.status .. ")"
		}
	end

	-- Check if operation has expired (TTL)
	local age = tick() - operation.timestamp
	if age > OPERATION_TTL_SECONDS then
		operation.status = "expired"
		return {
			error = string.format("Operation expired (%.0f seconds old). Please retry the operation.", age)
		}
	end

	-- Apply based on type
	local result
	if operation.type == "patch_script" then
		result = applyPatchScript(operation.data)
	elseif operation.type == "edit_script" then
		result = applyEditScript(operation.data)
	elseif operation.type == "create_script" then
		result = applyCreateScript(operation.data)
	elseif operation.type == "create_instance" then
		result = applyCreateInstance(operation.data)
	elseif operation.type == "set_instance_properties" then
		result = applySetProperties(operation.data)
	elseif operation.type == "delete_instance" then
		result = applyDeleteInstance(operation.data)
	else
		return {
			error = "Unknown operation type: " .. operation.type
		}
	end

	if not result.error then
		operation.status = "approved"
		if Constants.DEBUG then
			print(string.format("[Lux Tools] Applied operation #%d: %s", operation.id, operation.type))
		end
	else
		if Constants.DEBUG then
			print(string.format("[Lux Tools] Failed to apply operation #%d: %s", operation.id, result.error))
		end
	end

	return result
end

--- Reject a pending operation
--- @param operationId number
--- @return table result
function Tools.rejectOperation(operationId)
	for _, op in ipairs(pendingOperations) do
		if op.id == operationId then
			op.status = "rejected"
			if Constants.DEBUG then
				print(string.format("[Lux Tools] Rejected operation #%d: %s", op.id, op.type))
			end
			return {
			}
		end
	end
	return {
		error = "Operation not found: " .. tostring(operationId)
	}
end

--- Clear all pending operations
function Tools.clearPendingOperations()
	local count = #pendingOperations
	pendingOperations = {}
	nextOperationId = 1
	if Constants.DEBUG then
		print(string.format("[Lux Tools] Cleared %d pending operations", count))
	end
end

--============================================================
-- TOOL DISPLAY FORMATTING (for user-friendly output)
--============================================================

--- Format tool call intent for display
--- @param toolName string
--- @param args table
--- @return string - Human-readable description of what the tool will do
function Tools.formatToolIntent(toolName, args)
	local intent = ""

	if toolName == "get_script" then
		intent = string.format("?? Reading script: `%s`", args.path or "?")

	elseif toolName == "patch_script" then
		local searchPreview = (args.search_content or ""):sub(1, 50):gsub("\n", "?")
		if #(args.search_content or "") > 50 then searchPreview = searchPreview .. "..." end
		intent = string.format("?? Patching `%s`\n? Finding: `%s`", args.path or "?", searchPreview)

	elseif toolName == "edit_script" then
		intent = string.format("?? Rewriting `%s`\n? Reason: %s", args.path or "?", args.explanation or "No explanation")

	elseif toolName == "create_script" then
		intent = string.format("?? Creating %s: `%s`\n? Purpose: %s", 
			args.scriptType or "Script", args.path or "?", args.purpose or "No purpose specified")

	elseif toolName == "create_instance" then
		local propsStr = ""
		if args.properties and next(args.properties) then
			local propList = {}
			for k, v in pairs(args.properties) do
				table.insert(propList, string.format("%s=%s", k, tostring(v):sub(1,20)))
			end
			propsStr = "\n? Properties: " .. table.concat(propList, ", "):sub(1, 80)
		end
		intent = string.format("?? Creating %s `%s` in `%s`%s", 
			args.className or "Instance", args.name or "?", args.parent or "?", propsStr)

	elseif toolName == "set_instance_properties" then
		local propList = {}
		if args.properties then
			for k, v in pairs(args.properties) do
				table.insert(propList, string.format("%s=%s", k, tostring(v):sub(1,20)))
			end
		end
		intent = string.format("?? Modifying `%s`\n? Setting: %s", 
			args.path or "?", table.concat(propList, ", "):sub(1, 80))

	elseif toolName == "delete_instance" then
		intent = string.format("??? Deleting `%s`", args.path or "?")

	elseif toolName == "get_instance" then
		intent = string.format("?? Inspecting `%s`", args.path or "?")

	elseif toolName == "list_children" then
		local filter = args.classFilter and (" (filter: " .. args.classFilter .. ")") or ""
		intent = string.format("?? Listing children of `%s`%s", args.path or "?", filter)

	elseif toolName == "get_descendants_tree" then
		intent = string.format("?? Mapping structure of `%s` (depth: %d)", args.path or "?", args.maxDepth or 3)

	elseif toolName == "search_scripts" then
		intent = string.format("?? Searching scripts for: `%s`", (args.query or ""):sub(1, 50))

	elseif toolName == "update_project_context" then
		intent = string.format("?? Saving %s context: %s", args.contextType or "?", (args.content or ""):sub(1, 50))

	elseif toolName == "get_project_context" then
		intent = "?? Loading project context"

	elseif toolName == "discover_project" then
		intent = "?? Discovering project structure"

	elseif toolName == "validate_context" then
		intent = "? Validating saved context"

	elseif toolName == "web_fetch" then
		intent = string.format("?? Fetching URL: %s", (args.url or ""):sub(1, 60))

	else
		intent = string.format("?? %s", toolName)
	end

	return intent
end

--- Format tool result for display
--- @param toolName string
--- @param result table
--- @return string - Human-readable description of the result
function Tools.formatToolResult(toolName, result)
	if result.error then
		return string.format("? Error: %s", result.error)
	end

	local output = ""

	if toolName == "get_script" then
		output = string.format("? Read %d lines from `%s`", result.lineCount or 0, result.path or "?")

	elseif toolName == "patch_script" then
		if result.pending then
			output = string.format("? Awaiting approval for patch to `%s`", result.message or "")
		else
			output = string.format("? Patched lines %s in `%s`", result.patchedLines or "?", result.path or "?")
		end

	elseif toolName == "edit_script" then
		if result.pending then
			output = string.format("? %s", result.message or "Awaiting approval")
		else
			output = string.format("? Rewrote `%s` (%d lines changed)", result.path or "?", result.linesChanged or 0)
		end

	elseif toolName == "create_script" then
		if result.pending then
			output = string.format("? %s", result.message or "Awaiting approval")
		else
			output = string.format("? Created `%s` (%d lines)", result.path or "?", result.lineCount or 0)
		end

	elseif toolName == "create_instance" then
		if result.pending then
			output = string.format("? %s", result.message or "Awaiting approval")
		else
			local propsInfo = ""
			if result.propertiesApplied and #result.propertiesApplied > 0 then
				propsInfo = string.format("\n? Applied: %s", table.concat(result.propertiesApplied, ", "))
			end
			if result.propertyErrors and #result.propertyErrors > 0 then
				propsInfo = propsInfo .. string.format("\n? Failed: %d properties", #result.propertyErrors)
			end
			output = string.format("? Created `%s`%s", result.path or "?", propsInfo)
			if result.warning then
				output = output .. "\n?? " .. result.warning
			end
		end

	elseif toolName == "set_instance_properties" then
		if result.pending then
			output = string.format("? %s", result.message or "Awaiting approval")
		else
			local changes = result.propertiesChanged and table.concat(result.propertiesChanged, ", ") or "none"
			output = string.format("? Modified `%s` [%s]", result.path or "?", changes)
		end

	elseif toolName == "delete_instance" then
		if result.pending then
			output = string.format("? %s", result.message or "Awaiting approval")
		else
			output = string.format("? Deleted `%s`", result.deleted or "?")
		end

	elseif toolName == "get_instance" then
		output = string.format("? Found %s `%s` (%d children)", 
			result.className or "Instance", result.path or "?", result.childCount or 0)

	elseif toolName == "list_children" then
		output = string.format("? Found %d children in `%s`", result.childCount or 0, result.path or "?")

	elseif toolName == "get_descendants_tree" then
		output = string.format("? Mapped `%s` hierarchy", result.path or "?")

	elseif toolName == "search_scripts" then
		output = string.format("? Found %d matches for `%s`", result.count or 0, result.query or "?")

	elseif toolName == "update_project_context" then
		output = "? Context saved"

	elseif toolName == "get_project_context" then
		if result.hasContext then
			output = string.format("? Loaded %d context entries", result.entries and #result.entries or 0)
		else
			output = "?? No project context found"
		end

	elseif toolName == "discover_project" then
		output = string.format("? Found %d scripts", result.scriptCount or 0)

	elseif toolName == "validate_context" then
		output = string.format("? %d valid, %d stale entries", result.validEntries or 0, result.staleEntries or 0)

	elseif toolName == "web_fetch" then
		output = string.format("? Fetched %d bytes from %s", result.length or 0, result.url or "?")

	else
		output = "? Complete"
	end

	return output
end

return Tools
