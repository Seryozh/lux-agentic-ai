--[[
    TaskPlanner.lua
    Intelligent task analysis, planning, and self-reflection system
    
    This module adds "thinking before acting" to the agentic loop:
    1. Analyzes user requests to understand complexity
    2. Creates execution plans for complex tasks
    3. Triggers self-reflection at key checkpoints
    4. Tracks progress against planned goals
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local HttpService = game:GetService("HttpService")

local TaskPlanner = {}

-- ============================================================================
-- STATE
-- ============================================================================

local currentPlan = nil
local reflectionDue = false
local toolCallsSinceReflection = 0
local recentFailures = {}
local sessionHistory = {} -- Track high-level actions this session

-- ============================================================================
-- TASK COMPLEXITY ANALYSIS
-- ============================================================================

-- Keywords that indicate different complexities
local COMPLEXITY_INDICATORS = {
	simple = {
		keywords = { "change", "fix", "update", "set", "get", "read", "check", "look" },
		patterns = { "^change%s+the", "^fix%s+the", "^what%s+is", "^show%s+me" }
	},
	medium = {
		keywords = { "add", "create", "make", "build", "implement", "modify" },
		patterns = { "^add%s+a", "^create%s+a", "^make%s+a" }
	},
	complex = {
		keywords = { "system", "complete", "full", "entire", "refactor", "redesign", "integrate" },
		patterns = { "with%s+.+%s+and%s+.+%s+and", "complete%s+.+%s+system", "refactor%s+all" }
	}
}

-- Capabilities required for different task types
local CAPABILITY_DETECTION = {
	{ pattern = "script", capability = "script_editing" },
	{ pattern = "code", capability = "script_editing" },
	{ pattern = "function", capability = "script_editing" },
	{ pattern = "gui", capability = "ui_creation" },
	{ pattern = "ui", capability = "ui_creation" },
	{ pattern = "button", capability = "ui_creation" },
	{ pattern = "frame", capability = "ui_creation" },
	{ pattern = "part", capability = "instance_creation" },
	{ pattern = "model", capability = "instance_creation" },
	{ pattern = "data", capability = "data_management" },
	{ pattern = "save", capability = "data_management" },
	{ pattern = "load", capability = "data_management" },
	{ pattern = "remote", capability = "networking" },
	{ pattern = "server", capability = "networking" },
	{ pattern = "client", capability = "networking" },
}

--[[
    Analyze a user message to determine task complexity and requirements
    @param message string - User's request
    @return table - Analysis result
]]
function TaskPlanner.analyzeTask(message)
	if not Constants.PLANNING.enabled then
		return {
			complexity = "unknown",
			estimatedSteps = 0,
			capabilities = {},
			shouldPlan = false
		}
	end

	local lowerMessage = message:lower()
	local analysis = {
		complexity = "simple",
		estimatedSteps = 1,
		capabilities = {},
		shouldPlan = false,
		riskLevel = "low",
		suggestedApproach = nil
	}

	-- Detect required capabilities
	local capabilitySet = {}
	for _, detector in ipairs(CAPABILITY_DETECTION) do
		if lowerMessage:find(detector.pattern) then
			capabilitySet[detector.capability] = true
		end
	end
	for cap in pairs(capabilitySet) do
		table.insert(analysis.capabilities, cap)
	end

	-- Score complexity based on indicators
	local complexityScore = 0

	-- Check simple indicators (negative score)
	for _, keyword in ipairs(COMPLEXITY_INDICATORS.simple.keywords) do
		if lowerMessage:find(keyword) then
			complexityScore = complexityScore - 1
		end
	end
	for _, pattern in ipairs(COMPLEXITY_INDICATORS.simple.patterns) do
		if lowerMessage:match(pattern) then
			complexityScore = complexityScore - 2
		end
	end

	-- Check medium indicators
	for _, keyword in ipairs(COMPLEXITY_INDICATORS.medium.keywords) do
		if lowerMessage:find(keyword) then
			complexityScore = complexityScore + 1
		end
	end
	for _, pattern in ipairs(COMPLEXITY_INDICATORS.medium.patterns) do
		if lowerMessage:match(pattern) then
			complexityScore = complexityScore + 2
		end
	end

	-- Check complex indicators
	for _, keyword in ipairs(COMPLEXITY_INDICATORS.complex.keywords) do
		if lowerMessage:find(keyword) then
			complexityScore = complexityScore + 3
		end
	end
	for _, pattern in ipairs(COMPLEXITY_INDICATORS.complex.patterns) do
		if lowerMessage:match(pattern) then
			complexityScore = complexityScore + 5
		end
	end

	-- Factor in number of capabilities
	complexityScore = complexityScore + (#analysis.capabilities * 2)

	-- Determine complexity level
	if complexityScore <= Constants.PLANNING.complexityThresholds.simple then
		analysis.complexity = "simple"
		analysis.estimatedSteps = math.max(1, math.min(2, complexityScore + 2))
	elseif complexityScore <= Constants.PLANNING.complexityThresholds.medium then
		analysis.complexity = "medium"
		analysis.estimatedSteps = math.max(3, math.min(5, math.floor(complexityScore / 2)))
	else
		analysis.complexity = "complex"
		analysis.estimatedSteps = math.max(6, math.min(Constants.PLANNING.maxPlanSteps, math.floor(complexityScore / 2)))
	end

	-- Should we create a detailed plan?
	analysis.shouldPlan = analysis.complexity ~= "simple"

	-- Risk assessment
	if lowerMessage:find("delete") or lowerMessage:find("remove") or lowerMessage:find("destroy") then
		analysis.riskLevel = "high"
	elseif lowerMessage:find("edit") or lowerMessage:find("modify") or lowerMessage:find("change") then
		analysis.riskLevel = "medium"
	end

	-- Suggest approach based on analysis
	if analysis.complexity == "complex" then
		analysis.suggestedApproach = "Break this into phases: 1) Understand existing code, 2) Plan changes, 3) Implement incrementally, 4) Verify each step"
	elseif analysis.complexity == "medium" then
		analysis.suggestedApproach = "Read relevant code first, then implement with verification"
	else
		analysis.suggestedApproach = "Direct implementation with verification"
	end

	if Constants.DEBUG then
		print(string.format("[TaskPlanner] Analysis: complexity=%s, steps=%d, capabilities=%s, shouldPlan=%s",
			analysis.complexity,
			analysis.estimatedSteps,
			table.concat(analysis.capabilities, ","),
			tostring(analysis.shouldPlan)
			))
	end

	return analysis
end

-- ============================================================================
-- PLANNING
-- ============================================================================

--[[
    Create an execution plan for a task
    @param message string - User's request
    @param analysis table - Result from analyzeTask
    @return table - Execution plan
]]
function TaskPlanner.createPlan(message, analysis)
	if not analysis.shouldPlan then
		return nil
	end

	local plan = {
		id = HttpService:GenerateGUID(false),
		originalRequest = message,
		complexity = analysis.complexity,
		estimatedSteps = analysis.estimatedSteps,
		capabilities = analysis.capabilities,
		phases = {},
		currentPhase = 1,
		currentStep = 0,
		status = "pending", -- pending, in_progress, completed, failed
		createdAt = tick(),
		completedSteps = {},
		failedSteps = {}
	}

	-- Generate phases based on capabilities
	local phaseOrder = {
		{ cap = "script_editing", phase = "understanding", description = "Read and understand existing code" },
		{ cap = "ui_creation", phase = "structure", description = "Create UI structure (containers first)" },
		{ cap = "instance_creation", phase = "creation", description = "Create required instances" },
		{ cap = "data_management", phase = "data_layer", description = "Set up data handling" },
		{ cap = "networking", phase = "networking", description = "Implement client-server communication" },
	}

	-- Always start with understanding
	table.insert(plan.phases, {
		name = "understanding",
		description = "Understand the current state",
		status = "pending",
		steps = { "Inspect relevant instances", "Read related scripts if any" }
	})

	-- Add phases based on detected capabilities
	local addedPhases = { understanding = true }
	for _, capability in ipairs(analysis.capabilities) do
		for _, phaseInfo in ipairs(phaseOrder) do
			if phaseInfo.cap == capability and not addedPhases[phaseInfo.phase] then
				table.insert(plan.phases, {
					name = phaseInfo.phase,
					description = phaseInfo.description,
					status = "pending",
					steps = {}
				})
				addedPhases[phaseInfo.phase] = true
			end
		end
	end

	-- Always end with verification
	table.insert(plan.phases, {
		name = "verification",
		description = "Verify all changes work correctly",
		status = "pending",
		steps = { "Check created instances exist", "Verify script functionality" }
	})

	currentPlan = plan

	if Constants.DEBUG then
		print(string.format("[TaskPlanner] Created plan: %d phases, %d estimated steps",
			#plan.phases, plan.estimatedSteps))
	end

	return plan
end

--[[
    Update plan progress after a step completes
    @param stepDescription string - What was done
    @param success boolean - Whether it succeeded
]]
function TaskPlanner.recordStep(stepDescription, success)
	if not currentPlan then return end

	currentPlan.currentStep = currentPlan.currentStep + 1

	local stepRecord = {
		step = currentPlan.currentStep,
		description = stepDescription,
		success = success,
		timestamp = tick()
	}

	if success then
		table.insert(currentPlan.completedSteps, stepRecord)
	else
		table.insert(currentPlan.failedSteps, stepRecord)
	end

	-- Track in session history
	table.insert(sessionHistory, {
		action = stepDescription,
		success = success,
		timestamp = tick()
	})

	if Constants.DEBUG then
		print(string.format("[TaskPlanner] Step %d: %s (%s)",
			currentPlan.currentStep,
			stepDescription:sub(1, 50),
			success and "success" or "failed"
			))
	end
end

--[[
    Get current plan if any
    @return table|nil
]]
function TaskPlanner.getCurrentPlan()
	return currentPlan
end

--[[
    Clear current plan
]]
function TaskPlanner.clearPlan()
	if currentPlan then
		if Constants.DEBUG then
			print(string.format("[TaskPlanner] Plan cleared. Completed %d/%d steps",
				#currentPlan.completedSteps,
				currentPlan.currentStep
				))
		end
	end
	currentPlan = nil
end

-- ============================================================================
-- SELF-REFLECTION
-- ============================================================================

--[[
    Check if reflection is due
    @return boolean
]]
function TaskPlanner.isReflectionDue()
	if not Constants.PLANNING.enabled then
		return false
	end

	-- Reflection due if:
	-- 1. We've done N tool calls since last reflection
	-- 2. We just had a failure and reflectionOnFailure is enabled
	-- 3. Manually flagged

	if reflectionDue then
		return true
	end

	if toolCallsSinceReflection >= Constants.PLANNING.reflectionInterval then
		return true
	end

	return false
end

--[[
    Record that a tool was called
    @param toolName string
    @param success boolean
]]
function TaskPlanner.recordToolCall(toolName, success)
	toolCallsSinceReflection = toolCallsSinceReflection + 1

	if not success then
		table.insert(recentFailures, {
			tool = toolName,
			timestamp = tick()
		})

		-- Purge old failures (older than 60 seconds)
		local now = tick()
		local fresh = {}
		for _, failure in ipairs(recentFailures) do
			if now - failure.timestamp < 60 then
				table.insert(fresh, failure)
			end
		end
		recentFailures = fresh

		-- Flag for reflection if enabled
		if Constants.PLANNING.reflectionOnFailure then
			reflectionDue = true
		end
	end
end

--[[
    Acknowledge that reflection was done
]]
function TaskPlanner.reflectionCompleted()
	reflectionDue = false
	toolCallsSinceReflection = 0

	if Constants.DEBUG then
		print("[TaskPlanner] Reflection completed, counters reset")
	end
end

--[[
    Generate a reflection prompt to inject into conversation
    @return string - Reflection guidance for the LLM
]]
function TaskPlanner.generateReflectionPrompt()
	local parts = { "\n[REFLECTION CHECKPOINT]\n" }

	-- Current plan status
	if currentPlan then
		table.insert(parts, string.format(
			"?? Plan Progress: Phase %d/%d, Step %d\n",
			currentPlan.currentPhase,
			#currentPlan.phases,
			currentPlan.currentStep
			))

		if #currentPlan.failedSteps > 0 then
			table.insert(parts, string.format(
				"?? Failed steps: %d\n",
				#currentPlan.failedSteps
				))
		end
	end

	-- Recent failures
	if #recentFailures > 0 then
		table.insert(parts, string.format(
			"? Recent failures (%d in last minute). Consider:\n",
			#recentFailures
			))
		table.insert(parts, "- Is the approach working?\n")
		table.insert(parts, "- Should you re-read code/structure?\n")
		table.insert(parts, "- Is there a simpler alternative?\n")
	end

	-- Reflection questions
	table.insert(parts, "\nBefore continuing, briefly assess:\n")
	table.insert(parts, "1. Are my recent actions moving toward the goal?\n")
	table.insert(parts, "2. Have I encountered unexpected obstacles?\n")
	table.insert(parts, "3. Should I adjust my approach?\n")

	return table.concat(parts)
end

-- ============================================================================
-- SESSION HISTORY
-- ============================================================================

--[[
    Get session history summary
    @return table
]]
function TaskPlanner.getSessionSummary()
	local summary = {
		totalActions = #sessionHistory,
		successes = 0,
		failures = 0,
		recentActions = {}
	}

	for i, action in ipairs(sessionHistory) do
		if action.success then
			summary.successes = summary.successes + 1
		else
			summary.failures = summary.failures + 1
		end

		-- Include last 10 actions in summary
		if i > #sessionHistory - 10 then
			table.insert(summary.recentActions, action)
		end
	end

	return summary
end

--[[
    Format session history for prompt inclusion
    @return string
]]
function TaskPlanner.formatSessionHistoryForPrompt()
	if not Constants.ADAPTIVE_PROMPT.includeSessionHistory then
		return ""
	end

	local summary = TaskPlanner.getSessionSummary()

	if summary.totalActions == 0 then
		return ""
	end

	local parts = { "\n## Session History\n" }
	table.insert(parts, string.format(
		"Actions this session: %d (%d successful, %d failed)\n",
		summary.totalActions, summary.successes, summary.failures
		))

	if #summary.recentActions > 0 then
		table.insert(parts, "\nRecent actions:\n")
		for _, action in ipairs(summary.recentActions) do
			local icon = action.success and "?" or "?"
			table.insert(parts, string.format("- %s %s\n", icon, action.action:sub(1, 60)))
		end
	end

	return table.concat(parts)
end

--[[
    Get recent failures count (for adaptive prompt)
    @return number
]]
function TaskPlanner.getRecentFailureCount()
	return #recentFailures
end

--[[
    Reset session state (on conversation reset)
]]
function TaskPlanner.resetSession()
	currentPlan = nil
	reflectionDue = false
	toolCallsSinceReflection = 0
	recentFailures = {}
	sessionHistory = {}

	if Constants.DEBUG then
		print("[TaskPlanner] Session state reset")
	end
end

--[[
    Called when a new task (user message) starts
    Clears transient state but preserves session history
]]
function TaskPlanner.onNewTask()
	-- Clear transient failure tracking (these are task-specific)
	recentFailures = {}
	reflectionDue = false
	toolCallsSinceReflection = 0

	-- Keep sessionHistory - it's useful for overall session context
	-- Keep currentPlan - it might be relevant if continuing similar work

	if Constants.DEBUG then
		print("[TaskPlanner] New task boundary - cleared transient state")
	end
end

-- ============================================================================
-- INTENT PERSISTENCE
-- ============================================================================

-- Active intent tracking
local activeIntent = nil

--[[
    Extract constraints from user message
    @param message string
    @return table - Array of constraint strings
]]
local function extractConstraints(message)
	local constraints = {}
	local lowerMessage = message:lower()

	-- Look for constraint patterns
	local constraintPatterns = {
		"without%s+breaking%s+([^,%.]+)",
		"without%s+changing%s+([^,%.]+)",
		"keep%s+([^,%.]+)%s+working",
		"don't%s+touch%s+([^,%.]+)",
		"don't%s+modify%s+([^,%.]+)",
		"preserve%s+([^,%.]+)",
		"maintain%s+([^,%.]+)",
	}

	for _, pattern in ipairs(constraintPatterns) do
		local match = lowerMessage:match(pattern)
		if type(match) == "string" then
			local trimmed = match:gsub("^%s+", ""):gsub("%s+$", "")
			table.insert(constraints, trimmed)
		end
	end

	return constraints
end

--[[
    Extract success criteria from user message
    @param message string
    @return table - Array of criteria strings
]]
local function extractSuccessCriteria(message)
	local criteria = {}
	local lowerMessage = message:lower()

	-- Look for success criteria patterns
	local criteriaPatterns = {
		"should%s+([^,%.]+)",
		"must%s+([^,%.]+)",
		"needs?%s+to%s+([^,%.]+)",
		"make%s+sure%s+([^,%.]+)",
		"ensure%s+([^,%.]+)",
	}

	for _, pattern in ipairs(criteriaPatterns) do
		-- Use string.match in a loop with position tracking instead of gmatch
		-- This avoids issues with gmatch returning unexpected values
		local searchStart = 1
		while searchStart <= #lowerMessage do
			local matchStart, matchEnd, capture = lowerMessage:find(pattern, searchStart)
			if not matchStart then
				break
			end
			-- Process the capture if valid
			if type(capture) == "string" and #capture > 5 then  -- Skip very short matches
				local trimmed = capture:gsub("^%s+", ""):gsub("%s+$", "")
				table.insert(criteria, trimmed)
			end
			-- Move past this match to find more
			searchStart = matchEnd + 1
		end
	end

	return criteria
end

--[[
    Set the active intent for the current task
    @param userMessage string
    @param analysis table - From analyzeTask
]]
function TaskPlanner.setIntent(userMessage, analysis)
	activeIntent = {
		original = userMessage,
		parsed = {
			action = analysis and analysis.suggestedApproach or nil,
			complexity = analysis and analysis.complexity or "unknown",
			capabilities = analysis and analysis.capabilities or {}
		},
		constraints = extractConstraints(userMessage),
		successCriteria = extractSuccessCriteria(userMessage),
		createdAt = tick(),
		attempts = 0,
		lastError = nil
	}

	if Constants.DEBUG then
		print(string.format("[TaskPlanner] Intent set: %s (constraints: %d, criteria: %d)",
			userMessage:sub(1, 40),
			#activeIntent.constraints,
			#activeIntent.successCriteria
			))
	end
end

--[[
    Get the current active intent
    @return table|nil
]]
function TaskPlanner.getIntent()
	return activeIntent
end

--[[
    Get a reminder of the original intent (for error recovery)
    @return string|nil
]]
function TaskPlanner.getIntentReminder()
	if not activeIntent then return nil end

	local parts = {
		string.format("?? REMINDER - Original goal: %s", activeIntent.original:sub(1, 150))
	}

	if activeIntent.attempts > 0 then
		table.insert(parts, string.format("Attempt #%d", activeIntent.attempts + 1))
	end

	if #activeIntent.constraints > 0 then
		table.insert(parts, "Constraints: " .. table.concat(activeIntent.constraints, ", "))
	end

	if #activeIntent.successCriteria > 0 then
		table.insert(parts, "Success criteria: " .. table.concat(activeIntent.successCriteria, "; "))
	end

	return table.concat(parts, "\n")
end

--[[
    Called when an error occurs during task execution
    @param errorMessage string
    @return table|nil - Reminder and suggestion if attempts are high
]]
function TaskPlanner.onError(errorMessage)
	if not activeIntent then return nil end

	activeIntent.attempts = activeIntent.attempts + 1
	activeIntent.lastError = errorMessage

	if activeIntent.attempts >= 3 then
		return {
			message = TaskPlanner.getIntentReminder(),
			suggestion = string.format(
				"After %d failed attempts, consider asking the user if the goal is still correct.",
				activeIntent.attempts
			),
			shouldAskUser = activeIntent.attempts >= 5
		}
	end

	return nil
end

--[[
    Mark intent as completed
    @param success boolean
    @param summary string|nil
]]
function TaskPlanner.completeIntent(success, summary)
	if activeIntent then
		activeIntent.completed = true
		activeIntent.success = success
		activeIntent.completedAt = tick()
		activeIntent.summary = summary

		if Constants.DEBUG then
			print(string.format("[TaskPlanner] Intent completed: %s (%d attempts)",
				success and "SUCCESS" or "FAILED",
				activeIntent.attempts
				))
		end
	end

	activeIntent = nil
end

--[[
    Format intent for inclusion in prompt
    @return string
]]
function TaskPlanner.formatIntentForPrompt()
	if not activeIntent then return "" end

	local parts = { "\n## ?? Current Task Intent\n" }

	table.insert(parts, string.format("**Goal:** %s", activeIntent.original:sub(1, 200)))

	if #activeIntent.constraints > 0 then
		table.insert(parts, "\n**Constraints:**")
		for _, constraint in ipairs(activeIntent.constraints) do
			table.insert(parts, "- " .. constraint)
		end
	end

	if #activeIntent.successCriteria > 0 then
		table.insert(parts, "\n**Success Criteria:**")
		for _, criterion in ipairs(activeIntent.successCriteria) do
			table.insert(parts, "- " .. criterion)
		end
	end

	if activeIntent.attempts > 0 then
		table.insert(parts, string.format("\n?? Previous attempts: %d", activeIntent.attempts))
	end

	return table.concat(parts, "\n")
end

return TaskPlanner
