--[[
    TaskPlanner.lua
    Intelligent task analysis, planning, and ticket-based execution system
    
    This module implements the "Living Plan" architecture:
    1. Hybrid Complexity: Fast heuristic + AI validation/escalation
    2. Ticket-Based Planning: State-machine tracking for actionable units
    3. Self-Healing: Dynamic plan updates on tool failure
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local HttpService = game:GetService("HttpService")

local TaskPlanner = {}

-- ============================================================================
-- EVENT CALLBACKS (for Command Center UI integration)
-- ============================================================================

-- These callbacks are set by the UI to receive updates
TaskPlanner.onTicketUpdate = nil   -- function(ticketId, status, output)
TaskPlanner.onPlanCreated = nil    -- function(plan)
TaskPlanner.onPlanCleared = nil    -- function()
TaskPlanner.onAnalysisStart = nil  -- function(message) - Fires IMMEDIATELY when user sends message

-- ============================================================================
-- STATE
-- ============================================================================

local currentPlan = nil
local reflectionDue = false
local toolCallsSinceReflection = 0
local recentFailures = {}
local sessionHistory = {} -- Track high-level actions this session

-- ============================================================================
-- TASK COMPLEXITY ANALYSIS (Heuristic)
-- ============================================================================

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
		keywords = { "system", "complete", "full", "entire", "refactor", "redesign", "integrate", "architecture" },
		patterns = { "with%s+.+%s+and%s+.+%s+and", "complete%s+.+%s+system", "refactor%s+all" }
	}
}

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
    Analyze a user message to determine HEURISTIC task complexity
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
		heuristicSuggestion = "simple"
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

	local complexityScore = 0

	-- Heuristic Scoring
	for _, keyword in ipairs(COMPLEXITY_INDICATORS.simple.keywords) do
		if lowerMessage:find(keyword) then complexityScore = complexityScore - 1 end
	end
	for _, keyword in ipairs(COMPLEXITY_INDICATORS.medium.keywords) do
		if lowerMessage:find(keyword) then complexityScore = complexityScore + 1 end
	end
	for _, keyword in ipairs(COMPLEXITY_INDICATORS.complex.keywords) do
		if lowerMessage:find(keyword) then complexityScore = complexityScore + 3 end
	end

	complexityScore = complexityScore + (#analysis.capabilities * 2)

	if complexityScore <= Constants.PLANNING.complexityThresholds.simple then
		analysis.complexity = "simple"
	elseif complexityScore <= Constants.PLANNING.complexityThresholds.medium then
		analysis.complexity = "medium"
	else
		analysis.complexity = "complex"
	end

	analysis.heuristicSuggestion = analysis.complexity
	analysis.shouldPlan = analysis.complexity ~= "simple"

	return analysis
end

-- ============================================================================
-- PLANNING (Ticket-Based)
-- ============================================================================

--[[
    Create a new living plan with tickets
    @param message string - Original request
    @param analysis table - From analyzeTask
    @return table - Living plan
]]
function TaskPlanner.createPlan(message, analysis)
	local plan = {
		id = HttpService:GenerateGUID(false),
		goal = message,
		complexity = analysis.complexity,
		status = "in_progress",
		tickets = {},
		currentTicketId = 1,
		createdAt = tick(),
		heuristic = analysis.heuristicSuggestion
	}

	-- Initial template tickets (AI will evolve these)
	table.insert(plan.tickets, {
		id = 1,
		text = "Scan and understand current project state",
		status = "PENDING",
		type = "discovery"
	})

	if analysis.complexity == "complex" then
		table.insert(plan.tickets, {
			id = 2,
			text = "Implement core logic/structure",
			status = "PENDING"
		})
		table.insert(plan.tickets, {
			id = 3,
			text = "Verify functionality and performance",
			status = "PENDING"
		})
	else
		table.insert(plan.tickets, {
			id = 2,
			text = "Implement requested change",
			status = "PENDING"
		})
	end

	currentPlan = plan

	-- Fire event callback
	if TaskPlanner.onPlanCreated then
		TaskPlanner.onPlanCreated(plan)
	end

	return plan
end

--[[
    Update a ticket's state
    @param ticketId number
    @param status string - PENDING, RUNNING, DONE, FAILED, RETRYING
    @param output any - Optional tool output or notes
]]
function TaskPlanner.updateTicket(ticketId, status, output)
	if not currentPlan then return end

	for _, ticket in ipairs(currentPlan.tickets) do
		if ticket.id == ticketId then
			ticket.status = status
			if output then ticket.output = output end

			if status == "RUNNING" then
				currentPlan.currentTicketId = ticketId
			end

			if status == "FAILED" then
				table.insert(recentFailures, {
					ticketId = ticketId,
					error = output,
					timestamp = tick()
				})
			end

			-- Fire event callback for UI update
			if TaskPlanner.onTicketUpdate then
				TaskPlanner.onTicketUpdate(ticketId, status, output)
			end

			break
		end
	end
end

--[[
    Add a new ticket to the plan dynamically (Self-healing)
    @param text string
    @param afterId number? - Insert after this ID
]]
function TaskPlanner.addTicket(text, afterId)
	if not currentPlan then return end

	-- ZOMBIE KILLER: Remove "analysis" ticket when adding first real ticket
	if #currentPlan.tickets == 1 and currentPlan.tickets[1].type == "analysis" then
		currentPlan.tickets = {}  -- Clear the zombie
	end

	local newId = #currentPlan.tickets + 1
	local newTicket = {
		id = newId,
		text = text,
		status = "PENDING"
	}

	if afterId then
		local insertAt = 1
		for i, ticket in ipairs(currentPlan.tickets) do
			if ticket.id == afterId then
				insertAt = i + 1
				break
			end
		end
		table.insert(currentPlan.tickets, insertAt, newTicket)
		-- Renumber subsequent tickets to maintain order
		for i = insertAt + 1, #currentPlan.tickets do
			currentPlan.tickets[i].id = i
		end
	else
		table.insert(currentPlan.tickets, newTicket)
	end

	-- Auto-escalate if plan grows large
	if #currentPlan.tickets > 5 and currentPlan.complexity ~= "complex" then
		currentPlan.complexity = "complex"
	end
end

--[[
    Get formatted living plan for display / system prompt
    @return string
]]
function TaskPlanner.formatPlan()
	if not currentPlan then return "" end

	local parts = { string.format("\n### ?? Living Plan: %s\n", currentPlan.complexity:upper()) }
	
	for _, ticket in ipairs(currentPlan.tickets) do
		local icon = "⬜"
		if ticket.status == "DONE" then icon = "✅"
		elseif ticket.status == "RUNNING" then icon = "🔄"
		elseif ticket.status == "FAILED" then icon = "❌"
		elseif ticket.status == "RETRYING" then icon = "⚠" end
		
		local line = string.format("%s %s", icon, ticket.text)
		if ticket.status == "RUNNING" and ticket.tool then
			line = line .. string.format(" (Active: `%s`)", ticket.tool)
		end
		table.insert(parts, line)
	end

	return table.concat(parts, "\n")
end

-- ============================================================================
-- PRE-PLANNING (Immediate UI Feedback)
-- ============================================================================

--[[
    Called IMMEDIATELY when user sends a message
    Creates a preliminary "Analyzing..." plan so Mission pane updates instantly
    @param message string - User's request
    @return table - Preliminary plan for immediate display
]]
function TaskPlanner.beginAnalysis(message)
	-- Clear any existing plan
	if currentPlan then
		TaskPlanner.clearPlan()
	end

	-- Create preliminary plan immediately
	local prelimPlan = {
		id = HttpService:GenerateGUID(false),
		goal = message:sub(1, 50) .. (message:len() > 50 and "..." or ""),
		complexity = "analyzing",
		status = "analyzing",
		tickets = {
			{
				id = 1,
				text = "Analyzing request...",
				status = "RUNNING",
				type = "analysis"
			}
		},
		currentTicketId = 1,
		createdAt = tick(),
		isPreliminary = true
	}

	currentPlan = prelimPlan

	-- Fire immediate callback for UI
	if TaskPlanner.onAnalysisStart then
		TaskPlanner.onAnalysisStart(message)
	end

	if TaskPlanner.onPlanCreated then
		TaskPlanner.onPlanCreated(prelimPlan)
	end

	return prelimPlan
end

--[[
    Finalize analysis and update plan with actual tickets
    Called after AI determines the actual plan steps
    @param analysis table - From analyzeTask()
    @param aiSteps table|nil - Optional AI-generated steps
]]
function TaskPlanner.finalizeAnalysis(analysis, aiSteps)
	if not currentPlan then return end

	-- Update the plan with real complexity
	currentPlan.complexity = analysis.complexity
	currentPlan.status = "in_progress"
	currentPlan.isPreliminary = false

	-- Mark analysis ticket as done
	if currentPlan.tickets[1] and currentPlan.tickets[1].type == "analysis" then
		currentPlan.tickets[1].status = "DONE"
		currentPlan.tickets[1].text = "Request analyzed"
	end

	-- Add real tickets based on analysis
	local nextId = 2

	if aiSteps and #aiSteps > 0 then
		-- Use AI-generated steps
		for _, step in ipairs(aiSteps) do
			table.insert(currentPlan.tickets, {
				id = nextId,
				text = step,
				status = "PENDING"
			})
			nextId = nextId + 1
		end
	else
		-- Use heuristic-based tickets
		if analysis.complexity == "complex" then
			table.insert(currentPlan.tickets, { id = nextId, text = "Understand project structure", status = "PENDING" })
			nextId = nextId + 1
			table.insert(currentPlan.tickets, { id = nextId, text = "Implement core changes", status = "PENDING" })
			nextId = nextId + 1
			table.insert(currentPlan.tickets, { id = nextId, text = "Verify and test", status = "PENDING" })
		elseif analysis.complexity == "medium" then
			table.insert(currentPlan.tickets, { id = nextId, text = "Locate target files", status = "PENDING" })
			nextId = nextId + 1
			table.insert(currentPlan.tickets, { id = nextId, text = "Make changes", status = "PENDING" })
		else
			table.insert(currentPlan.tickets, { id = nextId, text = "Execute request", status = "PENDING" })
		end
	end

	-- Auto-escalate if many steps
	if #currentPlan.tickets > Constants.PLANNING.aiEscalationThreshold then
		currentPlan.complexity = "complex"
	end

	-- Notify UI of updated plan
	if TaskPlanner.onPlanCreated then
		TaskPlanner.onPlanCreated(currentPlan)
	end
end

-- ============================================================================
-- AGENTIC LOOP INTEGRATION
-- ============================================================================

function TaskPlanner.getCurrentPlan() return currentPlan end

function TaskPlanner.clearPlan()
	currentPlan = nil
	-- Fire event callback
	if TaskPlanner.onPlanCleared then
		TaskPlanner.onPlanCleared()
	end
end

function TaskPlanner.recordToolCall(toolName, success)
	toolCallsSinceReflection = toolCallsSinceReflection + 1
	if not success then
		reflectionDue = true
	end
end

function TaskPlanner.isReflectionDue()
	return reflectionDue or toolCallsSinceReflection >= Constants.PLANNING.reflectionInterval
end

function TaskPlanner.reflectionCompleted()
	reflectionDue = false
	toolCallsSinceReflection = 0
end

function TaskPlanner.getRecentFailureCount()
	return #recentFailures
end

-- ============================================================================
-- INTENT & HISTORY
-- ============================================================================

function TaskPlanner.formatSessionHistoryForPrompt()
	if not Constants.ADAPTIVE_PROMPT.includeSessionHistory then return "" end
	local parts = { "\n## Session History\n" }
	if #sessionHistory == 0 then return "" end
	
	for i = math.max(1, #sessionHistory - 5), #sessionHistory do
		local action = sessionHistory[i]
		local icon = action.success and "✅" or "❌"
		table.insert(parts, string.format("- %s %s", icon, action.text:sub(1, 60)))
	end
	return table.concat(parts, "\n")
end

function TaskPlanner.resetSession()
	currentPlan = nil
	recentFailures = {}
	sessionHistory = {}
	reflectionDue = false
	toolCallsSinceReflection = 0
end

return TaskPlanner
