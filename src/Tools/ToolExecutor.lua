--[[
	ToolExecutor.lua
	Main tool execution router and coordinator

	Handles:
	- Routing tool calls to appropriate modules (Read/Write/Project)
	- Failure tracking to prevent infinite loops
	- Operation application and rejection
	- Tool formatting for user-friendly display

	Creator Store Compliant - No dynamic code execution
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local ContextSelector = require(script.Parent.Parent.Context.ContextSelector)

local ApprovalQueue = require(script.Parent.ApprovalQueue)
local ReadTools = require(script.Parent.ReadTools)
local WriteTools = require(script.Parent.WriteTools)
local ProjectTools = require(script.Parent.ProjectTools)

local ToolExecutor = {}

--============================================================
-- FAILURE TRACKING (to prevent infinite loops)
--============================================================

local failureHistory = {}

--- Record a tool failure
--- @param toolName string
--- @param args table
--- @param error string
local function recordFailure(toolName, args, error)
	-- Create a more robust key to avoid collisions
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

--- Check if a tool has repeated failures
--- @param toolName string
--- @param args table
--- @return table|nil {shouldWarn: boolean, count: number, lastError: string}
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
-- TOOL ROUTING
--============================================================

-- Define which tools belong to which category
local READ_TOOLS = {
	get_script = true,
	search_scripts = true,
	get_instance = true,
	list_children = true,
	get_descendants_tree = true,
	web_fetch = true,
}

local WRITE_TOOLS = {
	patch_script = true,
	edit_script = true,
	create_script = true,
	create_instance = true,
	set_instance_properties = true,
	delete_instance = true,
	request_user_feedback = true,
}

local PROJECT_TOOLS = {
	update_project_context = true,
	get_project_context = true,
	discover_project = true,
	validate_context = true,
}

--============================================================
-- MAIN EXECUTE FUNCTION
--============================================================

--- Execute a tool call
--- @param toolName string
--- @param args table
--- @return table result
function ToolExecutor.execute(toolName, args)
	if Constants.DEBUG then
		print(string.format("[Lux ToolExecutor] Executing: %s", toolName))
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

	-- Route to appropriate module
	local result
	if READ_TOOLS[toolName] then
		result = ReadTools.execute(toolName, args)
	elseif WRITE_TOOLS[toolName] then
		result = WriteTools.execute(toolName, args, ApprovalQueue, ContextSelector)
	elseif PROJECT_TOOLS[toolName] then
		result = ProjectTools.execute(toolName, args)
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
-- OPERATION MANAGEMENT
--============================================================

--- Apply a pending operation
--- @param operationId number
--- @return table result
function ToolExecutor.applyOperation(operationId)
	local operation = ApprovalQueue.get(operationId)

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
	local stats = ApprovalQueue.getStats()
	local age = tick() - operation.timestamp
	if age > stats.ttl then
		operation.status = "expired"
		return {
			error = string.format("Operation expired (%.0f seconds old). Please retry the operation.", age)
		}
	end

	-- Mark as approved first
	ApprovalQueue.approve(operationId)

	-- Apply based on type
	local result = WriteTools.apply(operation.type, operation.data)

	if result.error then
		if Constants.DEBUG then
			print(string.format("[Lux ToolExecutor] Failed to apply operation #%d: %s", operation.id, result.error))
		end
	elseif Constants.DEBUG then
		print(string.format("[Lux ToolExecutor] Applied operation #%d: %s", operation.id, operation.type))
	end

	return result
end

--- Reject a pending operation
--- @param operationId number
--- @return table result
function ToolExecutor.rejectOperation(operationId)
	local success = ApprovalQueue.reject(operationId)
	if not success then
		return {
			error = "Operation not found: " .. tostring(operationId)
		}
	end
	return {}
end

--============================================================
-- TOOL DISPLAY FORMATTING (for user-friendly output)
--============================================================

--- Format tool call intent for display
--- @param toolName string
--- @param args table
--- @return string - Human-readable description of what the tool will do
function ToolExecutor.formatToolIntent(toolName, args)
	local intent = ""

	if toolName == "get_script" then
		intent = string.format("📖 Reading script: `%s`", args.path or "?")

	elseif toolName == "patch_script" then
		local searchPreview = (args.search_content or ""):sub(1, 50):gsub("\n", "↵")
		if #(args.search_content or "") > 50 then searchPreview = searchPreview .. "..." end
		intent = string.format("🔧 Patching `%s`\n🔍 Finding: `%s`", args.path or "?", searchPreview)

	elseif toolName == "edit_script" then
		intent = string.format("✏️ Rewriting `%s`\n📝 Reason: %s", args.path or "?", args.explanation or "No explanation")

	elseif toolName == "create_script" then
		intent = string.format("➕ Creating %s: `%s`\n📝 Purpose: %s",
			args.scriptType or "Script", args.path or "?", args.purpose or "No purpose specified")

	elseif toolName == "create_instance" then
		local propsStr = ""
		if args.properties and next(args.properties) then
			local propList = {}
			for k, v in pairs(args.properties) do
				table.insert(propList, string.format("%s=%s", k, tostring(v):sub(1,20)))
			end
			propsStr = "\n🎨 Properties: " .. table.concat(propList, ", "):sub(1, 80)
		end
		intent = string.format("➕ Creating %s `%s` in `%s`%s",
			args.className or "Instance", args.name or "?", args.parent or "?", propsStr)

	elseif toolName == "set_instance_properties" then
		local propList = {}
		if args.properties then
			for k, v in pairs(args.properties) do
				table.insert(propList, string.format("%s=%s", k, tostring(v):sub(1,20)))
			end
		end
		intent = string.format("🎨 Modifying `%s`\n⚙️ Setting: %s",
			args.path or "?", table.concat(propList, ", "):sub(1, 80))

	elseif toolName == "delete_instance" then
		intent = string.format("🗑️ Deleting `%s`", args.path or "?")

	elseif toolName == "get_instance" then
		intent = string.format("🔍 Inspecting `%s`", args.path or "?")

	elseif toolName == "list_children" then
		local filter = args.classFilter and (" (filter: " .. args.classFilter .. ")") or ""
		intent = string.format("📋 Listing children of `%s`%s", args.path or "?", filter)

	elseif toolName == "get_descendants_tree" then
		intent = string.format("🌳 Mapping structure of `%s` (depth: %d)", args.path or "?", args.maxDepth or 3)

	elseif toolName == "search_scripts" then
		intent = string.format("🔍 Searching scripts for: `%s`", (args.query or ""):sub(1, 50))

	elseif toolName == "update_project_context" then
		intent = string.format("💾 Saving %s context: %s", args.contextType or "?", (args.content or ""):sub(1, 50))

	elseif toolName == "get_project_context" then
		intent = "📚 Loading project context"

	elseif toolName == "discover_project" then
		intent = "🔎 Discovering project structure"

	elseif toolName == "validate_context" then
		intent = "✅ Validating saved context"

	elseif toolName == "web_fetch" then
		intent = string.format("🌐 Fetching URL: %s", (args.url or ""):sub(1, 60))

	else
		intent = string.format("🔧 %s", toolName)
	end

	return intent
end

--- Format tool result for display
--- @param toolName string
--- @param result table
--- @return string - Human-readable description of the result
function ToolExecutor.formatToolResult(toolName, result)
	if result.error then
		return string.format("❌ Error: %s", result.error)
	end

	local output = ""

	if toolName == "get_script" then
		output = string.format("✅ Read %d lines from `%s`", result.lineCount or 0, result.path or "?")

	elseif toolName == "patch_script" then
		if result.pending then
			output = string.format("⏳ Awaiting approval for patch to `%s`", result.message or "")
		else
			output = string.format("✅ Patched lines %s in `%s`", result.patchedLines or "?", result.path or "?")
		end

	elseif toolName == "edit_script" then
		if result.pending then
			output = string.format("⏳ %s", result.message or "Awaiting approval")
		else
			output = string.format("✅ Rewrote `%s` (%d lines changed)", result.path or "?", result.linesChanged or 0)
		end

	elseif toolName == "create_script" then
		if result.pending then
			output = string.format("⏳ %s", result.message or "Awaiting approval")
		else
			output = string.format("✅ Created `%s` (%d lines)", result.path or "?", result.lineCount or 0)
		end

	elseif toolName == "create_instance" then
		if result.pending then
			output = string.format("⏳ %s", result.message or "Awaiting approval")
		else
			local propsInfo = ""
			if result.propertiesApplied and #result.propertiesApplied > 0 then
				propsInfo = string.format("\n✅ Applied: %s", table.concat(result.propertiesApplied, ", "))
			end
			if result.propertyErrors and #result.propertyErrors > 0 then
				propsInfo = propsInfo .. string.format("\n⚠️ Failed: %d properties", #result.propertyErrors)
			end
			output = string.format("✅ Created `%s`%s", result.path or "?", propsInfo)
			if result.warning then
				output = output .. "\n⚠️ " .. result.warning
			end
		end

	elseif toolName == "set_instance_properties" then
		if result.pending then
			output = string.format("⏳ %s", result.message or "Awaiting approval")
		else
			local changes = result.propertiesChanged and table.concat(result.propertiesChanged, ", ") or "none"
			output = string.format("✅ Modified `%s` [%s]", result.path or "?", changes)
		end

	elseif toolName == "delete_instance" then
		if result.pending then
			output = string.format("⏳ %s", result.message or "Awaiting approval")
		else
			output = string.format("✅ Deleted `%s`", result.deleted or "?")
		end

	elseif toolName == "get_instance" then
		output = string.format("✅ Found %s `%s` (%d children)",
			result.className or "Instance", result.path or "?", result.childCount or 0)

	elseif toolName == "list_children" then
		output = string.format("✅ Found %d children in `%s`", result.childCount or 0, result.path or "?")

	elseif toolName == "get_descendants_tree" then
		output = string.format("✅ Mapped `%s` hierarchy", result.path or "?")

	elseif toolName == "search_scripts" then
		output = string.format("✅ Found %d matches for `%s`", result.count or 0, result.query or "?")

	elseif toolName == "update_project_context" then
		output = "✅ Context saved"

	elseif toolName == "get_project_context" then
		if result.hasContext then
			output = string.format("✅ Loaded %d context entries", result.entries and #result.entries or 0)
		else
			output = "ℹ️ No project context found"
		end

	elseif toolName == "discover_project" then
		output = string.format("✅ Found %d scripts", result.scriptCount or 0)

	elseif toolName == "validate_context" then
		output = string.format("✅ %d valid, %d stale entries", result.validEntries or 0, result.staleEntries or 0)

	elseif toolName == "web_fetch" then
		output = string.format("✅ Fetched %d bytes from %s", result.length or 0, result.url or "?")

	else
		output = "✅ Complete"
	end

	return output
end

return ToolExecutor
