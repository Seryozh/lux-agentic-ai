--[[
    ContextSelector.lua
    Intelligent context filtering for prompts
    
    Instead of dumping ALL scripts into every prompt, this module:
    1. Analyzes the user's request to identify relevant topics
    2. Scores scripts by relevance to the task
    3. Includes recently edited scripts (they're likely relevant)
    4. Returns only the most relevant context, saving tokens
]]

local Constants = require(script.Parent.Constants)
local IndexManager = require(script.Parent.IndexManager)
local Utils = require(script.Parent.Utils)

local ContextSelector = {}

-- ============================================================================
-- STATE
-- ============================================================================

-- Track recently edited scripts (path -> timestamp)
local recentlyEdited = {}

-- Keyword cache for scripts (script path -> keywords extracted)
local scriptKeywordCache = {}

-- Freshness tracking (path -> { lastRead, lastModified, readCount })
local freshnessState = {}

-- ============================================================================
-- FRESHNESS CONFIGURATION
-- ============================================================================

local FRESHNESS_CONFIG = {
	-- Time thresholds (in seconds)
	staleThreshold = 300,        -- 5 minutes: script is considered stale
	veryStaleThreshold = 600,    -- 10 minutes: script is very stale
	modifiedAfterReadWindow = 60, -- 1 minute: if modified this recently after read, boost relevance

	-- Scoring adjustments (reduced penalties to prevent staleness from overwhelming keyword relevance)
	freshBonus = 10,             -- Recently read script bonus (reduced from 15)
	staleReadPenalty = 3,        -- Penalty for stale read (reduced from 10)
	veryStaleReadPenalty = 8,    -- Penalty for very stale read (reduced from 25)
	neverReadPenalty = 2,        -- Slight penalty for never-read scripts (reduced from 5)
	modifiedAfterReadBonus = 30, -- Big bonus if script was modified after we read it (keep this high)
}

-- ============================================================================
-- KEYWORD EXTRACTION
-- ============================================================================

-- Common Roblox-related keywords to look for
local IMPORTANT_KEYWORDS = {
	-- Services
	"players", "workspace", "replicatedstorage", "serverstorage", "serverscriptservice",
	"startergui", "starterplayer", "lighting", "soundservice", "tweenservice",
	"datastore", "httpservice", "runservice", "userinputservice", "contextactionservice",

	-- Concepts
	"remote", "event", "function", "bindable", "module", "class", "service",
	"data", "save", "load", "store", "profile", "player", "character",
	"gui", "ui", "frame", "button", "text", "label", "screen", "billboard",
	"part", "model", "cframe", "position", "size", "color", "material",
	"animate", "animation", "tween", "lerp", "physics", "collision",
	"tool", "inventory", "shop", "currency", "money", "coins", "gems",
	"combat", "health", "damage", "weapon", "ability", "skill",
	"spawn", "respawn", "teleport", "zone", "region",
	"leaderboard", "stats", "score", "level", "xp", "experience",
	"chat", "message", "notification", "sound", "music", "audio"
}

--[[
    Extract keywords from text (for matching)
    @param text string
    @return table - Set of keywords (lowercase)
]]
local function extractKeywords(text)
	local keywords = {}
	local lowerText = text:lower()

	-- Extract words (alphanumeric sequences)
	for word in lowerText:gmatch("%w+") do
		if #word >= 3 then -- Skip very short words
			keywords[word] = true
		end
	end

	-- Also check for important compound terms
	for _, important in ipairs(IMPORTANT_KEYWORDS) do
		if lowerText:find(important, 1, true) then
			keywords[important] = true
		end
	end

	return keywords
end

--[[
    Get keywords for a script (cached)
    @param scriptData table - Script info from IndexManager
    @return table - Keywords set
]]
local function getScriptKeywords(scriptData)
	local path = scriptData.path

	-- Check cache
	if scriptKeywordCache[path] then
		return scriptKeywordCache[path]
	end

	-- Get script instance
	local script = Utils.getScriptByPath(path)
	local keywords = {}

	-- Keywords from path
	local pathKeywords = extractKeywords(path)
	for k in pairs(pathKeywords) do
		keywords[k] = true
	end

	-- Keywords from script name
	local nameKeywords = extractKeywords(scriptData.name)
	for k in pairs(nameKeywords) do
		keywords[k] = true
	end

	-- Keywords from source (limited to first 2000 chars to save processing)
	if script and script:IsA("LuaSourceContainer") then
		local sourcePreview = script.Source:sub(1, 2000)
		local sourceKeywords = extractKeywords(sourcePreview)
		for k in pairs(sourceKeywords) do
			keywords[k] = true
		end
	end

	-- Cache result
	scriptKeywordCache[path] = keywords

	return keywords
end

-- ============================================================================
-- FRESHNESS TRACKING
-- ============================================================================

--[[
    Record that a script was read
    @param path string
]]
function ContextSelector.recordRead(path)
	if not freshnessState[path] then
		freshnessState[path] = {
			lastRead = nil,
			lastModified = nil,
			readCount = 0
		}
	end

	freshnessState[path].lastRead = tick()
	freshnessState[path].readCount = (freshnessState[path].readCount or 0) + 1

	if Constants.DEBUG then
		print(string.format("[ContextSelector] Recorded read: %s (count: %d)",
			path, freshnessState[path].readCount))
	end
end

--[[
    Record that a script was modified
    @param path string
]]
function ContextSelector.recordModified(path)
	if not freshnessState[path] then
		freshnessState[path] = {
			lastRead = nil,
			lastModified = nil,
			readCount = 0
		}
	end

	freshnessState[path].lastModified = tick()

	if Constants.DEBUG then
		print(string.format("[ContextSelector] Recorded modification: %s", path))
	end
end

--[[
    Get freshness status for a script
    @param path string
    @return table - { status: "fresh"|"stale"|"very_stale"|"never_read", timeSinceRead: number|nil, modifiedAfterRead: boolean }
]]
function ContextSelector.getFreshness(path)
	local state = freshnessState[path]
	local now = tick()

	if not state or not state.lastRead then
		return {
			status = "never_read",
			timeSinceRead = nil,
			modifiedAfterRead = false
		}
	end

	local timeSinceRead = now - state.lastRead
	local modifiedAfterRead = state.lastModified and state.lastModified > state.lastRead

	local status
	if timeSinceRead < FRESHNESS_CONFIG.staleThreshold then
		status = "fresh"
	elseif timeSinceRead < FRESHNESS_CONFIG.veryStaleThreshold then
		status = "stale"
	else
		status = "very_stale"
	end

	return {
		status = status,
		timeSinceRead = timeSinceRead,
		modifiedAfterRead = modifiedAfterRead,
		readCount = state.readCount
	}
end

--[[
    Calculate freshness score adjustment for a script
    @param path string
    @return number - Score adjustment (positive = boost, negative = penalty)
]]
local function calculateFreshnessScore(path)
	local freshness = ContextSelector.getFreshness(path)
	local adjustment = 0

	if freshness.status == "never_read" then
		adjustment = -FRESHNESS_CONFIG.neverReadPenalty
	elseif freshness.status == "fresh" then
		adjustment = FRESHNESS_CONFIG.freshBonus
	elseif freshness.status == "stale" then
		adjustment = -FRESHNESS_CONFIG.staleReadPenalty
	elseif freshness.status == "very_stale" then
		adjustment = -FRESHNESS_CONFIG.veryStaleReadPenalty
	end

	-- Big bonus if script was modified after we read it (we need to re-read!)
	if freshness.modifiedAfterRead then
		adjustment = adjustment + FRESHNESS_CONFIG.modifiedAfterReadBonus
	end

	return adjustment
end

--[[
    Get scripts that should be re-read (modified after last read)
    @return table - Array of { path, timeSinceRead, reason }
]]
function ContextSelector.getStaleScripts()
	local stale = {}
	local now = tick()

	for path, state in pairs(freshnessState) do
		if state.lastRead then
			local freshness = ContextSelector.getFreshness(path)

			if freshness.modifiedAfterRead then
				table.insert(stale, {
					path = path,
					timeSinceRead = freshness.timeSinceRead,
					reason = "modified_after_read",
					priority = "high"
				})
			elseif freshness.status == "very_stale" then
				table.insert(stale, {
					path = path,
					timeSinceRead = freshness.timeSinceRead,
					reason = "very_stale",
					priority = "medium"
				})
			elseif freshness.status == "stale" then
				table.insert(stale, {
					path = path,
					timeSinceRead = freshness.timeSinceRead,
					reason = "stale",
					priority = "low"
				})
			end
		end
	end

	-- Sort by priority (high first)
	local priorityOrder = { high = 1, medium = 2, low = 3 }
	table.sort(stale, function(a, b)
		return priorityOrder[a.priority] < priorityOrder[b.priority]
	end)

	return stale
end

--[[
    Mark all reads as stale (called on new task)
]]
function ContextSelector.markAllStale()
	local cutoff = tick() - FRESHNESS_CONFIG.veryStaleThreshold
	for path, state in pairs(freshnessState) do
		if state.lastRead then
			-- Push lastRead back to make it stale
			state.lastRead = math.min(state.lastRead, cutoff)
		end
	end

	if Constants.DEBUG then
		print("[ContextSelector] All reads marked as stale for new task")
	end
end

--[[
    Format freshness warnings for prompt inclusion
    @return string|nil - Warning text or nil if no warnings
]]
function ContextSelector.formatFreshnessWarnings()
	local stale = ContextSelector.getStaleScripts()
	if #stale == 0 then
		return nil
	end

	local lines = {}
	local highPriority = {}
	local mediumPriority = {}

	for _, item in ipairs(stale) do
		if item.priority == "high" then
			table.insert(highPriority, item)
		elseif item.priority == "medium" then
			table.insert(mediumPriority, item)
		end
	end

	if #highPriority > 0 then
		table.insert(lines, "?? SCRIPTS MODIFIED SINCE LAST READ (re-read before editing):")
		for _, item in ipairs(highPriority) do
			table.insert(lines, string.format("  • %s", item.path))
		end
	end

	if #mediumPriority > 0 then
		table.insert(lines, "?? Stale reads (consider re-reading):")
		for i, item in ipairs(mediumPriority) do
			if i > 3 then
				table.insert(lines, string.format("  ... and %d more", #mediumPriority - 3))
				break
			end
			local minutes = math.floor(item.timeSinceRead / 60)
			table.insert(lines, string.format("  • %s (%d min ago)", item.path, minutes))
		end
	end

	if #lines == 0 then
		return nil
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- RELEVANCE SCORING
-- ============================================================================

--[[
    Score how relevant a script is to a user's request
    @param scriptData table - Script info
    @param requestKeywords table - Keywords from user request
    @param taskCapabilities table - Detected capabilities from TaskPlanner
    @return number - Relevance score (higher = more relevant)
]]
local function scoreRelevance(scriptData, requestKeywords, taskCapabilities)
	local score = 0

	-- Get script keywords
	local scriptKeywords = getScriptKeywords(scriptData)

	-- 1. Keyword matching (main factor)
	local matchCount = 0
	for keyword in pairs(requestKeywords) do
		if scriptKeywords[keyword] then
			matchCount = matchCount + 1
		end
	end
	score = score + (matchCount * 10)

	-- 2. Path relevance (if request mentions the path)
	local lowerPath = scriptData.path:lower()
	for keyword in pairs(requestKeywords) do
		if lowerPath:find(keyword, 1, true) then
			score = score + 25 -- Strong signal
		end
	end

	-- 3. Recently edited bonus (reduced from 50 to 15 to prevent recency bias overwhelming relevance)
	local editTime = recentlyEdited[scriptData.path]
	if editTime then
		local minutesAgo = (tick() - editTime) / 60
		if minutesAgo < Constants.CONTEXT_SELECTION.recentEditWindowMinutes then
			-- More recent = higher bonus (up to 15 points - reduced to prevent recency bias)
			local recencyBonus = 15 * (1 - (minutesAgo / Constants.CONTEXT_SELECTION.recentEditWindowMinutes))
			score = score + recencyBonus
		end
	end

	-- 4. Capability matching
	taskCapabilities = taskCapabilities or {}
	for _, cap in ipairs(taskCapabilities) do
		if cap == "script_editing" then
			-- Any script is potentially relevant
			score = score + 2
		elseif cap == "ui_creation" and lowerPath:find("gui") then
			score = score + 15
		elseif cap == "ui_creation" and lowerPath:find("ui") then
			score = score + 15
		elseif cap == "networking" and (lowerPath:find("server") or lowerPath:find("client") or lowerPath:find("remote")) then
			score = score + 15
		elseif cap == "data_management" and (lowerPath:find("data") or lowerPath:find("store") or lowerPath:find("save")) then
			score = score + 15
		end
	end

	-- 5. Script type bonus (ModuleScripts are often dependencies)
	if scriptData.className == "ModuleScript" then
		score = score + 5 -- Slightly prefer modules
	end

	-- 6. Location-based hints
	if lowerPath:find("serverscriptservice") then
		if requestKeywords["server"] or requestKeywords["data"] or requestKeywords["remote"] then
			score = score + 10
		end
	elseif lowerPath:find("startergui") then
		if requestKeywords["gui"] or requestKeywords["ui"] or requestKeywords["button"] or requestKeywords["screen"] then
			score = score + 10
		end
	elseif lowerPath:find("replicatedstorage") then
		-- Shared modules - generally relevant
		score = score + 3
	end

	-- 7. Freshness scoring (boost recently read, penalize stale)
	local freshnessAdjustment = calculateFreshnessScore(scriptData.path)
	score = score + freshnessAdjustment

	return score
end

-- ============================================================================
-- MAIN SELECTION LOGIC
-- ============================================================================

--[[
    Select relevant scripts for the current task
    @param userMessage string - User's request
    @param taskAnalysis table|nil - From TaskPlanner.analyzeTask()
    @return table - { scripts: array, totalAvailable: number, selectionReason: string }
]]
function ContextSelector.selectRelevantScripts(userMessage, taskAnalysis)
	if not Constants.CONTEXT_SELECTION.enabled then
		-- Fallback: return all scripts (old behavior)
		local scanResult = IndexManager.scanScripts()
		return {
			scripts = scanResult.scripts,
			totalAvailable = scanResult.totalCount,
			selectionReason = "Context selection disabled - including all scripts"
		}
	end

	local scanResult = IndexManager.scanScripts()
	local allScripts = scanResult.scripts

	if #allScripts == 0 then
		return {
			scripts = {},
			totalAvailable = 0,
			selectionReason = "No scripts in project"
		}
	end

	-- Extract keywords from user message
	local requestKeywords = {}
	if Constants.CONTEXT_SELECTION.keywordMatchingEnabled then
		requestKeywords = extractKeywords(userMessage)
	end

	-- Get capabilities from task analysis
	local taskCapabilities = taskAnalysis and taskAnalysis.capabilities or {}

	-- Score all scripts
	local scoredScripts = {}
	for _, scriptData in ipairs(allScripts) do
		local score = scoreRelevance(scriptData, requestKeywords, taskCapabilities)
		table.insert(scoredScripts, {
			script = scriptData,
			score = score
		})
	end

	-- Sort by score descending
	table.sort(scoredScripts, function(a, b)
		return a.score > b.score
	end)

	-- Select top N
	local maxScripts = Constants.CONTEXT_SELECTION.maxRelevantScripts
	local selected = {}
	local minScore = 0 -- Threshold to include

	for i, scored in ipairs(scoredScripts) do
		if i > maxScripts then break end

		-- Only include if score is above threshold (has some relevance)
		if scored.score >= minScore then
			table.insert(selected, scored.script)
		end
	end

	-- Build selection reason
	local reason
	if #selected == #allScripts then
		reason = string.format("Including all %d scripts (all are relevant)", #selected)
	elseif #selected == 0 then
		reason = "No scripts matched the request keywords"
	else
		reason = string.format("Selected %d of %d scripts by relevance", #selected, #allScripts)
	end

	if Constants.DEBUG then
		print(string.format("[ContextSelector] %s", reason))
		if #scoredScripts > 0 then
			print(string.format("[ContextSelector] Top score: %d, Bottom score: %d",
				scoredScripts[1].score,
				scoredScripts[#scoredScripts].score
				))
		end
	end

	return {
		scripts = selected,
		totalAvailable = #allScripts,
		selectionReason = reason,
		topScores = #scoredScripts > 0 and {
			highest = scoredScripts[1].score,
			lowest = scoredScripts[#scoredScripts].score
		} or nil
	}
end

-- ============================================================================
-- RECENTLY EDITED TRACKING
-- ============================================================================

--[[
    Mark a script as recently edited
    @param path string - Script path
]]
function ContextSelector.markEdited(path)
	if not Constants.CONTEXT_SELECTION.includeRecentlyEdited then
		return
	end

	recentlyEdited[path] = tick()

	-- Clean up old entries
	local cutoff = tick() - (Constants.CONTEXT_SELECTION.recentEditWindowMinutes * 60)
	for p, time in pairs(recentlyEdited) do
		if time < cutoff then
			recentlyEdited[p] = nil
		end
	end

	if Constants.DEBUG then
		print(string.format("[ContextSelector] Marked as edited: %s", path))
	end
end

--[[
    Get list of recently edited scripts
    @return table - Array of paths
]]
function ContextSelector.getRecentlyEdited()
	local result = {}
	local cutoff = tick() - (Constants.CONTEXT_SELECTION.recentEditWindowMinutes * 60)

	for path, time in pairs(recentlyEdited) do
		if time >= cutoff then
			table.insert(result, {
				path = path,
				minutesAgo = math.floor((tick() - time) / 60)
			})
		end
	end

	-- Sort by most recent first
	table.sort(result, function(a, b)
		return a.minutesAgo < b.minutesAgo
	end)

	return result
end

-- ============================================================================
-- FORMATTING FOR PROMPT
-- ============================================================================

--[[
    Format selected scripts for inclusion in system prompt
    @param selection table - Result from selectRelevantScripts
    @return string - Formatted text for prompt
]]
function ContextSelector.formatForPrompt(selection)
	local lines = {}

	-- Header with context
	table.insert(lines, "GAME SCRIPTS (Filtered by Relevance):\n")

	if selection.selectionReason then
		table.insert(lines, string.format("?? %s\n", selection.selectionReason))
	end

	-- Sort scripts by path for readability
	local sortedScripts = {}
	for _, script in ipairs(selection.scripts) do
		table.insert(sortedScripts, script)
	end
	table.sort(sortedScripts, function(a, b) return a.path < b.path end)

	-- List scripts
	for _, scriptData in ipairs(sortedScripts) do
		local flags = {}

		-- Recently edited indicator
		if recentlyEdited[scriptData.path] then
			table.insert(flags, "??")
		end

		-- Freshness indicator
		local freshness = ContextSelector.getFreshness(scriptData.path)
		if freshness.modifiedAfterRead then
			table.insert(flags, "??") -- Modified after read - needs re-read
		elseif freshness.status == "fresh" then
			table.insert(flags, "?") -- Recently read
		elseif freshness.status == "very_stale" then
			table.insert(flags, "??") -- Very stale
		end

		local flagStr = #flags > 0 and " " .. table.concat(flags, "") or ""

		table.insert(lines, string.format("• %s (%s, %d lines)%s",
			scriptData.path,
			scriptData.className,
			scriptData.lineCount,
			flagStr
			))
	end

	if #selection.scripts == 0 then
		table.insert(lines, "No scripts found matching your request.")
		table.insert(lines, "Use list_children or discover_project to explore the game structure.")
	end

	-- Note if there are more scripts available
	if selection.totalAvailable > #selection.scripts then
		table.insert(lines, string.format(
			"\n?? %d more scripts available (use search_scripts to find specific code)",
			selection.totalAvailable - #selection.scripts
			))
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

--[[
    Invalidate keyword cache for a script (after it's edited)
    @param path string - Script path
]]
function ContextSelector.invalidateCache(path)
	scriptKeywordCache[path] = nil
	if Constants.DEBUG then
		print(string.format("[ContextSelector] Cache invalidated for: %s", path))
	end
end

--[[
    Clear all caches (on conversation reset or major changes)
]]
function ContextSelector.clearCache()
	scriptKeywordCache = {}
	recentlyEdited = {}
	freshnessState = {}
	if Constants.DEBUG then
		print("[ContextSelector] All caches cleared (including freshness)")
	end
end

--[[
    Reset state (on conversation reset)
]]
function ContextSelector.reset()
	-- Keep keyword cache (scripts haven't changed)
	-- Clear recently edited and freshness
	recentlyEdited = {}
	freshnessState = {}
	if Constants.DEBUG then
		print("[ContextSelector] Session state cleared (recently edited + freshness)")
	end
end

--[[
    Get freshness statistics for debugging/monitoring
    @return table - { total, fresh, stale, veryStale, neverRead, modifiedAfterRead }
]]
function ContextSelector.getFreshnessStats()
	local stats = {
		total = 0,
		fresh = 0,
		stale = 0,
		veryStale = 0,
		neverRead = 0,
		modifiedAfterRead = 0
	}

	for path, _ in pairs(freshnessState) do
		stats.total = stats.total + 1
		local freshness = ContextSelector.getFreshness(path)

		if freshness.status == "fresh" then
			stats.fresh = stats.fresh + 1
		elseif freshness.status == "stale" then
			stats.stale = stats.stale + 1
		elseif freshness.status == "very_stale" then
			stats.veryStale = stats.veryStale + 1
		elseif freshness.status == "never_read" then
			stats.neverRead = stats.neverRead + 1
		end

		if freshness.modifiedAfterRead then
			stats.modifiedAfterRead = stats.modifiedAfterRead + 1
		end
	end

	return stats
end

return ContextSelector
