--[[
    WorkingMemory.lua
    Tiered context management with relevance decay

    Implements a three-tier memory system:
    1. CRITICAL - User goals, key decisions (never evicted)
    2. WORKING - Recent tool results, script reads (decays over time)
    3. BACKGROUND - Compressed summaries of older context

    Uses exponential decay so recent items are much more valuable.
    Proactively compacts before hitting token limits.
]]

local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Constants)

local WorkingMemory = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local CONFIG = {
	enabled = true,
	maxWorkingItems = 20,
	compactThreshold = 15,      -- Start compacting when exceeding this
	relevanceFloor = 10,        -- Minimum relevance (never goes below)
	halfLife = 300,             -- Seconds for relevance to halve (increased from 120 for longer context retention)
	accessBoost = 5,            -- Relevance boost on access
	maxBackgroundItems = 50,    -- Compressed summaries to keep
	maxContentLength = 500,     -- Truncate long content in summaries
}

-- ============================================================================
-- STATE
-- ============================================================================

local memory = {
	critical = {},     -- Never evicted: user goals, key decisions
	working = {},      -- Recent context with decay
	background = {}    -- Compressed summaries
}

local currentGoal = nil  -- The active user goal

-- ============================================================================
-- MEMORY ITEM STRUCTURE
-- ============================================================================

--[[
    Memory Item:
    {
        id: string (GUID),
        type: string (tool_result, script_read, user_goal, decision, etc.),
        summary: string (human-readable summary),
        content: any (full content, may be truncated in background),
        relevance: number (current relevance score),
        baseRelevance: number (starting relevance, used for decay),
        addedAt: number (tick when added),
        lastAccessed: number (tick when last accessed),
        accessCount: number,
        metadata: table (optional tool-specific data)
    }
]]

-- ============================================================================
-- ADDING ITEMS
-- ============================================================================

--[[
    Add an item to working memory
    @param itemType string - Type of item
    @param summary string - Human-readable summary
    @param content any - Full content
    @param metadata table|nil - Optional metadata
    @return string - Item ID
]]
function WorkingMemory.add(itemType, summary, content, metadata)
	if not CONFIG.enabled then return nil end

	local item = {
		id = HttpService:GenerateGUID(false),
		type = itemType,
		summary = summary,
		content = content,
		addedAt = tick(),
		lastAccessed = tick(),
		accessCount = 1,
		metadata = metadata or {}
	}

	-- Set initial relevance based on type
	local baseRelevance = WorkingMemory._getBaseRelevance(itemType)
	item.baseRelevance = baseRelevance
	item.relevance = baseRelevance

	-- Route to appropriate tier
	if itemType == "user_goal" then
		currentGoal = item
		table.insert(memory.critical, item)
	elseif itemType == "decision" or itemType == "key_finding" then
		table.insert(memory.critical, item)
	else
		table.insert(memory.working, item)
	end

	-- Decay and compact
	WorkingMemory.decay()
	WorkingMemory.compact()

	if Constants.DEBUG then
		print(string.format("[WorkingMemory] Added %s: %s (relevance: %d)",
			itemType, summary:sub(1, 40), baseRelevance))
	end

	return item.id
end

--[[
    Get base relevance for different item types
]]
function WorkingMemory._getBaseRelevance(itemType)
	local relevanceMap = {
		user_goal = 100,
		decision = 90,
		key_finding = 85,
		script_read = 80,
		tool_result = 70,
		instance_inspect = 65,
		search_result = 60,
		general = 50
	}
	return relevanceMap[itemType] or 50
end

-- ============================================================================
-- ACCESSING ITEMS
-- ============================================================================

--[[
    Access an item (boosts its relevance)
    @param itemId string
    @return table|nil - The item
]]
function WorkingMemory.access(itemId)
	-- Check critical first
	for _, item in ipairs(memory.critical) do
		if item.id == itemId then
			item.lastAccessed = tick()
			item.accessCount = item.accessCount + 1
			return item
		end
	end

	-- Check working
	for _, item in ipairs(memory.working) do
		if item.id == itemId then
			item.lastAccessed = tick()
			item.accessCount = item.accessCount + 1
			-- Boost base relevance for repeated access
			item.baseRelevance = math.min(100, item.baseRelevance + CONFIG.accessBoost)
			return item
		end
	end

	return nil
end

--[[
    Find items by type
    @param itemType string
    @return table - Array of matching items
]]
function WorkingMemory.findByType(itemType)
	local results = {}

	for _, item in ipairs(memory.critical) do
		if item.type == itemType then
			table.insert(results, item)
		end
	end

	for _, item in ipairs(memory.working) do
		if item.type == itemType then
			table.insert(results, item)
		end
	end

	return results
end

--[[
    Get the current active goal
    @return table|nil
]]
function WorkingMemory.getCurrentGoal()
	return currentGoal
end

-- ============================================================================
-- DECAY & COMPACTION
-- ============================================================================

--[[
    Apply exponential decay to working memory items
]]
function WorkingMemory.decay()
	local now = tick()

	for _, item in ipairs(memory.working) do
		local timeSinceAccess = now - (item.lastAccessed or item.addedAt)
		-- Exponential decay: relevance = base * 0.5^(time/halfLife)
		item.relevance = item.baseRelevance * (0.5 ^ (timeSinceAccess / CONFIG.halfLife))
		item.relevance = math.max(CONFIG.relevanceFloor, item.relevance)
	end
end

--[[
    Compact working memory when it gets too large
]]
function WorkingMemory.compact()
	if #memory.working <= CONFIG.maxWorkingItems then
		return
	end

	-- Sort by relevance (descending)
	table.sort(memory.working, function(a, b)
		return a.relevance > b.relevance
	end)

	-- Move low-relevance items to background
	while #memory.working > CONFIG.compactThreshold do
		local item = table.remove(memory.working)
		local summary = WorkingMemory._summarize(item)
		table.insert(memory.background, summary)

		if Constants.DEBUG then
			print(string.format("[WorkingMemory] Compacted: %s (relevance: %.1f)",
				item.summary:sub(1, 30), item.relevance))
		end
	end

	-- Trim background if too large
	while #memory.background > CONFIG.maxBackgroundItems do
		table.remove(memory.background, 1)  -- Remove oldest
	end
end

--[[
    Create a compressed summary of an item
]]
function WorkingMemory._summarize(item)
	return {
		id = item.id,
		type = item.type,
		summary = item.summary,
		-- Truncate content for background storage
		content = type(item.content) == "string"
			and item.content:sub(1, CONFIG.maxContentLength)
			or nil,
		addedAt = item.addedAt,
		wasRelevance = item.relevance
	}
end

-- ============================================================================
-- GOAL MANAGEMENT
-- ============================================================================

--[[
    Set the current user goal
    @param message string - User's message
    @param analysis table|nil - Task analysis
]]
function WorkingMemory.setGoal(message, analysis)
	currentGoal = {
		id = HttpService:GenerateGUID(false),
		type = "user_goal",
		summary = message:sub(1, 200),
		content = message,
		addedAt = tick(),
		lastAccessed = tick(),
		accessCount = 1,
		baseRelevance = 100,
		relevance = 100,
		metadata = {
			analysis = analysis
		}
	}

	table.insert(memory.critical, currentGoal)

	if Constants.DEBUG then
		print(string.format("[WorkingMemory] Set goal: %s", message:sub(1, 50)))
	end
end

--[[
    Archive current goal (when starting a new task)
]]
function WorkingMemory.archiveCurrentGoal()
	if currentGoal then
		-- Keep in critical but mark as archived
		currentGoal.metadata = currentGoal.metadata or {}
		currentGoal.metadata.archived = true
		currentGoal.metadata.archivedAt = tick()

		-- Reduce relevance of archived goals
		currentGoal.baseRelevance = 50
		currentGoal.relevance = 50
	end
	currentGoal = nil
end

-- ============================================================================
-- FORMATTING FOR PROMPT
-- ============================================================================

--[[
    Format memory for inclusion in system prompt
    @param options table|nil - { includeCritical, includeWorking, includeBackground, minRelevance }
    @return string
]]
function WorkingMemory.formatForPrompt(options)
	if not CONFIG.enabled then return "" end

	options = options or {}
	local includeCritical = options.includeCritical ~= false
	local includeWorking = options.includeWorking ~= false
	local includeBackground = options.includeBackground or false
	local minRelevance = options.minRelevance or 30

	-- Apply decay before formatting
	WorkingMemory.decay()

	local parts = {}

	-- Critical memory (goals, decisions)
	if includeCritical and #memory.critical > 0 then
		local activeGoals = {}
		local decisions = {}

		for _, item in ipairs(memory.critical) do
			if item.type == "user_goal" and not (item.metadata and item.metadata.archived) then
				table.insert(activeGoals, item)
			elseif item.type == "decision" or item.type == "key_finding" then
				table.insert(decisions, item)
			end
		end

		if #activeGoals > 0 then
			table.insert(parts, "## ?? Active Goal")
			for _, item in ipairs(activeGoals) do
				table.insert(parts, "- " .. item.summary)
			end
			table.insert(parts, "")
		end

		if #decisions > 0 then
			table.insert(parts, "## ?? Key Decisions")
			for _, item in ipairs(decisions) do
				table.insert(parts, "- " .. item.summary)
			end
			table.insert(parts, "")
		end
	end

	-- Working memory (recent context)
	if includeWorking then
		local relevantWorking = {}
		for _, item in ipairs(memory.working) do
			if item.relevance >= minRelevance then
				table.insert(relevantWorking, item)
			end
		end

		-- Sort by relevance
		table.sort(relevantWorking, function(a, b)
			return a.relevance > b.relevance
		end)

		if #relevantWorking > 0 then
			table.insert(parts, "## ?? Recent Context")
			for _, item in ipairs(relevantWorking) do
				local icon = WorkingMemory._getTypeIcon(item.type)
				table.insert(parts, string.format("- %s [%.0f%%] %s",
					icon, item.relevance, item.summary))
			end
			table.insert(parts, "")
		end
	end

	-- Background memory (compressed, only if requested)
	if includeBackground and #memory.background > 0 then
		table.insert(parts, "## ?? Background Context")
		for i = math.max(1, #memory.background - 5), #memory.background do
			local item = memory.background[i]
			if item then
				table.insert(parts, "- " .. item.summary)
			end
		end
		table.insert(parts, "")
	end

	return table.concat(parts, "\n")
end

function WorkingMemory._getTypeIcon(itemType)
	local icons = {
		user_goal = "??",
		decision = "??",
		key_finding = "??",
		script_read = "??",
		tool_result = "??",
		instance_inspect = "??",
		search_result = "??",
		general = "??"
	}
	return icons[itemType] or "•"
end

-- ============================================================================
-- CLEANUP & STATE
-- ============================================================================

--[[
    Clear all memory (on conversation reset)
]]
function WorkingMemory.clear()
	memory.critical = {}
	memory.working = {}
	memory.background = {}
	currentGoal = nil

	if Constants.DEBUG then
		print("[WorkingMemory] Cleared all memory")
	end
end

--[[
    Get memory statistics
    @return table
]]
function WorkingMemory.getStatistics()
	local totalRelevance = 0
	for _, item in ipairs(memory.working) do
		totalRelevance = totalRelevance + item.relevance
	end

	return {
		criticalCount = #memory.critical,
		workingCount = #memory.working,
		backgroundCount = #memory.background,
		averageRelevance = #memory.working > 0 and (totalRelevance / #memory.working) or 0,
		hasGoal = currentGoal ~= nil,
		goalSummary = currentGoal and currentGoal.summary:sub(1, 50) or nil
	}
end

--[[
    Get current size for token estimation
    @return number - Approximate token count
]]
function WorkingMemory.estimateTokens()
	local charCount = 0

	for _, item in ipairs(memory.critical) do
		charCount = charCount + #item.summary + 20
	end

	for _, item in ipairs(memory.working) do
		charCount = charCount + #item.summary + 20
	end

	-- Rough estimate: 4 chars per token
	return math.ceil(charCount / 4)
end

return WorkingMemory
