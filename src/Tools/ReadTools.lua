--[[
	ReadTools.lua
	Read-only tool implementations for inspecting game state

	Handles:
	- Script source code reading
	- Instance property inspection
	- Hierarchy listing and tree traversal
	- Script search functionality
	- Project discovery

	These tools are safe and never modify game state.

	Creator Store Compliant - No dynamic code execution
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Utils = require(script.Parent.Parent.Shared.Utils)
local IndexManager = require(script.Parent.Parent.Shared.IndexManager)

local HttpService = game:GetService("HttpService")

local ReadTools = {}

--============================================================
-- HELPER FUNCTIONS
--============================================================

--- Get instance by path (e.g., "ServerScriptService.PlayerManager")
--- @param path string
--- @return Instance|nil
local function getInstanceByPath(path)
	return Utils.getScriptByPath(path)
end

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

--============================================================
-- SCRIPT TOOLS
--============================================================

--- Get complete source code of a script
--- @param args table {path: string}
--- @return table {success: boolean, path: string, source: string, className: string, lineCount: number} or {success: false, error: string}
function ReadTools.get_script(args)
	if Constants.DEBUG then
		print(string.format("[Lux ReadTools] get_script(%s)", args.path))
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

--- Search for scripts containing specific code patterns
--- @param args table {query: string}
--- @return table {success: boolean, query: string, matches: table[], count: number} or {success: false, error: string}
function ReadTools.search_scripts(args)
	if Constants.DEBUG then
		print(string.format("[Lux ReadTools] search_scripts(%s)", args.query))
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
-- INSTANCE INSPECTION TOOLS
--============================================================

--- Get detailed information about an instance
--- @param args table {path: string, properties: table (optional list of specific properties)}
--- @return table
function ReadTools.get_instance(args)
	if Constants.DEBUG then
		print(string.format("[Lux ReadTools] get_instance(%s)", args.path))
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
function ReadTools.list_children(args)
	if Constants.DEBUG then
		print(string.format("[Lux ReadTools] list_children(%s)", args.path))
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
function ReadTools.get_descendants_tree(args)
	if Constants.DEBUG then
		print(string.format("[Lux ReadTools] get_descendants_tree(%s)", args.path))
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
-- WEB TOOLS
--============================================================

--- Fetch content from a web URL (read-only operation)
--- @param args table {url: string, maxLength: number (optional)}
--- @return table
function ReadTools.web_fetch(args)
	if Constants.DEBUG then
		print(string.format("[Lux ReadTools] web_fetch(%s)", args.url))
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
-- TOOL DISPATCHER
--============================================================

--- Execute a read tool by name
--- @param toolName string
--- @param args table
--- @return table result
function ReadTools.execute(toolName, args)
	if toolName == "get_script" then
		return ReadTools.get_script(args)
	elseif toolName == "search_scripts" then
		return ReadTools.search_scripts(args)
	elseif toolName == "get_instance" then
		return ReadTools.get_instance(args)
	elseif toolName == "list_children" then
		return ReadTools.list_children(args)
	elseif toolName == "get_descendants_tree" then
		return ReadTools.get_descendants_tree(args)
	elseif toolName == "web_fetch" then
		return ReadTools.web_fetch(args)
	else
		return {
			error = "Unknown read tool: " .. toolName
		}
	end
end

return ReadTools
