--[[
    OpenRouterClient.lua
    Agentic AI client using OpenRouter API with iterative tool calling loop

    The AI continues working through tools until it decides it's done.
    Iterative loop: User ? AI ? Tool ? AI ? Tool ? ... ? Response
]]

local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)
local IndexManager = require(script.Parent.IndexManager)
local Tools = require(script.Parent.Tools)
local ProjectContext = require(script.Parent.ProjectContext)

-- Load system prompt and tool definitions from separate modules
local SystemPrompt = require(script.Parent.SystemPrompt)
local ToolDefinitions = require(script.Parent.ToolDefinitions)

-- New agentic intelligence modules (v2.0)
local TaskPlanner = require(script.Parent.TaskPlanner)
local ErrorAnalyzer = require(script.Parent.ErrorAnalyzer)
local ContextSelector = require(script.Parent.ContextSelector)
local Verification = require(script.Parent.Verification)
local DecisionMemory = require(script.Parent.DecisionMemory)

-- Safety and resilience modules (v3.0)
local SessionManager = require(script.Parent.SessionManager)
local CircuitBreaker = require(script.Parent.CircuitBreaker)
local OutputValidator = require(script.Parent.OutputValidator)
local ErrorPredictor = require(script.Parent.ErrorPredictor)
local WorkingMemory = require(script.Parent.WorkingMemory)

-- Self-Healing Resilience Layer (v4.0)
local ToolResilience = require(script.Parent.ToolResilience)
local CompressionFallback = require(script.Parent.CompressionFallback)

local OpenRouterClient = {}

-- Store reference to plugin for settings
local pluginInstance = nil

-- Current model (can be changed at runtime)
local currentModel = Constants.OPENROUTER_MODEL

-- ============================================================================
-- API KEY MANAGEMENT
-- ============================================================================

--[[
    Get the API Key from plugin settings
    @return string|nil - API key or nil if not set
]]
local function getApiKey()
	if pluginInstance then
		local savedKey = pluginInstance:GetSetting("OPENROUTER_API_KEY")
		if savedKey and savedKey ~= "" then
			return savedKey
		end
	end
	return nil
end

--[[
    Save API key to plugin settings
    @param key string - The API key to save
]]
function OpenRouterClient.saveApiKey(key)
	if pluginInstance then
		pluginInstance:SetSetting("OPENROUTER_API_KEY", key)
	end
end

function OpenRouterClient.init(plugin)
	pluginInstance = plugin

	-- Load saved model preference
	local savedModel = plugin:GetSetting("OPENROUTER_MODEL")
	if savedModel and savedModel ~= "" then
		currentModel = savedModel
	end
end

--[[
    Get current model ID
    @return string - Current model ID
]]
function OpenRouterClient.getCurrentModel()
	return currentModel
end

--[[
    Set model and persist to settings
    @param modelId string - Model ID to use
]]
function OpenRouterClient.setModel(modelId)
	currentModel = modelId
	if pluginInstance then
		pluginInstance:SetSetting("OPENROUTER_MODEL", modelId)
	end
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
-- HTTP REQUEST WITH TIMEOUT
-- ============================================================================

local function withTimeout(fn, timeout)
	local done, result, err = false, nil, nil

	task.spawn(function()
		local ok, res = pcall(fn)
		if ok then
			result = res
		else
			err = res
		end
		done = true
	end)

	local start = tick()
	while not done and (tick() - start) < timeout do
		task.wait(0.1)
	end

	if not done then
		return nil, "Timeout"
	end

	if err then
		return nil, err
	end

	return result, nil
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

		-- Compact format: "� Path/To/File (Type, N lines)"
		table.insert(lines, string.format("� %s (%s, %d lines)",
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
-- CONVERSATION STATE
-- ============================================================================

local conversationHistory = {}

-- Token usage tracking for current session
local tokenUsage = {
	promptTokens = 0,
	completionTokens = 0,
	totalTokens = 0,
	apiCalls = 0,
	totalCost = 0,
	lastRequestCost = 0
}

-- Credit balance (fetched from API)
local creditBalance = nil

-- Tool execution tracking for completion summary
local toolExecutionLog = {
	items = {},        -- Array of { toolName, description, success }
	successful = 0,
	failed = 0,
	totalTools = 0
}

function OpenRouterClient.resetConversation()
	-- End current session via SessionManager (v3.0)
	if SessionManager.isConversationActive() then
		SessionManager.onConversationEnd()
	end

	conversationHistory = {}
	-- Reset token tracking
	tokenUsage = {
		promptTokens = 0,
		completionTokens = 0,
		totalTokens = 0,
		apiCalls = 0,
		totalCost = 0,
		lastRequestCost = 0
	}
	-- Reset tool execution log
	toolExecutionLog = {
		items = {},
		successful = 0,
		failed = 0,
		totalTools = 0
	}

	-- Clear task-specific state
	currentTaskAnalysis = nil
	currentUserMessage = nil

	-- Reset resilience layer (v4.0)
	ToolResilience.reset()
end

--[[
    Reset tool execution log (call at start of new task)
]]
function OpenRouterClient.resetToolLog()
	toolExecutionLog = {
		items = {},
		successful = 0,
		failed = 0,
		totalTools = 0
	}
end

--[[
    Record a tool execution for the completion summary
    @param toolName string - Name of the tool
    @param description string - Human-readable description of what was done
    @param success boolean - Whether the tool succeeded
]]
function OpenRouterClient.recordToolExecution(toolName, description, success)
	toolExecutionLog.totalTools = toolExecutionLog.totalTools + 1

	if success then
		toolExecutionLog.successful = toolExecutionLog.successful + 1
	else
		toolExecutionLog.failed = toolExecutionLog.failed + 1
	end

	table.insert(toolExecutionLog.items, {
		toolName = toolName,
		description = description,
		success = success
	})
end

--[[
    Get tool execution summary for display
    @return table - { totalTools, successful, failed, items }
]]
function OpenRouterClient.getToolExecutionSummary()
	return {
		totalTools = toolExecutionLog.totalTools,
		successful = toolExecutionLog.successful,
		failed = toolExecutionLog.failed,
		items = toolExecutionLog.items
	}
end

function OpenRouterClient.getConversationHistory()
	return conversationHistory
end

function OpenRouterClient.getTokenUsage()
	return tokenUsage
end

function OpenRouterClient.getCreditBalance()
	return creditBalance
end

-- ============================================================================
-- RESPONSE SANITIZATION
-- ============================================================================

--[[
    Sanitize tool response to ensure it's safe for JSON encoding and API submission
    @param response table - The tool response
    @return table - Sanitized response
]]
local function sanitizeToolResponse(response)
	if type(response) ~= "table" then
		return response
	end

	local sanitized = {}

	for key, value in pairs(response) do
		local valueType = type(value)

		if valueType == "string" then
			-- Remove null bytes and truncate very long strings
			local cleaned = value:gsub("\0", "")
			if #cleaned > 10000 then
				cleaned = cleaned:sub(1, 10000) .. "... [truncated]"
			end
			sanitized[key] = cleaned

		elseif valueType == "number" or valueType == "boolean" then
			sanitized[key] = value

		elseif valueType == "table" then
			sanitized[key] = sanitizeToolResponse(value)

		elseif valueType == "nil" then
			sanitized[key] = nil

		else
			-- Userdata, function, thread - convert to string
			sanitized[key] = tostring(value)
		end
	end

	return sanitized
end

-- ============================================================================
-- API KEY VALIDATION & CREDITS
-- ============================================================================

--[[
    Validate an API key by checking credits endpoint
    @param key string - The API key to validate
    @return table - {valid: bool, credits: table|nil, error: string|nil}
]]
function OpenRouterClient.validateApiKey(key)
	local result, err = withTimeout(function()
		return HttpService:RequestAsync({
			Url = Constants.OPENROUTER_CREDITS_ENDPOINT,
			Method = "GET",
			Headers = {
				["Authorization"] = "Bearer " .. key
			}
		})
	end, 10)

	if err then
		return { valid = false, error = "Connection failed: " .. tostring(err) }
	end

	if result.StatusCode == 401 then
		return { valid = false, error = "Invalid API key" }
	end

	if not result.Success then
		return { valid = false, error = "HTTP " .. result.StatusCode }
	end

	local success, parsed = pcall(function()
		return HttpService:JSONDecode(result.Body)
	end)

	if not success or not parsed.data then
		return { valid = false, error = "Invalid response from OpenRouter" }
	end

	local data = parsed.data
	return {
		valid = true,
		credits = {
			total = data.total_credits or 0,
			used = data.total_usage or 0,
			remaining = (data.total_credits or 0) - (data.total_usage or 0)
		}
	}
end

--[[
    Fetch current credit balance
    @return table|nil - {total, used, remaining} or nil on error
]]
function OpenRouterClient.getCredits()
	local key = getApiKey()
	if not key then return nil end

	local result = OpenRouterClient.validateApiKey(key)
	if result.valid then
		creditBalance = result.credits
		return result.credits
	end
	return nil
end

-- ============================================================================
-- API COMMUNICATION
-- ============================================================================

--[[
    Convert internal conversation format to OpenAI format
    @param contents table - Conversation history in internal format
    @return table - Messages in OpenAI format
]]
local function convertToOpenAIMessages(contents)
	local messages = {}
	local toolCallIds = {} -- Queue to store IDs for pending tool calls

	-- Convert messages
	for _, msg in ipairs(contents) do
		local role = msg.role
		if role == "model" then role = "assistant" end

		-- Accumulate text content for this message
		local textContent = ""
		local toolCalls = nil

		if msg.parts then
			for _, part in ipairs(msg.parts) do
				if part.text then
					textContent = textContent .. part.text
				elseif part.functionCall then
					if not toolCalls then toolCalls = {} end

					local callId = "call_" .. HttpService:GenerateGUID(false)
					table.insert(toolCallIds, callId)

					table.insert(toolCalls, {
						id = callId,
						type = "function",
						["function"] = {
							name = part.functionCall.name,
							arguments = HttpService:JSONEncode(part.functionCall.args or {})
						}
					})
				end
			end
		end

		-- Add text/tool_calls message
		if textContent ~= "" or toolCalls then
			local message = { role = role }
			if textContent ~= "" then message.content = textContent end
			if toolCalls then message.tool_calls = toolCalls end
			table.insert(messages, message)
		end

		-- Add tool response messages
		if msg.parts then
			for _, part in ipairs(msg.parts) do
				if part.functionResponse then
					local callId = table.remove(toolCallIds, 1) or "call_unknown"

					table.insert(messages, {
						role = "tool",
						tool_call_id = callId,
						name = part.functionResponse.name,
						content = HttpService:JSONEncode(part.functionResponse.response)
					})
				end
			end
		end
	end

	return messages
end

-- Current task analysis (stored for use across iterations)
local currentTaskAnalysis = nil
local currentUserMessage = nil

--[[
    Call OpenRouter API
    @param contents table - Conversation history
    @return table - {success: bool, response: table} or {success: false, error: string}
]]
local function callOpenRouterAPI(contents)
	local key = getApiKey()
	if not key then
		return { success = false, error = "No API key configured" }
	end

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Calling OpenRouter API (conversation: %d messages)", #contents))
	end

	-- Build request
	local tools = buildToolDefinitions()
	local messages = convertToOpenAIMessages(contents)

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

	local requestBody = {
		model = currentModel,
		messages = messages,
		tools = tools,
		max_tokens = Constants.GENERATION_CONFIG.maxOutputTokens or 65536,
		temperature = Constants.GENERATION_CONFIG.temperature or 1.0,
		usage = { include = true }  -- Get cost tracking
	}

	local requestBodyJson = HttpService:JSONEncode(requestBody)

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Request body size: %d characters", #requestBodyJson))
	end

	-- Make HTTP request with retry logic for transient errors
	local MAX_RETRIES = 3
	local RETRY_CODES = { [429] = true, [500] = true, [502] = true, [503] = true, [504] = true }
	local result, err
	local lastError

	for attempt = 1, MAX_RETRIES do
		local startTime = tick()
		result, err = withTimeout(function()
			return HttpService:RequestAsync({
				Url = Constants.OPENROUTER_ENDPOINT,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["Authorization"] = "Bearer " .. key,
					["HTTP-Referer"] = Constants.OPENROUTER_REFERER,
					["X-Title"] = "Lux",
					-- Explicitly tell OpenRouter we're using OpenAI format (no transforms)
					["OpenAI-Beta"] = "assistants=v1"
				},
				Body = requestBodyJson
			})
		end, Constants.REQUEST_TIMEOUT)

		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] API call attempt %d took %.2f seconds", attempt, tick() - startTime))
		end

		-- Check for timeout/network error
		if err then
			lastError = "Request failed: " .. tostring(err)
			if attempt < MAX_RETRIES then
				local backoff = math.pow(2, attempt - 1) * 2  -- 2s, 4s, 8s
				if Constants.DEBUG then
					print(string.format("[Lux DEBUG] Network error, retrying in %.1fs...", backoff))
				end
				task.wait(backoff)
			end
		elseif result.Success then
			-- Success - break out of retry loop
			break
		else
			-- HTTP error - check if retryable
			local statusCode = result.StatusCode

			if statusCode == 401 then
				return { success = false, error = "Invalid API key. Please check your OpenRouter key." }
			elseif statusCode == 402 then
				return { success = false, error = "Insufficient credits. Add credits at openrouter.ai" }
			elseif RETRY_CODES[statusCode] and attempt < MAX_RETRIES then
				-- Retryable error - exponential backoff
				local backoff = math.pow(2, attempt - 1) * 2  -- 2s, 4s, 8s
				lastError = string.format("HTTP %d - retrying...", statusCode)
				if Constants.DEBUG then
					print(string.format("[Lux DEBUG] HTTP %d, retrying in %.1fs (attempt %d/%d)",
						statusCode, backoff, attempt, MAX_RETRIES))
				end
				task.wait(backoff)
			else
				-- Non-retryable error or max retries exceeded
				local errorMsg = "HTTP " .. statusCode
				if statusCode == 429 then
					errorMsg = "Rate limited after " .. MAX_RETRIES .. " retries. Please wait and try again."
				elseif statusCode >= 500 then
					errorMsg = "OpenRouter server error (HTTP " .. statusCode .. "). Please try again later."
				end

				if Constants.DEBUG then
					print(string.format("[Lux DEBUG] API error: %s", errorMsg))
					print(string.format("[Lux DEBUG] Response body: %s", result.Body:sub(1, 500)))
				end

				return { success = false, error = errorMsg }
			end
		end
	end

	-- Check final result after retries
	if err then
		return { success = false, error = lastError or "Request failed after " .. MAX_RETRIES .. " retries" }
	end

	if not result.Success then
		return { success = false, error = "Request failed after " .. MAX_RETRIES .. " retries" }
	end

	-- Parse response
	local success, parsed = pcall(function()
		return HttpService:JSONDecode(result.Body)
	end)

	if not success then
		return { success = false, error = "Failed to parse API response" }
	end

	-- Check for API error in response
	if parsed.error then
		return { success = false, error = parsed.error.message or "Unknown API error" }
	end

	-- Check for valid response
	if not parsed.choices or #parsed.choices == 0 then
		return { success = false, error = "No response from API" }
	end

	-- Extract and track token usage
	if parsed.usage then
		local usage = parsed.usage
		local cost = usage.cost or 0

		tokenUsage.promptTokens = tokenUsage.promptTokens + (usage.prompt_tokens or 0)
		tokenUsage.completionTokens = tokenUsage.completionTokens + (usage.completion_tokens or 0)
		tokenUsage.totalTokens = tokenUsage.totalTokens + (usage.total_tokens or 0)
		tokenUsage.totalCost = tokenUsage.totalCost + cost
		tokenUsage.lastRequestCost = cost
		tokenUsage.apiCalls = tokenUsage.apiCalls + 1

		-- Instant balance update (optimistic)
		if creditBalance and creditBalance.remaining then
			creditBalance.remaining = creditBalance.remaining - cost
			creditBalance.used = creditBalance.used + cost
		end

		if Constants.DEBUG then
			print(string.format("\n?? [COST] Call #%d: $%.4f | Session total: $%.4f | Tokens: %d in, %d out\n",
				tokenUsage.apiCalls,
				cost,
				tokenUsage.totalCost,
				usage.prompt_tokens or 0,
				usage.completion_tokens or 0
				))
		end
	end

	-- Convert OpenAI response back to internal format
	local choice = parsed.choices[1]
	local internalParts = {}

	if choice.message.content then
		table.insert(internalParts, { text = choice.message.content })
	end

	if choice.message.tool_calls then
		for _, call in ipairs(choice.message.tool_calls) do
			local args = {}
			pcall(function()
				args = HttpService:JSONDecode(call["function"].arguments)
			end)

			table.insert(internalParts, {
				functionCall = {
					name = call["function"].name,
					args = args
				}
			})
		end
	end

	return {
		success = true,
		response = {
			parts = internalParts,
			finishReason = choice.finish_reason
		}
	}
end

-- ============================================================================
-- CONTEXT MANAGEMENT
-- ============================================================================

--[[
    Estimate conversation token count (rough estimate)
]]
local function estimateTokenCount()
	local total = 0
	for _, msg in ipairs(conversationHistory) do
		if msg.parts then
			for _, part in ipairs(msg.parts) do
				if part.text then
					total = total + (#part.text / 4)
				elseif part.functionCall then
					total = total + 100
				elseif part.functionResponse then
					local responseStr = HttpService:JSONEncode(part.functionResponse.response)
					total = total + (#responseStr / 4)
				end
			end
		end
	end
	return total
end

--[[
    Call API to summarize history
    @param historyToSummarize table - Array of messages to summarize
    @return string|nil - Summary text or nil if failed
]]
local function generateHistorySummary(historyToSummarize)
	if Constants.DEBUG then
		print("[Lux DEBUG] Generating summary for " .. #historyToSummarize .. " messages...")
	end

	local key = getApiKey()
	if not key then return nil end

	-- Convert just the text parts for summary
	local textContent = ""
	for _, msg in ipairs(historyToSummarize) do
		local role = msg.role
		local text = ""
		if msg.parts then
			for _, part in ipairs(msg.parts) do
				if part.text then text = text .. part.text end
				if part.functionCall then text = text .. " [Tool Call: " .. part.functionCall.name .. "]" end
				if part.functionResponse then text = text .. " [Tool Result]" end
			end
		end
		textContent = textContent .. string.format("\n%s: %s", role, text)
	end

	local requestBody = {
		model = Constants.SUMMARY_MODEL or Constants.OPENROUTER_MODEL,
		messages = {
			{
				role = "system",
				content = "You are a technical summarizer. Summarize the following conversation logs from a Roblox Studio coding session. Focus strictly on:\n1. Technical decisions made\n2. Current state of files (what was edited/created)\n3. Pending tasks or errors\nDiscard casual chatter. Be concise."
			},
			{
				role = "user",
				content = textContent
			}
		},
		max_tokens = 2000,
		temperature = 0.5
	}

	local success, result = pcall(function()
		return HttpService:RequestAsync({
			Url = Constants.OPENROUTER_ENDPOINT,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["Authorization"] = "Bearer " .. key,
				["HTTP-Referer"] = Constants.OPENROUTER_REFERER,
				["X-Title"] = "Lux"
			},
			Body = HttpService:JSONEncode(requestBody)
		})
	end)

	if success and result.Success then
		local ok, parsed = pcall(HttpService.JSONDecode, HttpService, result.Body)
		if ok and parsed.choices and parsed.choices[1] then
			return parsed.choices[1].message.content
		end
	end

	return nil
end

--[[
    Compress old conversation history when token count gets high
    v4.0: Uses CompressionFallback for multi-strategy compression with zero context loss
]]
local function compressHistoryIfNeeded()
	-- Check if compression needed using new module
	if not CompressionFallback.needsCompression(conversationHistory) then
		return
	end

	if Constants.DEBUG then
		print(string.format("[Lux] Compression needed (%d messages, ~%d tokens)",
			#conversationHistory,
			CompressionFallback.estimateTokens(conversationHistory)
		))
	end

	-- Use multi-strategy compression with fallbacks (v4.0)
	local compressionResult = CompressionFallback.compress(
		conversationHistory,
		generateHistorySummary,  -- Pass AI summary function as fallback
		{
			preserveCount = Constants.MESSAGES_TO_PRESERVE or 10
		}
	)

	if compressionResult.success then
		conversationHistory = compressionResult.compressed

		if Constants.DEBUG then
			print(string.format("[Lux] Compression succeeded using strategy: %s (new size: %d messages)",
				compressionResult.strategy,
				#conversationHistory
			))
		end
	else
		-- This should never happen with CompressionFallback, but handle anyway
		warn("[Lux] All compression strategies failed (this should not happen!)")
	end
end

-- ============================================================================
-- AGENTIC LOOP
-- ============================================================================

-- Operations that require user approval
local DANGEROUS_OPERATIONS = {
	patch_script = true,
	edit_script = true,
	create_script = true,
	create_instance = true,
	set_instance_properties = true,
	delete_instance = true
}

-- Operations that request user feedback (pause for verification)
local FEEDBACK_OPERATIONS = {
	request_user_feedback = true
}

-- Pause state for resuming after approval
local pausedState = nil

-- Forward declaration
local continueLoopFromIteration

--[[
    Process a batch of tool calls sequentially
    @param startIndex number - Index to start in the batch
    @param context table - Batch context {iteration, functionCalls, functionResponses, statusCallback, thinkingText, chatRenderer}
]]
local function processToolBatch(startIndex, context)
	for i = startIndex, #context.functionCalls do
		local functionCall = context.functionCalls[i]

		if context.statusCallback then
			context.statusCallback(context.iteration, "executing_" .. functionCall.name)
		end

		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] Tool %d/%d: %s", i, #context.functionCalls, functionCall.name))
		end

		-- =========================================================
		-- PRE-EXECUTION SAFETY CHECKS (v3.0)
		-- =========================================================

		-- 1. Check CircuitBreaker (hard stop on failure spiral)
		local canProceed, cbWarning = SessionManager.beforeToolExecution(functionCall.name, functionCall.args)
		if not canProceed then
			warn("[Lux] Circuit breaker BLOCKED tool: " .. functionCall.name)
			local blockedResult = {
				error = cbWarning or "Circuit breaker activated - too many consecutive failures",
				blocked = true,
				requiresReset = true
			}
			table.insert(context.functionResponses, {
				functionResponse = {
					name = functionCall.name,
					response = sanitizeToolResponse(blockedResult)
				}
			})
			-- Return immediately - agent must acknowledge the block
			table.insert(conversationHistory, {
				role = "user",
				parts = context.functionResponses
			})
			return continueLoopFromIteration(context.iteration + 1, context.statusCallback, context.chatRenderer)
		end

		-- 2. Validate tool call (catch hallucinations before execution)
		local validation = OutputValidator.validateToolCall({
			name = functionCall.name,
			args = functionCall.args
		})

		local toolResult
		local success = true
		local toolSuccess = false
		local sanitizedResult

		if not validation.valid then
			-- Validation failed - don't execute, return error to LLM
			local validationError = OutputValidator.formatForLLM(validation)
			warn("[Lux] OutputValidator rejected tool call: " .. functionCall.name)

			if context.chatRenderer then
				context.chatRenderer.addThought("?? Tool call validation failed: " .. validationError, "warning")
			end

			toolResult = {
				error = validationError,
				validationFailed = true,
				suggestions = validation.suggestions
			}
			toolSuccess = false
			sanitizedResult = sanitizeToolResponse(toolResult)

		else
			-- 3. Check ErrorPredictor for warnings (non-blocking)
			if cbWarning and context.chatRenderer then
				context.chatRenderer.addThought("? " .. cbWarning, "warning")
			end

			-- =========================================================
			-- TOOL EXECUTION
			-- =========================================================

			-- Display tool intent BEFORE execution (if ChatRenderer available)
			if context.chatRenderer then
				local intent = Tools.formatToolIntent(functionCall.name, functionCall.args)
				context.chatRenderer.addThought(intent, "tool")
			end

			-- Use resilient execution wrapper (v4.0 - self-healing)
			toolResult = ToolResilience.executeResilient(
				Tools.execute,
				functionCall.name,
				functionCall.args
			)
			success = not toolResult.error

			-- Determine if tool execution was successful
			toolSuccess = success and not toolResult.error

			-- =========================================================
			-- POST-EXECUTION TRACKING (v3.0)
			-- =========================================================

			-- Notify SessionManager of tool result (updates CircuitBreaker, ErrorPredictor, etc.)
			SessionManager.afterToolExecution(functionCall.name, functionCall.args, toolSuccess, toolResult)

			sanitizedResult = sanitizeToolResponse(toolResult)
		end

		-- Record tool call for TaskPlanner (session tracking)
		TaskPlanner.recordToolCall(functionCall.name, toolSuccess)

		-- Record tool call for DecisionMemory (pattern learning)
		if Constants.DECISION_MEMORY.enabled then
			local resultSummary = toolResult.error or (toolResult.success and "success") or "completed"
			DecisionMemory.recordTool(functionCall.name, toolSuccess, resultSummary)
		end

		-- Display tool result AFTER execution (if ChatRenderer available)
		if context.chatRenderer then
			local resultText = Tools.formatToolResult(functionCall.name, toolResult)
			context.chatRenderer.addThought(resultText, "result")
		end

		-- Add pending result to responses
		table.insert(context.functionResponses, {
			functionResponse = {
				name = functionCall.name,
				response = sanitizedResult
			}
		})

		-- Check approval
		if DANGEROUS_OPERATIONS[functionCall.name] and toolResult.pending then
			if Constants.DEBUG then
				print(string.format("[Lux DEBUG] Pausing for approval: %s", functionCall.name))
			end

			pausedState = {
				type = "batch_paused",
				context = context,
				currentIndex = i,
				operationId = toolResult.operationId,
				taskId = SessionManager.getCurrentTaskId()  -- Scope to current task
			}

			return {
				awaitingApproval = true,
				operation = {
					type = functionCall.name,
					path = functionCall.args.path,
					description = functionCall.args.explanation or functionCall.args.purpose or "No description",
					data = functionCall.args,
					operationId = toolResult.operationId
				},
				thinkingText = context.thinkingText
			}
		end

		-- Check for user feedback request
		if FEEDBACK_OPERATIONS[functionCall.name] and toolResult.awaitingFeedback then
			if Constants.DEBUG then
				print(string.format("[Lux DEBUG] Pausing for user feedback: %s", functionCall.args.question))
			end

			pausedState = {
				type = "feedback_paused",
				context = context,
				currentIndex = i,
				operationId = toolResult.operationId,
				feedbackRequest = toolResult.feedbackRequest,
				taskId = SessionManager.getCurrentTaskId()  -- Scope to current task
			}

			return {
				awaitingUserFeedback = true,
				feedbackRequest = toolResult.feedbackRequest,
				operationId = toolResult.operationId,
				thinkingText = context.thinkingText
			}
		end
	end

	-- Batch complete: Add all results to history
	table.insert(conversationHistory, {
		role = "user",
		parts = context.functionResponses
	})

	-- Continue to next iteration
	return continueLoopFromIteration(context.iteration + 1, context.statusCallback, context.chatRenderer)
end

--[[
    Continue the agentic loop from a specific iteration (internal)
]]
continueLoopFromIteration = function(currentIteration, statusCallback, chatRenderer)
	-- If we exceeded max iterations
	if currentIteration > Constants.MAX_AGENT_ITERATIONS then
		return {
			success = false,
			error = string.format("Agent exceeded maximum iterations (%d)", Constants.MAX_AGENT_ITERATIONS)
		}
	end

	compressHistoryIfNeeded()

	if statusCallback then
		statusCallback(currentIteration, "thinking")
	end

	local response = callOpenRouterAPI(conversationHistory)

	if not response.success then
		return { success = false, error = response.error }
	end

	local parts = response.response.parts

	table.insert(conversationHistory, {
		role = "model",
		parts = parts
	})

	local functionCalls = {}
	local thinkingText = ""

	for _, part in ipairs(parts) do
		if part.functionCall then
			table.insert(functionCalls, part.functionCall)
		elseif part.text then
			thinkingText = thinkingText .. part.text
		end
	end

	-- IMPORTANT: Show AI's thinking/planning text IMMEDIATELY when there are tool calls
	-- This ensures the user sees explanations BEFORE tools execute, not just at the end
	if thinkingText ~= "" and #functionCalls > 0 and chatRenderer then
		local trimmedText = thinkingText:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmedText ~= "" then
			-- Display as a thought in the thinking panel for visibility during execution
			chatRenderer.addThought(trimmedText, "thinking")
		end
	end

	if #functionCalls == 0 then
		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] Agent completed in %d iterations", currentIteration))
		end
		return { success = true, text = thinkingText }
	end

	-- Start processing tool batch
	local batchContext = {
		iteration = currentIteration,
		functionCalls = functionCalls,
		functionResponses = {},
		statusCallback = statusCallback,
		chatRenderer = chatRenderer,
		thinkingText = thinkingText
	}

	return processToolBatch(1, batchContext)
end

--[[
    Process agentic loop - AI continues working until done
    @param statusCallback function - Called with (iteration, status) for UI updates
    @param chatRenderer table - Optional ChatRenderer module for displaying tool calls
    @return table - {success, text} or {awaitingApproval, operation, thinkingText} or {success: false, error}
]]
function OpenRouterClient.processLoop(statusCallback, chatRenderer)
	return continueLoopFromIteration(1, statusCallback, chatRenderer)
end

--[[
    Resume the paused agentic loop with user's approval decision
    @param approved boolean - Whether user approved the operation
    @return table - Same return format as processLoop
]]
function OpenRouterClient.resumeWithApproval(approved)
	if not pausedState then
		return { success = false, error = "No paused operation to resume" }
	end

	-- Validate that pausedState belongs to current task (prevent cross-task pollution)
	local currentTask = SessionManager.getCurrentTaskId()
	if pausedState.taskId and currentTask and pausedState.taskId ~= currentTask then
		warn(string.format("[Lux] Stale pausedState from task %s, current task is %s - clearing",
			pausedState.taskId, currentTask))
		pausedState = nil
		return { success = false, error = "Operation expired - it was from a different task. Please try again." }
	end

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Resuming with approval=%s", tostring(approved)))
	end

	local state = pausedState
	pausedState = nil

	local actualResult
	if approved then
		actualResult = Tools.applyOperation(state.operationId)

		if actualResult.error then
			-- End decision memory sequence on error
			if Constants.DECISION_MEMORY.enabled then
				DecisionMemory.endSequence(false, "Failed to apply: " .. actualResult.error)
			end
			return { success = false, error = "Failed to apply: " .. actualResult.error }
		end
	else
		Tools.rejectOperation(state.operationId)
		actualResult = { success = false, error = "User denied this operation" }
	end

	-- The paused operation was the LAST one added to functionResponses in the batch context
	-- We need to update it

	-- Backward compatibility check (if pausedState structure changed)
	if state.type == "batch_paused" then
		local responses = state.context.functionResponses
		local lastResponse = responses[#responses].functionResponse
		lastResponse.response = sanitizeToolResponse(actualResult)

		-- Resume processing the batch
		local result = processToolBatch(state.currentIndex + 1, state.context)

		-- Mark task complete via SessionManager if this is a final result (v3.0)
		if not result.awaitingApproval and not result.awaitingUserFeedback then
			if result.success then
				SessionManager.onTaskComplete(true, result.text and result.text:sub(1, 100) or "Completed")
			elseif result.error then
				SessionManager.onTaskComplete(false, result.error)
			end
		end

		return result

	else
		-- Fallback for legacy pause state (should not happen in new flow)
		return { success = false, error = "Invalid pause state" }
	end
end

--[[
    Resume the paused agentic loop with user's feedback response
    @param feedbackResponse table - { positive: boolean|nil, feedback: string }
    @return table - Same return format as processLoop
]]
function OpenRouterClient.resumeWithFeedback(feedbackResponse)
	if not pausedState then
		return { success = false, error = "No paused operation to resume" }
	end

	if pausedState.type ~= "feedback_paused" then
		return { success = false, error = "Paused state is not a feedback request" }
	end

	-- Validate that pausedState belongs to current task (prevent cross-task pollution)
	local currentTask = SessionManager.getCurrentTaskId()
	if pausedState.taskId and currentTask and pausedState.taskId ~= currentTask then
		warn(string.format("[Lux] Stale pausedState from task %s, current task is %s - clearing",
			pausedState.taskId, currentTask))
		pausedState = nil
		return { success = false, error = "Feedback request expired - it was from a different task. Please try again." }
	end

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Resuming with feedback: %s", feedbackResponse.feedback or "?"))
	end

	local state = pausedState
	pausedState = nil

	-- Build the feedback result to send back to AI
	local feedbackResult = {
		userFeedback = feedbackResponse.feedback or "No feedback provided",
		positive = feedbackResponse.positive,
		verificationType = state.feedbackRequest.verificationType,
		originalQuestion = state.feedbackRequest.question
	}

	-- Add interpretation hint for the AI
	if feedbackResponse.positive == true then
		feedbackResult.interpretation = "User confirmed everything looks correct. You can proceed."
	elseif feedbackResponse.positive == false then
		feedbackResult.interpretation = "User reported a problem. Investigate and fix before proceeding."
	else
		feedbackResult.interpretation = "User provided detailed feedback. Read and respond appropriately."
	end

	-- Update the last response in the batch context
	local responses = state.context.functionResponses
	local lastResponse = responses[#responses].functionResponse
	lastResponse.response = sanitizeToolResponse(feedbackResult)

	-- Resume processing the batch
	local result = processToolBatch(state.currentIndex + 1, state.context)

	-- Mark task complete via SessionManager if this is a final result (v3.0)
	if not result.awaitingApproval and not result.awaitingUserFeedback then
		if result.success then
			SessionManager.onTaskComplete(true, result.text and result.text:sub(1, 100) or "Completed")
		elseif result.error then
			SessionManager.onTaskComplete(false, result.error)
		end
	end

	return result
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
	conversationHistory = {}

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

	table.insert(conversationHistory, {
		role = "user",
		parts = {{ text = userMessage }}
	})

	local result = OpenRouterClient.processLoop(statusCallback, chatRenderer)

	-- Mark task complete via SessionManager (v3.0)
	-- This handles DecisionMemory.endSequence internally
	if result.success then
		SessionManager.onTaskComplete(true, result.text and result.text:sub(1, 100) or "Completed")
	elseif result.error then
		SessionManager.onTaskComplete(false, result.error)
	end
	-- Note: awaitingApproval doesn't end the task - it continues after approval

	return result
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

	table.insert(conversationHistory, {
		role = "user",
		parts = {{ text = userMessage }}
	})

	local result = OpenRouterClient.processLoop(statusCallback, chatRenderer)

	-- Mark task complete via SessionManager (v3.0)
	if result.success then
		SessionManager.onTaskComplete(true, result.text and result.text:sub(1, 100) or "Completed")
	elseif result.error then
		SessionManager.onTaskComplete(false, result.error)
	end

	return result
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--[[
    Check if API is configured
    @return boolean, string - isConfigured, error message if not
]]
function OpenRouterClient.checkConfiguration()
	local key = getApiKey()
	if not key then
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

function OpenRouterClient.estimateTokenCount()
	return estimateTokenCount()
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
