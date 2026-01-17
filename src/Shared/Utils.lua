--[[
    Utils.lua
    Utility functions for string manipulation and common operations
]]

local Utils = {}

--[=[
    Janitor Class
    A standard cleanup manager for connections, instances, and threads.
    Prevents memory leaks by tracking and cleaning up resources.

    Usage:
        local janitor = Utils.Janitor.new()
        janitor:Add(connection, "Disconnect")
        janitor:Add(instance, "Destroy")
        janitor:Cleanup()
]=]
local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
	local self = setmetatable({}, Janitor)
	self._items = {}
	return self
end

function Janitor:Add(item, cleanupMethod, index)
	cleanupMethod = cleanupMethod or "Destroy"

	local entry = {
		item = item,
		method = cleanupMethod
	}

	if index then
		self._items[index] = entry
	else
		table.insert(self._items, entry)
	end

	return item
end

function Janitor:Remove(index)
	if type(index) == "number" then
		table.remove(self._items, index)
	else
		self._items[index] = nil
	end
end

function Janitor:Cleanup()
	for _, entry in pairs(self._items) do
		if entry and entry.item then
			local item = entry.item
			local method = entry.method

			if type(method) == "string" then
				if typeof(item) == "RBXScriptConnection" then
					item:Disconnect()
				elseif typeof(item) == "Instance" then
					item:Destroy()
				elseif type(item) == "table" and type(item[method]) == "function" then
					item[method](item)
				end
			elseif type(method) == "function" then
				method(item)
			end
		end
	end

	self._items = {}
end

function Janitor:Destroy()
	self:Cleanup()
end

Utils.Janitor = Janitor

--[=[
    FastSignal Class
    A pure Lua signal implementation (no BindableEvent overhead).
    Used for reactive event-driven programming.

    Usage:
        local signal = Utils.Signal.new()
        local connection = signal:Connect(function(data)
            print("Signal fired with data:", data)
        end)
        signal:Fire("hello")
        connection:Disconnect()
]=]
local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, handler)
	local self = setmetatable({}, Connection)
	self._signal = signal
	self._handler = handler
	self._connected = true
	return self
end

function Connection:Disconnect()
	if not self._connected then
		return
	end

	self._connected = false

	local handlers = self._signal._handlers
	for i = #handlers, 1, -1 do
		if handlers[i] == self._handler then
			table.remove(handlers, i)
			break
		end
	end
end

function Signal.new()
	local self = setmetatable({}, Signal)
	self._handlers = {}
	return self
end

function Signal:Connect(handler)
	if type(handler) ~= "function" then
		error("Signal:Connect expects a function handler", 2)
	end

	table.insert(self._handlers, handler)
	return Connection.new(self, handler)
end

function Signal:Fire(...)
	local handlers = self._handlers
	for i = 1, #handlers do
		task.spawn(handlers[i], ...)
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	self._handlers = {}
end

Utils.Signal = Signal

--- Trim whitespace from both ends of a string
--- @param s string
--- @return string
function Utils.trim(s)
	return s:match("^%s*(.-)%s*$")
end

--- Split string by delimiter
--- @param str string
--- @param delimiter string
--- @return table
function Utils.split(str, delimiter)
	local result = {}
	local pattern = "(.-)" .. delimiter
	local lastEnd = 1

	for part in str:gmatch(pattern) do
		table.insert(result, part)
	end

	-- Add the last part after the final delimiter
	local lastPart = str:sub(lastEnd)
	if lastPart ~= "" then
		-- Handle the remaining part correctly
		local parts = {}
		for part in (str .. delimiter):gmatch(pattern) do
			table.insert(parts, part)
		end
		return parts
	end

	return result
end

--- Split string into lines (handles both \n and \r\n)
--- @param str string
--- @return table
function Utils.splitLines(str)
	if not str then return {} end
	local lines = {}
	for line in (str .. "\n"):gmatch("(.-)\n") do
		-- gsub returns (result, count) - we only want result
		local cleanLine = (line:gsub("\r$", ""))
		table.insert(lines, cleanLine)
	end
	return lines
end

--- Normalize line endings to \n
--- @param str string
--- @return string
function Utils.normalizeLineEndings(str)
	return str:gsub("\r\n", "\n")
end

--- Count lines in a string
--- @param str string
--- @return number
function Utils.countLines(str)
	if str == "" then return 0 end

	local count = 1
	for _ in str:gmatch("\n") do
		count = count + 1
	end
	return count
end

--- Get lines in a specific range (1-indexed, inclusive)
--- @param source string
--- @param startLine number
--- @param endLine number
--- @return string
function Utils.getLinesInRange(source, startLine, endLine)
	local lines = Utils.splitLines(source)
	local result = {}

	for i = startLine, math.min(endLine, #lines) do
		table.insert(result, lines[i])
	end

	return table.concat(result, "\n")
end

--- Replace lines in a specific range
--- @param source string
--- @param startLine number
--- @param endLine number
--- @param newCode string
--- @return string
function Utils.replaceLinesInRange(source, startLine, endLine, newCode)
	local lines = Utils.splitLines(source)
	local newLines = {}

	-- Add lines before the range
	for i = 1, startLine - 1 do
		table.insert(newLines, lines[i])
	end

	-- Add new code
	for _, line in ipairs(Utils.splitLines(newCode)) do
		table.insert(newLines, line)
	end

	-- Add lines after the range
	for i = endLine + 1, #lines do
		table.insert(newLines, lines[i])
	end

	return table.concat(newLines, "\n")
end

--- Calculate simple hash of a string
--- @param str string
--- @return string hex hash
function Utils.calculateHash(str)
	local hash = 0
	for i = 1, #str do
		hash = ((hash * 31) + string.byte(str, i)) % 2147483647
	end
	return string.format("%08x", hash)
end

--- Get full path of an instance
--- @param object Instance
--- @return string
function Utils.getPath(object)
	local path = object.Name
	local parent = object.Parent

	while parent and parent ~= game do
		path = parent.Name .. "." .. path
		parent = parent.Parent
	end

	return path
end

--- Split a dot-separated path into components
--- @param path string
--- @return table
function Utils.splitPath(path)
	local parts = {}
	for part in path:gmatch("[^.]+") do
		table.insert(parts, part)
	end
	return parts
end

--- Get script instance by path
--- @param path string - e.g. "ServerScriptService.bruh"
--- @return Instance|nil
function Utils.getScriptByPath(path)
	local parts = {}
	for part in path:gmatch("[^.]+") do
		table.insert(parts, part)
	end

	if #parts == 0 then
		return nil
	end

	-- Start from game service
	local current = game:GetService(parts[1])
	if not current then
		return nil
	end

	-- Navigate through path
	for i = 2, #parts do
		current = current:FindFirstChild(parts[i])
		if not current then
			return nil
		end
	end

	return current
end

--- Deep copy a table
--- @param orig table
--- @return table
function Utils.deepCopy(orig)
	local copy
	if type(orig) == 'table' then
		copy = {}
		for k, v in pairs(orig) do
			copy[Utils.deepCopy(k)] = Utils.deepCopy(v)
		end
	else
		copy = orig
	end
	return copy
end

--- Check if a table contains a value
--- @param tbl table
--- @param value any
--- @return boolean
function Utils.tableContains(tbl, value)
	for _, v in ipairs(tbl) do
		if v == value then
			return true
		end
	end
	return false
end

--- Generate a GUID for session identification
--- @return string
function Utils.generateGUID()
	local HttpService = game:GetService("HttpService")
	return HttpService:GenerateGUID(false) -- false = without braces
end

--- Safe JSON decode with error handling
--- @param jsonString string
--- @return table|nil, string|nil
function Utils.jsonDecode(jsonString)
	local HttpService = game:GetService("HttpService")
	local success, result = pcall(function()
		return HttpService:JSONDecode(jsonString)
	end)

	if success then
		return result, nil
	else
		return nil, "Failed to decode JSON: " .. tostring(result)
	end
end

--- Safe JSON encode with error handling
--- @param data table
--- @return string|nil, string|nil
function Utils.jsonEncode(data)
	local HttpService = game:GetService("HttpService")
	local success, result = pcall(function()
		return HttpService:JSONEncode(data)
	end)

	if success then
		return result, nil
	else
		return nil, "Failed to encode JSON: " .. tostring(result)
	end
end

--- Format a number with commas
--- @param num number
--- @return string
function Utils.formatNumber(num)
	local formatted = tostring(num)
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return formatted
end

--- Truncate string to max length with ellipsis
--- @param str string
--- @param maxLength number
--- @return string
function Utils.truncate(str, maxLength)
	if #str <= maxLength then
		return str
	end
	return str:sub(1, maxLength - 3) .. "..."
end

--- Escape special characters for pattern matching
--- @param str string
--- @return string
function Utils.escapePattern(str)
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

--- Create a debounced version of a function
--- @param func function
--- @param delay number
--- @return function
function Utils.debounce(func, delay)
	local timer = nil
	return function(...)
		local args = {...}
		if timer then
			timer:Disconnect()
		end
		timer = task.delay(delay, function()
			func(unpack(args))
			timer = nil
		end)
	end
end

--- Generate line-by-line diff between two strings
--- @param oldText string
--- @param newText string
--- @return table - Array of {type: "context"|"add"|"remove", lineNum: number, content: string}
function Utils.generateDiff(oldText, newText)
	local oldLines = Utils.splitLines(oldText)
	local newLines = Utils.splitLines(newText)

	local diff = {}
	local maxLen = math.max(#oldLines, #newLines)

	for i = 1, maxLen do
		local oldLine = oldLines[i]
		local newLine = newLines[i]

		if oldLine == newLine and oldLine ~= nil then
			-- Context line (unchanged)
			table.insert(diff, {
				type = "context",
				lineNum = i,
				content = oldLine
			})
		else
			-- Changed line
			if oldLine ~= nil then
				table.insert(diff, {
					type = "remove",
					lineNum = i,
					content = oldLine
				})
			end
			if newLine ~= nil then
				table.insert(diff, {
					type = "add",
					lineNum = i,
					content = newLine
				})
			end
		end
	end

	return diff
end

--- Format properties comparison for display
--- @param oldProps table
--- @param newProps table
--- @return string - Formatted comparison
function Utils.formatPropertyDiff(oldProps, newProps)
	local lines = {}

	for propName, newValue in pairs(newProps) do
		local oldValue = oldProps[propName]

		if oldValue ~= newValue then
			table.insert(lines, string.format("  %s:", propName))
			table.insert(lines, string.format("    - %s", tostring(oldValue)))
			table.insert(lines, string.format("    + %s", tostring(newValue)))
		end
	end

	return table.concat(lines, "\n")
end

return Utils
