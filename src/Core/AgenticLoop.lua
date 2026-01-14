--[[
	AgenticLoop.lua
	Core module: Agentic Loop & Tool Execution

	Responsibilities:
	- Execute the agentic loop (AI continues working until done)
	- Process tool batches sequentially
	- Handle approval/feedback pausing and resumption
	- Coordinate tool execution with safety checks
	- Manage conversation flow (start/continue)

	This module implements the core iterative loop where the AI thinks,
	executes tools, and continues until it completes the task or requires
	user approval/feedback.
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Tools = require(script.Parent.Parent.Tools.init)
local SessionManager = require(script.Parent.Parent.Coordination.SessionManager)
local OutputValidator = require(script.Parent.Parent.Safety.OutputValidator)
local ToolResilience = require(script.Parent.Parent.Safety.ToolResilience)
local TaskPlanner = require(script.Parent.Parent.Planning.TaskPlanner)
local DecisionMemory = require(script.Parent.Parent.Memory.DecisionMemory)

-- Import Core modules
local ApiClient = require(script.Parent.ApiClient)
local ConversationHistory = require(script.Parent.ConversationHistory)
local MessageConverter = require(script.Parent.MessageConverter)

local AgenticLoop = {}

-- ============================================================================
-- MODULE-LEVEL STATE
-- ============================================================================

-- Store callback functions provided by OpenRouterClient
local callOpenRouterAPIFn = nil

-- ============================================================================
-- OPERATION DEFINITIONS
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

-- ============================================================================
-- PAUSE STATE MANAGEMENT
-- ============================================================================

-- Pause state for resuming after approval
local pausedState = nil

-- Forward declaration
local continueLoopFromIteration

-- ============================================================================
-- TOOL BATCH PROCESSING
-- ============================================================================

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
					response = MessageConverter.sanitizeResponse(blockedResult)
				}
			})
			-- Return immediately - agent must acknowledge the block
			ConversationHistory.addMessage({
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
				context.chatRenderer.addThought("⚠️ Tool call validation failed: " .. validationError, "warning")
			end

			toolResult = {
				error = validationError,
				validationFailed = true,
				suggestions = validation.suggestions
			}
			toolSuccess = false
			sanitizedResult = MessageConverter.sanitizeResponse(toolResult)

		else
			-- 3. Check ErrorPredictor for warnings (non-blocking)
			if cbWarning and context.chatRenderer then
				context.chatRenderer.addThought("⚠ " .. cbWarning, "warning")
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

			sanitizedResult = MessageConverter.sanitizeResponse(toolResult)
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
	ConversationHistory.addMessage({
		role = "user",
		parts = context.functionResponses
	})

	-- Continue to next iteration
	return continueLoopFromIteration(context.iteration + 1, context.statusCallback, context.chatRenderer)
end

-- ============================================================================
-- AGENTIC LOOP ITERATION
-- ============================================================================

--[[
	Continue the agentic loop from a specific iteration (internal)
	@param currentIteration number - Current iteration number
	@param statusCallback function - Callback for status updates
	@param chatRenderer table - Optional ChatRenderer module
	@return table - Result of iteration or final completion
]]
continueLoopFromIteration = function(currentIteration, statusCallback, chatRenderer)
	-- If we exceeded max iterations
	if currentIteration > Constants.MAX_AGENT_ITERATIONS then
		return {
			success = false,
			error = string.format("Agent exceeded maximum iterations (%d)", Constants.MAX_AGENT_ITERATIONS)
		}
	end

	-- Compress history if needed
	ConversationHistory.compressIfNeeded(ApiClient.generateSummary)

	if statusCallback then
		statusCallback(currentIteration, "thinking")
	end

	-- Call API
	local response = callOpenRouterAPIFn(ConversationHistory.getHistory())

	if not response.success then
		return { success = false, error = response.error }
	end

	local parts = response.response.parts

	ConversationHistory.addMessage({
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

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
	Process agentic loop - AI continues working until done
	@param statusCallback function - Called with (iteration, status) for UI updates
	@param chatRenderer table - Optional ChatRenderer module for displaying tool calls
	@param callOpenRouterAPI function - Function to call OpenRouter API
	@return table - {success, text} or {awaitingApproval, operation, thinkingText} or {success: false, error}
]]
function AgenticLoop.processLoop(statusCallback, chatRenderer, callOpenRouterAPI)
	-- Store the API function for use in continueLoopFromIteration
	callOpenRouterAPIFn = callOpenRouterAPI
	return continueLoopFromIteration(1, statusCallback, chatRenderer)
end

--[[
	Resume the paused agentic loop with user's approval decision
	@param approved boolean - Whether user approved the operation
	@return table - Same return format as processLoop
]]
function AgenticLoop.resumeWithApproval(approved)
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
		lastResponse.response = MessageConverter.sanitizeResponse(actualResult)

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
function AgenticLoop.resumeWithFeedback(feedbackResponse)
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
	lastResponse.response = MessageConverter.sanitizeResponse(feedbackResult)

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
-- CONVERSATION FUNCTIONS
-- ============================================================================

--[[
	Start a new conversation
	@param userMessage string - User's message
	@param statusCallback function - Called with (iteration, status) for UI updates
	@param chatRenderer table - Optional ChatRenderer module for displaying tool calls
	@param callOpenRouterAPI function - Function to call OpenRouter API
	@return table - {success, text} or {awaitingApproval, operation, thinkingText}
]]
function AgenticLoop.startConversation(userMessage, statusCallback, chatRenderer, callOpenRouterAPI)
	-- Reset conversation history
	ConversationHistory.resetConversation()

	-- Store user message for adaptive prompt building (handled by caller)
	-- Use SessionManager for coordinated new task initialization (handled by caller)

	-- Add user message to history
	ConversationHistory.addMessage({
		role = "user",
		parts = {{ text = userMessage }}
	})

	local result = AgenticLoop.processLoop(statusCallback, chatRenderer, callOpenRouterAPI)

	-- Mark task complete via SessionManager (v3.0)
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
	@param callOpenRouterAPI function - Function to call OpenRouter API
	@return table - {success, text} or {awaitingApproval, operation, thinkingText}
]]
function AgenticLoop.continueConversation(userMessage, statusCallback, chatRenderer, callOpenRouterAPI)
	-- Update user message for adaptive prompt (handled by caller)

	-- Mark previous task as complete before starting new one (v3.0)
	SessionManager.onTaskComplete(true, "Continuing to next task")

	-- Use SessionManager for coordinated new task initialization (handled by caller)

	ConversationHistory.addMessage({
		role = "user",
		parts = {{ text = userMessage }}
	})

	local result = AgenticLoop.processLoop(statusCallback, chatRenderer, callOpenRouterAPI)

	-- Mark task complete via SessionManager (v3.0)
	if result.success then
		SessionManager.onTaskComplete(true, result.text and result.text:sub(1, 100) or "Completed")
	elseif result.error then
		SessionManager.onTaskComplete(false, result.error)
	end

	return result
end

return AgenticLoop
