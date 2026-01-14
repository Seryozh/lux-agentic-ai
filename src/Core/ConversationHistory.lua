--[[
	ConversationHistory.lua
	Core module: Conversation State Management

	Responsibilities:
	- Maintain conversation history array
	- Track tool execution logs
	- Token estimation
	- History compression coordination
	- Add/retrieve messages from conversation state

	This module manages the in-memory conversation state and provides
	utilities for token estimation and history compression.
]]

local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.Shared.Constants)

local ConversationHistory = {}

-- ============================================================================
-- STATE
-- ============================================================================

local conversationHistory = {}

-- Tool execution tracking for completion summary
local toolExecutionLog = {
	items = {},        -- Array of { toolName, description, success }
	successful = 0,
	failed = 0,
	totalTools = 0
}

-- ============================================================================
-- CONVERSATION HISTORY MANAGEMENT
-- ============================================================================

--[[
	Get conversation history
	@return table - Array of conversation messages
]]
function ConversationHistory.getHistory()
	return conversationHistory
end

--[[
	Add a message to conversation history
	@param message table - Message with role and parts
]]
function ConversationHistory.addMessage(message)
	table.insert(conversationHistory, message)
end

--[[
	Reset conversation history and tracking data
]]
function ConversationHistory.resetConversation()
	conversationHistory = {}
	-- Reset tool execution log
	toolExecutionLog = {
		items = {},
		successful = 0,
		failed = 0,
		totalTools = 0
	}
end

-- ============================================================================
-- TOOL EXECUTION TRACKING
-- ============================================================================

--[[
	Reset tool execution log (call at start of new task)
]]
function ConversationHistory.resetToolLog()
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
function ConversationHistory.recordToolExecution(toolName, description, success)
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
function ConversationHistory.getToolExecutionSummary()
	return {
		totalTools = toolExecutionLog.totalTools,
		successful = toolExecutionLog.successful,
		failed = toolExecutionLog.failed,
		items = toolExecutionLog.items
	}
end

-- ============================================================================
-- TOKEN ESTIMATION
-- ============================================================================

--[[
	Estimate conversation token count (rough estimate)
	@return number - Estimated token count
]]
function ConversationHistory.estimateTokenCount()
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

-- ============================================================================
-- HISTORY COMPRESSION
-- ============================================================================

--[[
	Compress old conversation history when token count gets high
	Uses CompressionFallback for multi-strategy compression with zero context loss (v4.0)
	@param generateSummaryFn function - Function to call API for summary generation
]]
function ConversationHistory.compressIfNeeded(generateSummaryFn)
	local CompressionFallback = require(script.Parent.Parent.Context.CompressionFallback)

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
		generateSummaryFn,  -- Pass AI summary function as fallback
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

return ConversationHistory
