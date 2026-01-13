--[[
    CompressionFallback.lua - Self-Healing Conversation Compression (v1.0)

    Provides multiple fallback strategies when AI-based summarization fails.
    Prevents catastrophic context loss that occurs in current implementation.

    Fallback Hierarchy:
    1. AI Summary (best, but can fail)
    2. Structured Truncation (preserves key information)
    3. Smart Sampling (keeps diverse messages)
    4. Simple Truncation (last resort)
]]

local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Constants)

local CompressionFallback = {}

-- ============================================================================
-- COMPRESSION STRATEGIES
-- ============================================================================

--[[
    Strategy 1: Structured Truncation
    Extract and preserve key information from conversation history
    @param messages table - Messages to compress
    @return string - Structured summary
]]
local function structuredTruncation(messages)
	local summary = {
		"[Conversation History - Structured Summary]",
		""
	}

	-- Extract key elements
	local userQuestions = {}
	local aiActions = {}
	local toolCalls = {}
	local errors = {}

	for _, msg in ipairs(messages) do
		if msg.role == "user" and msg.parts then
			-- Extract user messages
			for _, part in ipairs(msg.parts) do
				if part.text then
					-- Only add meaningful user messages (not system summaries)
					if not part.text:find("SYSTEM:") and #part.text > 10 then
						table.insert(userQuestions, part.text:sub(1, 200))  -- First 200 chars
					end
				end
			end

		elseif msg.role == "model" and msg.parts then
			-- Extract AI actions and tool calls
			for _, part in ipairs(msg.parts) do
				if part.text then
					local text = part.text
					-- Extract key phrases
					if text:find("create") or text:find("add") or text:find("build") then
						table.insert(aiActions, text:sub(1, 150))
					end
				end

				if part.functionCall then
					-- Record tool usage
					local toolName = part.functionCall.name
					toolCalls[toolName] = (toolCalls[toolName] or 0) + 1
				end

				if part.functionResponse then
					local response = part.functionResponse.response
					if type(response) == "table" and response.error then
						table.insert(errors, string.format("%s: %s",
							part.functionResponse.name,
							response.error:sub(1, 100)))
					end
				end
			end
		end
	end

	-- Build structured summary
	if #userQuestions > 0 then
		table.insert(summary, "User Requests:")
		for i, q in ipairs(userQuestions) do
			if i <= 5 then  -- Keep first 5
				table.insert(summary, "  • " .. q)
			end
		end
		if #userQuestions > 5 then
			table.insert(summary, string.format("  ... and %d more requests", #userQuestions - 5))
		end
		table.insert(summary, "")
	end

	if #aiActions > 0 then
		table.insert(summary, "AI Actions Taken:")
		for i, action in ipairs(aiActions) do
			if i <= 5 then  -- Keep first 5
				table.insert(summary, "  • " .. action)
			end
		end
		if #aiActions > 5 then
			table.insert(summary, string.format("  ... and %d more actions", #aiActions - 5))
		end
		table.insert(summary, "")
	end

	local toolSummary = {}
	for tool, count in pairs(toolCalls) do
		table.insert(toolSummary, string.format("%s (%dx)", tool, count))
	end
	if #toolSummary > 0 then
		table.insert(summary, "Tools Used: " .. table.concat(toolSummary, ", "))
		table.insert(summary, "")
	end

	if #errors > 0 then
		table.insert(summary, "Errors Encountered:")
		for i, err in ipairs(errors) do
			if i <= 3 then  -- Keep first 3 errors
				table.insert(summary, "  • " .. err)
			end
		end
		if #errors > 3 then
			table.insert(summary, string.format("  ... and %d more errors", #errors - 3))
		end
		table.insert(summary, "")
	end

	table.insert(summary, string.format("Total Messages Compressed: %d", #messages))

	return table.concat(summary, "\n")
end

--[[
    Strategy 2: Smart Sampling
    Keep a diverse sample of messages instead of just truncating
    @param messages table - Messages to compress
    @param targetCount number - Target number of messages to keep
    @return table - Sampled messages
]]
local function smartSampling(messages, targetCount)
	if #messages <= targetCount then
		return messages
	end

	local sampled = {}

	-- Always keep first and last few messages
	local keepFirst = math.min(3, math.floor(targetCount * 0.2))
	local keepLast = math.min(3, math.floor(targetCount * 0.3))
	local keepMiddle = targetCount - keepFirst - keepLast

	-- Keep first messages
	for i = 1, keepFirst do
		if messages[i] then
			table.insert(sampled, messages[i])
		end
	end

	-- Sample middle messages evenly
	if keepMiddle > 0 then
		local middleStart = keepFirst + 1
		local middleEnd = #messages - keepLast
		local step = math.max(1, math.floor((middleEnd - middleStart) / keepMiddle))

		for i = middleStart, middleEnd, step do
			if #sampled < (keepFirst + keepMiddle) and messages[i] then
				table.insert(sampled, messages[i])
			end
		end
	end

	-- Keep last messages
	for i = math.max(1, #messages - keepLast + 1), #messages do
		if messages[i] then
			table.insert(sampled, messages[i])
		end
	end

	return sampled
end

--[[
    Strategy 3: Simple Truncation with Context Marker
    Just truncate, but add a clear marker
    @param messages table
    @param keepCount number
    @return table
]]
local function simpleTruncation(messages, keepCount)
	local truncated = {}
	local startIndex = math.max(1, #messages - keepCount + 1)

	for i = startIndex, #messages do
		table.insert(truncated, messages[i])
	end

	return truncated
end

-- ============================================================================
-- MAIN COMPRESSION FUNCTION
-- ============================================================================

--[[
    Compress conversation history with multiple fallback strategies
    @param messages table - Conversation history
    @param summarizeFn function|nil - Optional AI summarization function
    @param config table|nil - Configuration {preserveCount, summaryModel}
    @return table - {success: bool, compressed: table, strategy: string, summary: string|nil}
]]
function CompressionFallback.compress(messages, summarizeFn, config)
	config = config or {}
	local preserveCount = config.preserveCount or Constants.MESSAGES_TO_PRESERVE or 10

	if #messages <= (preserveCount + 2) then
		-- No compression needed
		return {
			success = true,
			compressed = messages,
			strategy = "none",
			summary = nil
		}
	end

	-- Extract messages to compress
	local keepStartIndex = #messages - preserveCount + 1
	local toCompress = {}
	for i = 1, keepStartIndex - 1 do
		table.insert(toCompress, messages[i])
	end

	local preserved = {}
	for i = keepStartIndex, #messages do
		table.insert(preserved, messages[i])
	end

	-- ========================================================================
	-- STRATEGY 1: AI-Based Summarization (Best Quality)
	-- ========================================================================
	if summarizeFn then
		local success, summary = pcall(summarizeFn, toCompress)

		if success and summary and type(summary) == "string" and #summary > 50 then
			-- AI summary succeeded!
			local compressed = {
				{
					role = "user",
					parts = {{
						text = string.format(
							"[COMPRESSED HISTORY - AI Summary]\n\n%s\n\n(Original: %d messages, Preserved: %d recent messages)",
							summary,
							#toCompress,
							#preserved
						)
					}}
				},
				{
					role = "model",
					parts = {{ text = "Understood. Continuing with this context." }}
				}
			}

			-- Append preserved messages
			for _, msg in ipairs(preserved) do
				table.insert(compressed, msg)
			end

			if Constants.DEBUG then
				print(string.format("[CompressionFallback] Strategy 1 (AI Summary) succeeded: %d -> %d messages",
					#messages, #compressed))
			end

			return {
				success = true,
				compressed = compressed,
				strategy = "ai_summary",
				summary = summary
			}
		else
			if Constants.DEBUG then
				warn("[CompressionFallback] Strategy 1 (AI Summary) failed, trying fallback...")
			end
		end
	end

	-- ========================================================================
	-- STRATEGY 2: Structured Truncation (Good Quality, Always Works)
	-- ========================================================================
	local structuredSummary = structuredTruncation(toCompress)

	local compressed = {
		{
			role = "user",
			parts = {{
				text = structuredSummary
			}}
		},
		{
			role = "model",
			parts = {{ text = "Understood. Continuing with this context." }}
		}
	}

	-- Append preserved messages
	for _, msg in ipairs(preserved) do
		table.insert(compressed, msg)
	end

	if Constants.DEBUG then
		print(string.format("[CompressionFallback] Strategy 2 (Structured Truncation): %d -> %d messages",
			#messages, #compressed))
	end

	return {
		success = true,
		compressed = compressed,
		strategy = "structured_truncation",
		summary = structuredSummary
	}
end

--[[
    Estimate token count for messages
    @param messages table
    @return number - Estimated tokens
]]
function CompressionFallback.estimateTokens(messages)
	local totalChars = 0

	for _, msg in ipairs(messages) do
		if msg.parts then
			for _, part in ipairs(msg.parts) do
				if part.text then
					totalChars = totalChars + #part.text
				end
				if part.functionCall then
					-- Estimate function call size
					local encoded = HttpService:JSONEncode(part.functionCall)
					totalChars = totalChars + #encoded
				end
				if part.functionResponse then
					-- Estimate function response size
					local encoded = HttpService:JSONEncode(part.functionResponse)
					totalChars = totalChars + #encoded
				end
			end
		end
	end

	-- Rough estimate: 4 chars per token
	return math.ceil(totalChars / 4)
end

--[[
    Check if compression is needed
    @param messages table
    @param threshold number|nil - Token threshold
    @return bool - True if compression needed
]]
function CompressionFallback.needsCompression(messages, threshold)
	threshold = threshold or Constants.COMPRESSION_THRESHOLD or 50000
	local estimatedTokens = CompressionFallback.estimateTokens(messages)
	return estimatedTokens > threshold
end

return CompressionFallback
