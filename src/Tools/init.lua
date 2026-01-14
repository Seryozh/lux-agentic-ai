--[[
	Tools/init.lua
	Main entry point for the Tools system

	Exports the split module structure:
	- execute: Main tool execution router
	- applyOperation: Apply a pending operation
	- rejectOperation: Reject a pending operation
	- getPendingOperations: Get all pending operations
	- clearPendingOperations: Clear all pending operations
	- formatToolIntent: Format tool call for display
	- formatToolResult: Format tool result for display
	- getDefinitions: Get tool definitions (imported from ToolDefinitions)

	Architecture:
	- ToolExecutor: Main router and coordinator
	- ReadTools: Read-only operations
	- WriteTools: Write/modify operations (queued for approval)
	- ProjectTools: Project context management
	- ApprovalQueue: Pending operation management

	Creator Store Compliant - No dynamic code execution
]]

local ToolExecutor = require(script.Parent.ToolExecutor)
local ApprovalQueue = require(script.Parent.ApprovalQueue)
local ToolDefinitions = require(script.Parent.ToolDefinitions)

local Tools = {}

--============================================================
-- CORE TOOL EXECUTION
--============================================================

--- Execute a tool call
--- @param toolName string
--- @param args table
--- @return table result
function Tools.execute(toolName, args)
	return ToolExecutor.execute(toolName, args)
end

--============================================================
-- OPERATION MANAGEMENT
--============================================================

--- Get all pending operations
--- @return table - Array of pending operations
function Tools.getPendingOperations()
	return ApprovalQueue.getAll()
end

--- Apply a pending operation
--- @param operationId number
--- @return table result
function Tools.applyOperation(operationId)
	return ToolExecutor.applyOperation(operationId)
end

--- Reject a pending operation
--- @param operationId number
--- @return table result
function Tools.rejectOperation(operationId)
	return ToolExecutor.rejectOperation(operationId)
end

--- Clear all pending operations
--- @return number count - Number of operations cleared
function Tools.clearPendingOperations()
	return ApprovalQueue.clear()
end

--============================================================
-- TOOL FORMATTING
--============================================================

--- Format tool call intent for display
--- @param toolName string
--- @param args table
--- @return string - Human-readable description of what the tool will do
function Tools.formatToolIntent(toolName, args)
	return ToolExecutor.formatToolIntent(toolName, args)
end

--- Format tool result for display
--- @param toolName string
--- @param result table
--- @return string - Human-readable description of the result
function Tools.formatToolResult(toolName, result)
	return ToolExecutor.formatToolResult(toolName, result)
end

--============================================================
-- TOOL DEFINITIONS
--============================================================

--- Get tool definitions for API declaration
--- @return table - Array of tool definitions
function Tools.getDefinitions()
	return ToolDefinitions
end

return Tools
