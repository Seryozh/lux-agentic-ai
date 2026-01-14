--[[
    SessionManager.lua
    Lifecycle coordination for all modules

    Manages state across three scopes:
    1. PERSISTED - Survives session restart (ProjectContext, DecisionMemory)
    2. SESSION-SCOPED - Cleared on conversation reset
    3. TASK-SCOPED - Cleared on each new user message

    This prevents state leaks and ensures coordinated initialization/cleanup.
    
    Creator Store Compliant - Uses only static module references
]]

local Constants = require(script.Parent.Parent.Shared.Constants)

-- ============================================================================
-- MODULE REFERENCES (static requires for Creator Store compliance)
-- ============================================================================

-- Core modules (always available)
local ErrorAnalyzer = require(script.Parent.Parent.Safety.ErrorAnalyzer)
local TaskPlanner = require(script.Parent.Parent.Planning.TaskPlanner)
local ContextSelector = require(script.Parent.Parent.Context.ContextSelector)
local ProjectContext = require(script.Parent.Parent.Memory.ProjectContext)
local DecisionMemory = require(script.Parent.Parent.Memory.DecisionMemory)

-- Safety modules (v2.0)
local CircuitBreaker = require(script.Parent.Parent.Safety.CircuitBreaker)
local OutputValidator = require(script.Parent.Parent.Safety.OutputValidator)
local ErrorPredictor = require(script.Parent.Parent.Safety.ErrorPredictor)
local WorkingMemory = require(script.Parent.Parent.Memory.WorkingMemory)

local SessionManager = {}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
	conversationActive = false,
	currentTaskId = nil,
	taskStartTime = nil,
	conversationStartTime = nil,
	taskCount = 0,
}

-- ============================================================================
-- CONVERSATION LIFECYCLE
-- ============================================================================

--[[
    Called when a NEW CONVERSATION starts (full reset)
    @return table - Initialization summary
]]
function SessionManager.onConversationStart()
	state.conversationActive = true
	state.conversationStartTime = tick()
	state.taskCount = 0

	-- Clear all transient state
	if ErrorAnalyzer and ErrorAnalyzer.clearHistory then 
		ErrorAnalyzer.clearHistory() 
	end

	if TaskPlanner and TaskPlanner.resetSession then 
		TaskPlanner.resetSession() 
	end

	if ContextSelector and ContextSelector.clearCache then 
		ContextSelector.clearCache() 
	end

	if WorkingMemory and WorkingMemory.clear then 
		WorkingMemory.clear() 
	end

	if CircuitBreaker and CircuitBreaker.forceReset then 
		CircuitBreaker.forceReset() 
	end

	if ErrorPredictor and ErrorPredictor.reset then 
		ErrorPredictor.reset() 
	end

	-- Load persisted knowledge
	local contextResult = nil
	if ProjectContext then
		ProjectContext.load()
		contextResult = ProjectContext.validateAll()
	end

	local patternCount = 0
	if DecisionMemory then
		DecisionMemory.load()
		local stats = DecisionMemory.getStatistics()
		patternCount = stats.totalPatterns or 0
	end

	if Constants.DEBUG then
		print(string.format(
			"[SessionManager] Conversation started. Context: %d valid, %d stale. Patterns: %d",
			contextResult and contextResult.valid or 0,
			contextResult and contextResult.stale or 0,
			patternCount
			))
	end

	return {
		contextValid = contextResult and contextResult.valid or 0,
		contextStale = contextResult and contextResult.stale or 0,
		patternsLoaded = patternCount
	}
end

--[[
    Called when a NEW TASK starts (new user message in same conversation)
    @param userMessage string
    @return table - Task analysis
]]
function SessionManager.onNewTask(userMessage)
	state.taskCount = state.taskCount + 1
	state.currentTaskId = tostring(tick()) .. "_" .. state.taskCount
	state.taskStartTime = tick()

	-- Clear task-specific transient state
	if ErrorAnalyzer and ErrorAnalyzer.onNewTask then 
		ErrorAnalyzer.onNewTask(state.currentTaskId) 
	end

	if TaskPlanner and TaskPlanner.onNewTask then 
		TaskPlanner.onNewTask() 
	end

	if CircuitBreaker and CircuitBreaker.forceReset then 
		CircuitBreaker.forceReset() 
	end

	-- Mark all script reads as stale for new tasks
	if ErrorPredictor and ErrorPredictor.markAllStale then 
		ErrorPredictor.markAllStale() 
	end

	if ContextSelector and ContextSelector.reset then 
		ContextSelector.reset() 
	end

	-- Archive previous goal and set new one
	if WorkingMemory and WorkingMemory.archiveCurrentGoal then
		WorkingMemory.archiveCurrentGoal()
	end

	-- Analyze the new task
	local analysis = nil
	if TaskPlanner and TaskPlanner.analyzeTask then
		analysis = TaskPlanner.analyzeTask(userMessage)
	end

	-- Set intent for persistence
	if TaskPlanner and TaskPlanner.setIntent and analysis then
		TaskPlanner.setIntent(userMessage, analysis)
	end

	-- Set goal in working memory
	if WorkingMemory and WorkingMemory.setGoal then
		WorkingMemory.setGoal(userMessage, analysis)
	end

	-- Start recording for DecisionMemory
	if DecisionMemory and DecisionMemory.startSequence then
		DecisionMemory.startSequence(userMessage, analysis)
	end

	if Constants.DEBUG then
		print(string.format(
			"[SessionManager] New task #%d: %s (complexity: %s)",
			state.taskCount,
			userMessage:sub(1, 40),
			analysis and analysis.complexity or "unknown"
			))
	end

	return analysis or {
		complexity = "unknown",
		estimatedSteps = 0,
		capabilities = {},
		shouldPlan = false
	}
end

--[[
    Called when a task COMPLETES (success or explicit failure)
    @param success boolean
    @param summary string|nil
]]
function SessionManager.onTaskComplete(success, summary)
	-- Record outcome in DecisionMemory
	if DecisionMemory and DecisionMemory.endSequence then
		DecisionMemory.endSequence(success, summary)
	end

	-- Clear task-specific state
	if ErrorAnalyzer and ErrorAnalyzer.pruneStaleErrors then 
		ErrorAnalyzer.pruneStaleErrors() 
	end

	-- Record completion in working memory
	if WorkingMemory and WorkingMemory.add then
		WorkingMemory.add("decision",
			string.format("Task %s: %s",
				success and "completed" or "failed",
				summary or state.currentTaskId
			),
			{ success = success, taskId = state.currentTaskId }
		)
	end

	local duration = tick() - (state.taskStartTime or tick())

	if Constants.DEBUG then
		print(string.format(
			"[SessionManager] Task #%d completed: %s (%.1fs)",
			state.taskCount,
			success and "SUCCESS" or "FAILED",
			duration
			))
	end

	state.currentTaskId = nil
	state.taskStartTime = nil
end

--[[
    Called when CONVERSATION ends (plugin unload or explicit reset)
]]
function SessionManager.onConversationEnd()
	-- Save any pending state
	if ProjectContext and ProjectContext.save then 
		ProjectContext.save() 
	end

	if DecisionMemory and DecisionMemory.save then 
		DecisionMemory.save() 
	end

	-- Clear session state
	if WorkingMemory and WorkingMemory.clear then 
		WorkingMemory.clear() 
	end

	if ErrorAnalyzer and ErrorAnalyzer.clearHistory then 
		ErrorAnalyzer.clearHistory() 
	end

	if TaskPlanner and TaskPlanner.resetSession then 
		TaskPlanner.resetSession() 
	end

	if ErrorPredictor and ErrorPredictor.reset then 
		ErrorPredictor.reset() 
	end

	state.conversationActive = false

	if Constants.DEBUG then
		print(string.format(
			"[SessionManager] Conversation ended after %d tasks",
			state.taskCount
			))
	end
end

-- ============================================================================
-- SCRIPT MODIFICATION EVENTS
-- ============================================================================

--[[
    Called when a SCRIPT is modified (by any tool)
    @param path string
]]
function SessionManager.onScriptModified(path)
	-- Invalidate caches
	if ContextSelector then
		if ContextSelector.invalidateCache then
			ContextSelector.invalidateCache(path)
		end
		if ContextSelector.markEdited then
			ContextSelector.markEdited(path)
		end
	end

	-- Track modification for freshness (both ErrorPredictor and ContextSelector)
	if ErrorPredictor and ErrorPredictor.recordScriptModified then
		ErrorPredictor.recordScriptModified(path)
	end
	if ContextSelector and ContextSelector.recordModified then
		ContextSelector.recordModified(path)
	end

	-- Cascade context invalidation
	if ProjectContext and ProjectContext.cascadeInvalidation then
		ProjectContext.cascadeInvalidation(path)
	end

	-- Add to working memory
	if WorkingMemory and WorkingMemory.add then
		WorkingMemory.add("tool_result",
			"Modified: " .. path,
			{ path = path, action = "modified" }
		)
	end

	if Constants.DEBUG then
		print(string.format("[SessionManager] Script modified: %s", path))
	end
end

--[[
    Called when a SCRIPT is read
    @param path string
    @param content string|nil
]]
function SessionManager.onScriptRead(path, content)
	-- Track read time for freshness (both ErrorPredictor and ContextSelector)
	if ErrorPredictor and ErrorPredictor.recordScriptRead then
		ErrorPredictor.recordScriptRead(path)
	end
	if ContextSelector and ContextSelector.recordRead then
		ContextSelector.recordRead(path)
	end

	-- Add to working memory
	if WorkingMemory and WorkingMemory.add then
		local lineCount = content and select(2, content:gsub("\n", "")) + 1 or 0
		WorkingMemory.add("script_read",
			string.format("Read %s (%d lines)", path, lineCount),
			{ path = path, lineCount = lineCount },
			{ path = path }
		)
	end
end

--[[
    Called when an INSTANCE is inspected
    @param path string
]]
function SessionManager.onInstanceInspected(path)
	if ErrorPredictor and ErrorPredictor.recordScriptRead then
		ErrorPredictor.recordScriptRead(path)  -- Same tracking for instances
	end
end

-- ============================================================================
-- TOOL EXECUTION EVENTS
-- ============================================================================

--[[
    Called BEFORE a tool executes
    @param toolName string
    @param args table
    @return boolean, string|nil - canProceed, warning
]]
function SessionManager.beforeToolExecution(toolName, args)
	-- Check circuit breaker
	if CircuitBreaker and CircuitBreaker.canProceed then
		local canProceed, warning = CircuitBreaker.canProceed()
		if not canProceed then
			return false, warning
		end
	end

	-- Check output validator
	if OutputValidator and OutputValidator.validateToolCall then
		local validation = OutputValidator.validateToolCall({ name = toolName, args = args })
		if not validation.valid then
			local formatted = OutputValidator.formatForLLM and OutputValidator.formatForLLM(validation) or "Validation failed"
			return false, formatted
		end
	end

	-- Check error predictor (warnings only, doesn't block)
	if ErrorPredictor and ErrorPredictor.canProceed then
		local canProceed, warning = ErrorPredictor.canProceed(toolName, args)
		if warning then
			-- Return warning but allow proceed
			return true, warning
		end
	end

	return true, nil
end

--[[
    Called AFTER a tool executes
    @param toolName string
    @param args table
    @param success boolean
    @param result any
]]
function SessionManager.afterToolExecution(toolName, args, success, result)
	-- Record with circuit breaker
	if CircuitBreaker then
		if success then
			if CircuitBreaker.recordSuccess then
				CircuitBreaker.recordSuccess()
			end
		else
			local errorMsg = type(result) == "table" and result.error or tostring(result)
			if CircuitBreaker.recordFailure then
				CircuitBreaker.recordFailure(toolName, errorMsg or "Unknown error")
			end
		end
	end

	-- Record with error predictor
	if ErrorPredictor and not success and ErrorPredictor.recordFailure then
		local errorMsg = type(result) == "table" and result.error or tostring(result)
		ErrorPredictor.recordFailure(toolName, args, errorMsg or "Unknown error")
	end

	-- Record with decision memory
	if DecisionMemory and DecisionMemory.recordTool then
		local summary = success
			and (type(result) == "table" and result.message or "Success")
			or (type(result) == "table" and result.error or "Failed")
		DecisionMemory.recordTool(toolName, success, summary)
	end

	-- Add to working memory
	if WorkingMemory and WorkingMemory.add then
		local summary = string.format("%s %s: %s",
			success and "?" or "?",
			toolName,
			args.path or args.pattern or "operation"
		)
		WorkingMemory.add("tool_result", summary:sub(1, 100), {
			tool = toolName,
			success = success
		})
	end

	-- Handle script-specific events
	if success then
		if toolName == "patch_script" or toolName == "edit_script" or toolName == "create_script" then
			SessionManager.onScriptModified(args.path)
		elseif toolName == "get_script" then
			local content = type(result) == "table" and result.source or nil
			SessionManager.onScriptRead(args.path, content)
		elseif toolName == "get_instance" or toolName == "list_children" then
			SessionManager.onInstanceInspected(args.path)
		end
	end
end

-- ============================================================================
-- STATE QUERIES
-- ============================================================================

--[[
    Get current session state
    @return table
]]
function SessionManager.getState()
	return {
		conversationActive = state.conversationActive,
		currentTaskId = state.currentTaskId,
		taskCount = state.taskCount,
		sessionDuration = state.conversationStartTime
			and (tick() - state.conversationStartTime)
			or 0,
		taskDuration = state.taskStartTime
			and (tick() - state.taskStartTime)
			or 0
	}
end

--[[
    Check if a conversation is active
    @return boolean
]]
function SessionManager.isConversationActive()
	return state.conversationActive
end

--[[
    Get current task ID
    @return string|nil
]]
function SessionManager.getCurrentTaskId()
	return state.currentTaskId
end

return SessionManager
