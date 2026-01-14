--[[
    DecisionMemory.lua
    Pattern learning from successful and failed operations
    
    This module learns from the agent's actions:
    1. Records tool sequences that worked
    2. Tracks patterns that failed repeatedly
    3. Suggests proven approaches for similar tasks
    4. Persists across sessions using StringValue storage
]]

local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.Shared.Constants)

local DecisionMemory = {}

-- ============================================================================
-- STATE
-- ============================================================================

-- In-memory pattern storage
local patterns = {
	successful = {},  -- Patterns that worked
	failed = {}       -- Patterns that failed
}

-- Current sequence being recorded
local currentSequence = nil

-- ============================================================================
-- HELPER FUNCTIONS (defined early for use throughout module)
-- ============================================================================

-- Common words to ignore in keyword extraction (stop words)
local STOP_WORDS = {
	-- Articles & pronouns
	"this", "that", "these", "those", "with", "from", "into", "have", "been",
	"will", "would", "could", "should", "about", "your", "their", "there",
	"what", "when", "where", "which", "while", "some", "more", "also", "just",
	"very", "each", "other", "than", "then", "only", "over", "such", "make",
	"made", "like", "want", "need", "please", "help", "sure", "okay", "yeah",
	-- Common coding terms that are too generic
	"code", "file", "thing", "stuff", "work", "something", "anything",
}

local stopWordSet = {}
for _, word in ipairs(STOP_WORDS) do
	stopWordSet[word] = true
end

--[[
    Extract meaningful keywords from task description
    @param text string
    @return table - Set of keywords (word -> true)
]]
local function extractKeywords(text)
	local keywords = {}
	local lowerText = text:lower()

	for word in lowerText:gmatch("%w+") do
		-- Skip short words, numbers, and stop words
		if #word >= 4 and not tonumber(word) and not stopWordSet[word] then
			keywords[word] = true
		end
	end

	return keywords  -- Return as set for easier matching
end

--[[
    Convert keyword set to array (for storage)
    @param keywordSet table
    @return table - Array of keywords
]]
local function keywordsToArray(keywordSet)
	local result = {}
	for word in pairs(keywordSet) do
		table.insert(result, word)
	end
	return result
end

--[[
    Extract just tool names from tool records
    @param tools table - Array of tool records
    @return table - Array of tool names
]]
local function extractToolNames(tools)
	local names = {}
	for _, tool in ipairs(tools) do
		table.insert(names, tool.name)
	end
	return names
end

-- ============================================================================
-- STORAGE
-- ============================================================================

local function getStorageLocation()
	return game:FindFirstChild(Constants.PROJECT_CONTEXT.storageLocation)
		or game:GetService(Constants.PROJECT_CONTEXT.storageLocation)
end

local function getMemoryValue()
	local location = getStorageLocation()
	return location:FindFirstChild(Constants.DECISION_MEMORY.storageName)
end

local function ensureMemoryValue()
	local location = getStorageLocation()
	local existing = location:FindFirstChild(Constants.DECISION_MEMORY.storageName)

	if existing then
		return existing
	end

	local memoryValue = Instance.new("StringValue")
	memoryValue.Name = Constants.DECISION_MEMORY.storageName
	memoryValue.Value = HttpService:JSONEncode({
		version = 1,
		patterns = { successful = {}, failed = {} },
		metadata = {
			created = os.time(),
			lastModified = os.time()
		}
	})
	memoryValue.Parent = location

	return memoryValue
end

--[[
    Load patterns from persistent storage
]]
function DecisionMemory.load()
	if not Constants.DECISION_MEMORY.enabled then
		return
	end

	local memoryValue = getMemoryValue()
	if not memoryValue then
		return
	end

	local success, data = pcall(function()
		return HttpService:JSONDecode(memoryValue.Value)
	end)

	if success and data.patterns then
		patterns = data.patterns

		if Constants.DEBUG then
			print(string.format("[DecisionMemory] Loaded %d successful, %d failed patterns",
				#patterns.successful, #patterns.failed
				))
		end
	end
end

--[[
    Save patterns to persistent storage
]]
function DecisionMemory.save()
	if not Constants.DECISION_MEMORY.enabled then
		return
	end

	-- Enforce max patterns limit
	while #patterns.successful > Constants.DECISION_MEMORY.maxPatterns do
		-- Remove oldest (by lastUsed)
		local oldestIdx = 1
		local oldestTime = patterns.successful[1].lastUsed or 0
		for i, p in ipairs(patterns.successful) do
			if (p.lastUsed or 0) < oldestTime then
				oldestIdx = i
				oldestTime = p.lastUsed or 0
			end
		end
		table.remove(patterns.successful, oldestIdx)
	end

	while #patterns.failed > Constants.DECISION_MEMORY.maxPatterns do
		table.remove(patterns.failed, 1)
	end

	local memoryValue = ensureMemoryValue()

	local data = {
		version = 1,
		patterns = patterns,
		metadata = {
			lastModified = os.time()
		}
	}

	local success, encoded = pcall(function()
		return HttpService:JSONEncode(data)
	end)

	if success then
		memoryValue.Value = encoded
	end
end

-- ============================================================================
-- SEQUENCE RECORDING
-- ============================================================================

--[[
    Start recording a new tool sequence
    @param taskDescription string - What the user asked for
    @param taskAnalysis table - From TaskPlanner.analyzeTask()
]]
function DecisionMemory.startSequence(taskDescription, taskAnalysis)
	if not Constants.DECISION_MEMORY.enabled then
		return
	end

	currentSequence = {
		id = HttpService:GenerateGUID(false),
		task = taskDescription:sub(1, 200),  -- Truncate for storage
		taskType = taskAnalysis and taskAnalysis.complexity or "unknown",
		capabilities = taskAnalysis and taskAnalysis.capabilities or {},
		tools = {},
		startTime = tick(),
		outcome = "in_progress"  -- in_progress, success, failed
	}

	if Constants.DEBUG then
		print(string.format("[DecisionMemory] Started sequence: %s", currentSequence.id:sub(1, 8)))
	end
end

--[[
    Record a tool call in the current sequence
    @param toolName string
    @param success boolean
    @param resultSummary string - Brief description of result
]]
function DecisionMemory.recordTool(toolName, success, resultSummary)
	if not Constants.DECISION_MEMORY.enabled or not currentSequence then
		return
	end

	table.insert(currentSequence.tools, {
		name = toolName,
		success = success,
		summary = (resultSummary or ""):sub(1, 100),
		timestamp = tick()
	})

	if Constants.DEBUG then
		print(string.format("[DecisionMemory] Recorded: %s (%s)",
			toolName, success and "success" or "failed"
			))
	end
end

--[[
    End the current sequence and save if successful
    @param success boolean - Whether the overall task succeeded
    @param summary string - Final outcome summary
]]
function DecisionMemory.endSequence(success, summary)
	if not Constants.DECISION_MEMORY.enabled or not currentSequence then
		return
	end

	currentSequence.outcome = success and "success" or "failed"
	currentSequence.endTime = tick()
	currentSequence.duration = currentSequence.endTime - currentSequence.startTime
	currentSequence.summary = (summary or ""):sub(1, 200)

	-- Calculate success rate for tools in sequence
	local successCount = 0
	for _, tool in ipairs(currentSequence.tools) do
		if tool.success then
			successCount = successCount + 1
		end
	end
	currentSequence.toolSuccessRate = #currentSequence.tools > 0 
		and (successCount / #currentSequence.tools) 
		or 0

	-- Store pattern
	local pattern = {
		id = currentSequence.id,
		taskKeywords = extractKeywords(currentSequence.task),
		capabilities = currentSequence.capabilities,
		toolSequence = extractToolNames(currentSequence.tools),
		toolCount = #currentSequence.tools,
		duration = currentSequence.duration,
		toolSuccessRate = currentSequence.toolSuccessRate,
		created = os.time(),
		lastUsed = os.time(),
		useCount = 1
	}

	if success then
		table.insert(patterns.successful, pattern)
	else
		table.insert(patterns.failed, pattern)
	end

	DecisionMemory.save()

	if Constants.DEBUG then
		print(string.format("[DecisionMemory] Sequence ended: %s (%d tools, %.0f%% success rate)",
			success and "SUCCESS" or "FAILED",
			#currentSequence.tools,
			currentSequence.toolSuccessRate * 100
			))
	end

	currentSequence = nil
end

-- Make it accessible for external use if needed
function DecisionMemory._extractKeywords(text)
	return extractKeywords(text)
end

-- ============================================================================
-- PATTERN MATCHING & SUGGESTIONS
-- ============================================================================

--[[
    Find patterns that match a task description
    @param taskDescription string
    @param taskAnalysis table - From TaskPlanner
    @return table - Array of matching patterns with relevance scores
]]
function DecisionMemory.findMatchingPatterns(taskDescription, taskAnalysis)
	if not Constants.DECISION_MEMORY.enabled then
		return { successful = {}, failed = {} }
	end

	-- Load latest
	DecisionMemory.load()

	local taskKeywords = extractKeywords(taskDescription)
	local taskCapabilities = taskAnalysis and taskAnalysis.capabilities or {}

	-- Convert task capabilities to set for faster lookup
	local taskCapabilitySet = {}
	for _, cap in ipairs(taskCapabilities) do
		taskCapabilitySet[cap] = true
	end

	local minKeywordMatches = Constants.DECISION_MEMORY.minKeywordMatches or 2
	local requireCapabilityMatch = Constants.DECISION_MEMORY.requireCapabilityMatch

	local function scorePattern(pattern)
		local score = 0
		local keywordMatches = 0
		local capabilityMatches = 0

		-- Keyword matching - pattern.taskKeywords could be array or set
		local patternKeywords = pattern.taskKeywords or {}
		if type(patternKeywords) == "table" then
			-- Handle both array and set formats
			if patternKeywords[1] ~= nil then
				-- Array format (old patterns)
				for _, keyword in ipairs(patternKeywords) do
					if taskKeywords[keyword] then
						keywordMatches = keywordMatches + 1
						score = score + 10
					end
				end
			else
				-- Set format (new patterns)
				for keyword in pairs(patternKeywords) do
					if taskKeywords[keyword] then
						keywordMatches = keywordMatches + 1
						score = score + 10
					end
				end
			end
		end

		-- Capability matching
		for _, cap in ipairs(pattern.capabilities or {}) do
			if taskCapabilitySet[cap] then
				capabilityMatches = capabilityMatches + 1
				score = score + 20
			end
		end

		-- Early rejection: not enough keyword matches
		if keywordMatches < minKeywordMatches then
			return 0, keywordMatches, capabilityMatches
		end

		-- Early rejection: no capability overlap when required
		if requireCapabilityMatch and #taskCapabilities > 0 and capabilityMatches == 0 then
			return 0, keywordMatches, capabilityMatches
		end

		-- ==================
		-- POSITIVE SIGNALS
		-- ==================

		-- Recency bonus (reduced for older patterns)
		local daysSinceUse = (os.time() - (pattern.lastUsed or 0)) / 86400
		if daysSinceUse < 1 then
			score = score + 15
		elseif daysSinceUse < 3 then
			score = score + 10
		elseif daysSinceUse < 7 then
			score = score + 5
		end
		-- No bonus for patterns older than 7 days

		-- Usage frequency bonus (capped)
		local useCount = pattern.useCount or 1
		score = score + math.min(useCount * 2, 10)

		-- Tool success rate consideration
		score = score + (pattern.toolSuccessRate or 0) * 10

		-- ==================
		-- NEGATIVE SIGNALS
		-- ==================

		-- High failure rate penalty
		local failureCount = pattern.failureCount or 0
		local totalUses = pattern.useCount or 1
		local failureRate = failureCount / math.max(1, totalUses)
		if failureRate > 0.3 then
			score = score - 20
		elseif failureRate > 0.1 then
			score = score - 10
		end

		-- Inefficient pattern penalty (took too many iterations)
		local avgIterations = pattern.avgIterations or 0
		if avgIterations > 15 then
			score = score - 15
		elseif avgIterations > 10 then
			score = score - 10
		elseif avgIterations > 7 then
			score = score - 5
		end

		-- Old pattern penalty (might be outdated)
		if daysSinceUse > 14 then
			score = score - 10
		elseif daysSinceUse > 7 then
			score = score - 5
		end

		-- Ensure score doesn't go negative
		score = math.max(0, score)

		return score, keywordMatches, capabilityMatches
	end

	-- Score all patterns
	local scoredSuccessful = {}
	for _, pattern in ipairs(patterns.successful) do
		local score, keywordMatches, capabilityMatches = scorePattern(pattern)
		if score > 20 then  -- Minimum threshold
			table.insert(scoredSuccessful, { 
				pattern = pattern, 
				score = score,
				keywordMatches = keywordMatches,
				capabilityMatches = capabilityMatches
			})
		end
	end

	local scoredFailed = {}
	for _, pattern in ipairs(patterns.failed) do
		local score, keywordMatches, capabilityMatches = scorePattern(pattern)
		if score > 20 then
			table.insert(scoredFailed, { 
				pattern = pattern, 
				score = score,
				keywordMatches = keywordMatches,
				capabilityMatches = capabilityMatches
			})
		end
	end

	-- Sort by score
	table.sort(scoredSuccessful, function(a, b) return a.score > b.score end)
	table.sort(scoredFailed, function(a, b) return a.score > b.score end)

	return {
		successful = scoredSuccessful,
		failed = scoredFailed
	}
end

--[[
    Calculate confidence score for a pattern match
    @param match table - Scored pattern match
    @param taskAnalysis table
    @return number - Confidence between 0.1 and 1.0
]]
local function calculateConfidence(match, taskAnalysis)
	local confidence = 0.5  -- Base

	-- ==================
	-- POSITIVE SIGNALS
	-- ==================

	-- Higher keyword overlap = higher confidence
	local keywordBonus = (match.keywordMatches or 0) / 10 * 0.2
	confidence = confidence + keywordBonus

	-- Capability match is a strong signal
	if (match.capabilityMatches or 0) > 0 then
		confidence = confidence + 0.15
	end

	-- Recent success boosts confidence
	local daysSinceUse = (os.time() - (match.pattern.lastUsed or 0)) / 86400
	if daysSinceUse < 1 then
		confidence = confidence + 0.1
	elseif daysSinceUse < 3 then
		confidence = confidence + 0.05
	end

	-- High tool success rate in pattern
	confidence = confidence + (match.pattern.toolSuccessRate or 0) * 0.15

	-- High use count indicates reliability
	local useCount = match.pattern.useCount or 1
	if useCount > 5 then
		confidence = confidence + 0.1
	elseif useCount > 2 then
		confidence = confidence + 0.05
	end

	-- ==================
	-- NEGATIVE SIGNALS
	-- ==================

	-- High failure rate penalty
	local failureCount = match.pattern.failureCount or 0
	local totalUses = match.pattern.useCount or 1
	local failureRate = failureCount / math.max(1, totalUses)
	if failureRate > 0.3 then
		confidence = confidence - 0.2
	elseif failureRate > 0.1 then
		confidence = confidence - 0.1
	end

	-- Inefficient pattern penalty (took too many iterations)
	local avgIterations = match.pattern.avgIterations or 0
	if avgIterations > 10 then
		confidence = confidence - 0.1
	elseif avgIterations > 7 then
		confidence = confidence - 0.05
	end

	-- Old pattern penalty (might be outdated)
	if daysSinceUse > 14 then
		confidence = confidence - 0.1
	elseif daysSinceUse > 7 then
		confidence = confidence - 0.05
	end

	-- Clamp to valid range
	return math.max(0.1, math.min(1.0, confidence))
end

--[[
    Get suggestions based on similar past tasks
    @param taskDescription string
    @param taskAnalysis table
    @return table - { suggestions: array, warnings: array }
]]
function DecisionMemory.getSuggestions(taskDescription, taskAnalysis)
	if not Constants.DECISION_MEMORY.enabled then
		return { suggestions = {}, warnings = {} }
	end

	local matches = DecisionMemory.findMatchingPatterns(taskDescription, taskAnalysis)
	local result = {
		suggestions = {},
		warnings = {}
	}

	-- Suggestions from successful patterns (with confidence)
	for i, match in ipairs(matches.successful) do
		if i > 3 then break end  -- Limit to top 3

		local confidence = calculateConfidence(match, taskAnalysis)

		if confidence >= 0.5 then  -- Only suggest with reasonable confidence
			local confidenceLabel
			if confidence >= 0.8 then
				confidenceLabel = "high"
			elseif confidence >= 0.6 then
				confidenceLabel = "medium"
			else
				confidenceLabel = "low"
			end

			table.insert(result.suggestions, {
				type = "proven_approach",
				message = string.format(
					"[%s confidence: %.0f%%] Similar task succeeded using: %s",
					confidenceLabel,
					confidence * 100,
					table.concat(match.pattern.toolSequence or {}, " ? ")
				),
				confidence = confidence,
				confidenceLabel = confidenceLabel,
				toolSequence = match.pattern.toolSequence,
				patternId = match.pattern.id
			})

			-- Update usage for best match only
			if i == 1 then
				match.pattern.lastUsed = os.time()
				match.pattern.useCount = (match.pattern.useCount or 0) + 1
				DecisionMemory.save()
			end
		end
	end

	-- Warnings from failed patterns
	for _, match in ipairs(matches.failed) do
		if match.score > 30 then  -- Strong match to a failed pattern
			local confidence = calculateConfidence(match, taskAnalysis)

			table.insert(result.warnings, {
				type = "similar_failed",
				message = string.format(
					"?? A similar approach failed before (%.0f%% match). Avoid: %s",
					confidence * 100,
					table.concat(match.pattern.toolSequence or {}, " ? ")
				),
				patternId = match.pattern.id,
				matchStrength = confidence
			})
		end
	end

	return result
end

-- ============================================================================
-- FORMATTING FOR PROMPT
-- ============================================================================

--[[
    Format suggestions for inclusion in LLM prompt
    @param taskDescription string
    @param taskAnalysis table
    @return string - Formatted text
]]
function DecisionMemory.formatForPrompt(taskDescription, taskAnalysis)
	if not Constants.DECISION_MEMORY.enabled then
		return ""
	end

	local suggestions = DecisionMemory.getSuggestions(taskDescription, taskAnalysis)

	if #suggestions.suggestions == 0 and #suggestions.warnings == 0 then
		return ""
	end

	local parts = { "\n## Past Experience\n" }

	if #suggestions.suggestions > 0 then
		table.insert(parts, "**What worked before:**")
		for _, sugg in ipairs(suggestions.suggestions) do
			table.insert(parts, string.format("- %s", sugg.message))
		end
		table.insert(parts, "")
	end

	if #suggestions.warnings > 0 then
		table.insert(parts, "**What to avoid:**")
		for _, warn in ipairs(suggestions.warnings) do
			table.insert(parts, string.format("- %s", warn.message))
		end
		table.insert(parts, "")
	end

	return table.concat(parts, "\n")
end

-- ============================================================================
-- STATISTICS & DEBUGGING
-- ============================================================================

--[[
    Get memory statistics
    @return table
]]
function DecisionMemory.getStatistics()
	DecisionMemory.load()

	local stats = {
		successfulPatterns = #patterns.successful,
		failedPatterns = #patterns.failed,
		totalPatterns = #patterns.successful + #patterns.failed,
		mostUsedTools = {},
		averageToolsPerTask = 0
	}

	-- Calculate most used tools
	local toolCounts = {}
	local totalTools = 0

	for _, pattern in ipairs(patterns.successful) do
		for _, tool in ipairs(pattern.toolSequence or {}) do
			toolCounts[tool] = (toolCounts[tool] or 0) + 1
			totalTools = totalTools + 1
		end
	end

	-- Sort by count
	local sortedTools = {}
	for tool, count in pairs(toolCounts) do
		table.insert(sortedTools, { tool = tool, count = count })
	end
	table.sort(sortedTools, function(a, b) return a.count > b.count end)

	-- Top 5 tools
	for i = 1, math.min(5, #sortedTools) do
		table.insert(stats.mostUsedTools, sortedTools[i])
	end

	-- Average tools per task
	if #patterns.successful > 0 then
		stats.averageToolsPerTask = totalTools / #patterns.successful
	end

	return stats
end

--[[
    Clear all patterns (for debugging/reset)
]]
function DecisionMemory.clearAll()
	patterns = { successful = {}, failed = {} }
	currentSequence = nil

	local memoryValue = getMemoryValue()
	if memoryValue then
		memoryValue:Destroy()
	end

	if Constants.DEBUG then
		print("[DecisionMemory] All patterns cleared")
	end
end

--[[
    Decay old patterns (called periodically)
]]
function DecisionMemory.decayOldPatterns()
	if not Constants.DECISION_MEMORY.enabled then
		return
	end

	local cutoffTime = os.time() - (Constants.DECISION_MEMORY.decayDays * 86400)
	local removedCount = 0

	-- Remove old successful patterns
	local newSuccessful = {}
	for _, pattern in ipairs(patterns.successful) do
		if (pattern.lastUsed or pattern.created or 0) > cutoffTime then
			table.insert(newSuccessful, pattern)
		else
			removedCount = removedCount + 1
		end
	end
	patterns.successful = newSuccessful

	-- Remove old failed patterns
	local newFailed = {}
	for _, pattern in ipairs(patterns.failed) do
		if (pattern.lastUsed or pattern.created or 0) > cutoffTime then
			table.insert(newFailed, pattern)
		else
			removedCount = removedCount + 1
		end
	end
	patterns.failed = newFailed

	if removedCount > 0 then
		DecisionMemory.save()
		if Constants.DEBUG then
			print(string.format("[DecisionMemory] Decayed %d old patterns", removedCount))
		end
	end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    Initialize decision memory (call at plugin start)
]]
function DecisionMemory.init()
	DecisionMemory.load()
	DecisionMemory.decayOldPatterns()
end

return DecisionMemory
