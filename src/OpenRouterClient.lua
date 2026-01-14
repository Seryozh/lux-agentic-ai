--[[
    OpenRouterClient.lua
    Agentic AI client using OpenRouter API with iterative tool calling loop

    The AI continues working through tools until it decides it's done.
    Iterative loop: User → AI → Tool → AI → Tool → ... → Response

    NOTE: Core functionality has been extracted to Core/ modules:
    - Core/ApiClient.lua - API key management & HTTP communication
    - Core/ConversationHistory.lua - Conversation state management
    - Core/MessageConverter.lua - Message format conversion
    - Core/AgenticLoop.lua - Agentic loop & tool execution
]]

local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Shared.Constants)
local Utils = require(script.Parent.Shared.Utils)
local IndexManager = require(script.Parent.Shared.IndexManager)
local Tools = require(script.Parent.Tools.init)
local ProjectContext = require(script.Parent.Memory.ProjectContext)

-- Load system prompt and tool definitions from separate modules
local SystemPrompt = require(script.Parent.Context.SystemPrompt)
local ToolDefinitions = require(script.Parent.Tools.ToolDefinitions)

-- New agentic intelligence modules (v2.0)
local TaskPlanner = require(script.Parent.Planning.TaskPlanner)
local ErrorAnalyzer = require(script.Parent.Safety.ErrorAnalyzer)
local ContextSelector = require(script.Parent.Context.ContextSelector)
local Verification = require(script.Parent.Planning.Verification)
local DecisionMemory = require(script.Parent.Memory.DecisionMemory)

-- Safety and resilience modules (v3.0)
local SessionManager = require(script.Parent.Coordination.SessionManager)
local CircuitBreaker = require(script.Parent.Safety.CircuitBreaker)
local OutputValidator = require(script.Parent.Safety.OutputValidator)
local ErrorPredictor = require(script.Parent.Safety.ErrorPredictor)
local WorkingMemory = require(script.Parent.Memory.WorkingMemory)

-- Self-Healing Resilience Layer (v4.0)
local ToolResilience = require(script.Parent.Safety.ToolResilience)
local CompressionFallback = require(script.Parent.Context.CompressionFallback)

-- Core modules (refactored v5.0)
local ApiClient = require(script.Parent.Core.ApiClient)
local ConversationHistory = require(script.Parent.Core.ConversationHistory)
local MessageConverter = require(script.Parent.Core.MessageConverter)
local AgenticLoop = require(script.Parent.Core.AgenticLoop)

local OpenRouterClient = {}

-- Current task analysis (stored for use across iterations)
local currentTaskAnalysis = nil
local currentUserMessage = nil

-- ============================================================================
-- INITIALIZATION & SESSION MANAGEMENT
-- ============================================================================

function OpenRouterClient.init(plugin)
	ApiClient.init(plugin)
end

function OpenRouterClient.onSessionStart()
	-- Reset resilience metrics for new session (v4.0)
	ToolResilience.reset()

	-- Use SessionManager for coordinated initialization (v3.0)
	local sessionResult = SessionManager.onConversationStart()

	if Constants.DEBUG then
		print(string.format("[Lux] Session started via SessionManager: %d context valid, %d stale, %d patterns",
			sessionResult.contextValid,
			sessionResult.contextStale,
			sessionResult.patternsLoaded
			))
	end

	-- Legacy support: Also run old initialization if PROJECT_CONTEXT is enabled
	if Constants.PROJECT_CONTEXT.enabled and Constants.PROJECT_CONTEXT.validateOnSessionStart then
		-- Auto-cleanup entries with persistently invalid anchors
		local removedCount = ProjectContext.cleanupInvalidEntries()
		if removedCount > 0 and Constants.DEBUG then
			print(string.format("[Lux] Session start: Cleaned up %d invalid context entries", removedCount))
		end
	end

	return sessionResult
end

--[[
	Called when session/conversation ends (plugin unload or explicit reset)
]]
function OpenRouterClient.onSessionEnd()
	SessionManager.onConversationEnd()

	if Constants.DEBUG then
		print("[Lux] Session ended via SessionManager")
	end
end

-- ============================================================================
-- TOOL DEFINITIONS
-- ============================================================================

-- Build tool definitions in OpenAI format
local function buildToolDefinitions()
	local tools = {}

	-- Convert tool definitions to OpenAI format
	for _, func in ipairs(ToolDefinitions) do
		table.insert(tools, {
			type = "function",
			["function"] = func
		})
	end

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Built %d tools for OpenRouter", #tools))
	end

	return tools
end

-- ============================================================================
-- SCRIPT LIST FORMATTING
-- ============================================================================

--[[
    Format script list for system prompt (generated dynamically by scanning)
    @return string - Formatted script list text
]]
local function formatScriptListForPrompt()
	local scanResult = IndexManager.scanScripts()
	local scripts = scanResult.scripts

	local lines = {}

	-- Include validated project context
	local contextText = ProjectContext.formatForPrompt()
	if contextText ~= "" then
		table.insert(lines, contextText)
		table.insert(lines, "---\n")
	end

	table.insert(lines, "GAME SCRIPTS (Compact View):\n")

	-- Sort scripts by path
	table.sort(scripts, function(a, b) return a.path < b.path end)

	-- Limit number of scripts in prompt (Priority 3.3)
	local MAX_SCRIPTS_IN_PROMPT = 400

	for i, scriptData in ipairs(scripts) do
		if i > MAX_SCRIPTS_IN_PROMPT then
			table.insert(lines, string.format("... and %d more scripts", #scripts - MAX_SCRIPTS_IN_PROMPT))
			break
		end

		-- Compact format: "📄 Path/To/File (Type, N lines)"
		table.insert(lines, string.format("📄 %s (%s, %d lines)",
			scriptData.path,
			scriptData.className,
			scriptData.lineCount))
	end

	if #scripts == 0 then
		table.insert(lines, "No scripts found yet.")
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- API COMMUNICATION WRAPPER
-- ============================================================================

--[[
	Call OpenRouter API (wrapper that adds system prompt and converts messages)
	@param contents table - Conversation history in internal format
	@return table - {success: bool, response: table} or {success: false, error: string}
]]
local function callOpenRouterAPI(contents)
	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Calling OpenRouter API (conversation: %d messages)", #contents))
	end

	-- Build request
	local tools = buildToolDefinitions()
	local messages = MessageConverter.toOpenAI(contents)

	-- Build dynamic system prompt using new modules
	local systemContent
	if Constants.ADAPTIVE_PROMPT.enabled and currentUserMessage then
		-- Use the new adaptive prompt builder, passing pre-computed analysis to avoid duplicate computation
		systemContent = SystemPrompt.buildComplete(currentUserMessage, {
			TaskPlanner = TaskPlanner,
			DecisionMemory = DecisionMemory,
			ProjectContext = ProjectContext,
			ContextSelector = ContextSelector,
			ErrorAnalyzer = ErrorAnalyzer
		}, currentTaskAnalysis)

		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] Built adaptive prompt (%d chars)", #systemContent))
		end
	else
		-- Fallback to static prompt with old-style script list
		systemContent = SystemPrompt.getStatic() .. "\n\n" .. formatScriptListForPrompt()
	end

	table.insert(messages, 1, {
		role = "system",
		content = systemContent
	})

	-- Call API via ApiClient
	return ApiClient.callAPI(messages, tools)
end

-- ============================================================================
-- PUBLIC API - FORWARDING TO CORE MODULES
-- ============================================================================

-- API Key Management (ApiClient)
function OpenRouterClient.saveApiKey(key)
	return ApiClient.saveApiKey(key)
end

function OpenRouterClient.getCurrentModel()
	return ApiClient.getCurrentModel()
end

function OpenRouterClient.setModel(modelId)
	return ApiClient.setModel(modelId)
end

function OpenRouterClient.validateApiKey(key)
	return ApiClient.validateApiKey(key)
end

function OpenRouterClient.getCredits()
	return ApiClient.getCredits()
end

function OpenRouterClient.getCreditBalance()
	return ApiClient.getCreditBalance()
end

function OpenRouterClient.getTokenUsage()
	return ApiClient.getTokenUsage()
end

-- Conversation History Management (ConversationHistory)
function OpenRouterClient.resetConversation()
	-- End current session via SessionManager (v3.0)
	if SessionManager.isConversationActive() then
		SessionManager.onConversationEnd()
	end

	ConversationHistory.resetConversation()
	ApiClient.resetTokenUsage()

	-- Clear task-specific state
	currentTaskAnalysis = nil
	currentUserMessage = nil

	-- Reset resilience layer (v4.0)
	ToolResilience.reset()
end

function OpenRouterClient.resetToolLog()
	return ConversationHistory.resetToolLog()
end

function OpenRouterClient.recordToolExecution(toolName, description, success)
	return ConversationHistory.recordToolExecution(toolName, description, success)
end

function OpenRouterClient.getToolExecutionSummary()
	return ConversationHistory.getToolExecutionSummary()
end

function OpenRouterClient.getConversationHistory()
	return ConversationHistory.getHistory()
end

function OpenRouterClient.estimateTokenCount()
	return ConversationHistory.estimateTokenCount()
end

-- Agentic Loop (AgenticLoop)
function OpenRouterClient.processLoop(statusCallback, chatRenderer)
	return AgenticLoop.processLoop(statusCallback, chatRenderer, callOpenRouterAPI)
end

function OpenRouterClient.resumeWithApproval(approved)
	return AgenticLoop.resumeWithApproval(approved)
end

function OpenRouterClient.resumeWithFeedback(feedbackResponse)
	return AgenticLoop.resumeWithFeedback(feedbackResponse)
end

-- ============================================================================
-- MAIN CONVERSATION FUNCTIONS
-- ============================================================================

--[[
    Start a new conversation
    @param userMessage string - User's message
    @param statusCallback function - Called with (iteration, status) for UI updates
    @param chatRenderer table - Optional ChatRenderer module for displaying tool calls
    @return table - {success, text} or {awaitingApproval, operation, thinkingText}
]]
function OpenRouterClient.startConversation(userMessage, statusCallback, chatRenderer)
	-- Store user message for adaptive prompt building
	currentUserMessage = userMessage

	-- Use SessionManager for coordinated new task initialization (v3.0)
	-- This handles: ErrorAnalyzer.onNewTask, TaskPlanner.onNewTask, CircuitBreaker.forceReset,
	-- WorkingMemory goal setting, DecisionMemory.startSequence, etc.
	currentTaskAnalysis = SessionManager.onNewTask(userMessage)

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Task analysis via SessionManager: complexity=%s, steps=%d",
			currentTaskAnalysis.complexity or "unknown",
			currentTaskAnalysis.estimatedSteps or 0
			))
	end

	-- Create plan for complex tasks (legacy support)
	if Constants.PLANNING.enabled and currentTaskAnalysis.shouldPlan then
		TaskPlanner.createPlan(userMessage, currentTaskAnalysis)
	end

	-- Reset session tracking
	TaskPlanner.resetSession()

	return AgenticLoop.startConversation(userMessage, statusCallback, chatRenderer, callOpenRouterAPI)
end

--[[
    Continue existing conversation
    @param userMessage string - User's message
    @param statusCallback function - Called with (iteration, status) for UI updates
    @param chatRenderer table - Optional ChatRenderer module for displaying tool calls
    @return table - {success, text} or {awaitingApproval, operation, thinkingText}
]]
function OpenRouterClient.continueConversation(userMessage, statusCallback, chatRenderer)
	-- Update user message for adaptive prompt
	currentUserMessage = userMessage

	-- Mark previous task as complete before starting new one (v3.0)
	SessionManager.onTaskComplete(true, "Continuing to next task")

	-- Use SessionManager for coordinated new task initialization (v3.0)
	currentTaskAnalysis = SessionManager.onNewTask(userMessage)

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Continued task via SessionManager: complexity=%s",
			currentTaskAnalysis.complexity or "unknown"
			))
	end

	return AgenticLoop.continueConversation(userMessage, statusCallback, chatRenderer, callOpenRouterAPI)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--[[
    Check if API is configured
    @return boolean, string - isConfigured, error message if not
]]
function OpenRouterClient.checkConfiguration()
	-- This requires direct access to plugin settings, so we can't fully delegate
	-- For now, we'll keep a simple check here and delegate validation to ApiClient
	local testKey = "test"
	local result = ApiClient.validateApiKey(testKey)

	if result.error and result.error:match("No API key") then
		return false, "API key not configured"
	end

	-- Check if HttpService is enabled
	local httpEnabled = pcall(function()
		HttpService:GetAsync("https://www.google.com")
	end)

	if not httpEnabled then
		return false, "HttpService not enabled - enable in Game Settings > Security > Allow HTTP Requests"
	end

	return true, nil
end

--[[
	Get resilience layer health metrics (v4.0)
	@return table - Health metrics and status
]]
function OpenRouterClient.getResilienceHealth()
	return {
		health = ToolResilience.checkHealth(),
		metrics = ToolResilience.getMetrics()
	}
end

return OpenRouterClient
