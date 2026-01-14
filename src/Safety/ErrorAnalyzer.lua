--[[
    ErrorAnalyzer.lua
    Intelligent error classification and recovery suggestions
    
    This module transforms cryptic errors into actionable insights:
    1. Classifies errors into categories
    2. Suggests specific recovery strategies
    3. Tracks error patterns to detect systematic issues
    4. Provides context-aware error messages for the LLM
]]

local Constants = require(script.Parent.Parent.Shared.Constants)

local ErrorAnalyzer = {}

-- ============================================================================
-- TASK BOUNDARY TRACKING
-- ============================================================================

-- Current task context for error relevance
local currentTaskId = nil
local taskStartTime = nil

-- ============================================================================
-- ERROR PATTERNS & CLASSIFICATION
-- ============================================================================

local ERROR_PATTERNS = {
	-- Script/Path errors
	{
		patterns = { "not found", "does not exist", "nil value", "attempt to index nil" },
		category = "missing_resource",
		severity = "medium",
		recoveryStrategies = {
			"Verify the path exists using get_instance or list_children",
			"Check for typos in the path",
			"The parent container might not exist - create it first",
			"Use discover_project to understand the current structure"
		}
	},

	-- Syntax errors
	{
		patterns = { "syntax error", "unexpected", "expected", "malformed", "'end' expected", "'then' expected" },
		category = "syntax_error",
		severity = "high",
		recoveryStrategies = {
			"Re-read the script using get_script to see current state",
			"Check for missing 'end', 'then', 'do', or closing brackets",
			"Verify string quotes are properly closed",
			"Count opening/closing brackets - they must match"
		}
	},

	-- Permission/Type errors
	{
		patterns = { "cannot set", "read%-only", "invalid property", "not a valid member" },
		category = "property_error",
		severity = "medium",
		recoveryStrategies = {
			"Use get_instance to see what properties actually exist",
			"Check if the property name is spelled correctly",
			"Some properties require specific value types (Color3, UDim2, etc.)",
			"Verify the instance class supports this property"
		}
	},

	-- Already exists errors
	{
		patterns = { "already exists", "duplicate", "name collision" },
		category = "already_exists",
		severity = "low",
		recoveryStrategies = {
			"Use get_instance to check existing state",
			"Consider modifying the existing resource instead of creating new",
			"Use a different name or delete the existing one first"
		}
	},

	-- Search/Match errors
	{
		patterns = { "ambiguous match", "found multiple", "not unique" },
		category = "ambiguous_match",
		severity = "medium",
		recoveryStrategies = {
			"Re-read the file with get_script to see exact content",
			"Include more context lines in your search_content",
			"Use more unique identifiers in the search pattern"
		}
	},

	{
		patterns = { "search content not found", "could not find", "no match" },
		category = "search_failed",
		severity = "medium",
		recoveryStrategies = {
			"Re-read the file - content may have changed",
			"Check for whitespace differences (indentation matters!)",
			"The code might have been modified by a previous operation",
			"Copy search_content exactly from get_script output"
		}
	},

	-- Instance creation errors
	{
		patterns = { "invalid classname", "cannot create", "unknown class" },
		category = "invalid_class",
		severity = "medium",
		recoveryStrategies = {
			"Verify the ClassName is spelled correctly (case-sensitive)",
			"Check Roblox API documentation for correct class name",
			"Some classes cannot be created via Instance.new()"
		}
	},

	-- Parent errors
	{
		patterns = { "parent not found", "invalid parent", "cannot parent" },
		category = "parent_error",
		severity = "medium",
		recoveryStrategies = {
			"Create the parent container first",
			"Use list_children to verify parent path exists",
			"Check if the parent allows this type of child"
		}
	},

	-- Rate/Timeout errors  
	{
		patterns = { "timeout", "rate limit", "too many requests", "try again" },
		category = "rate_limited",
		severity = "low",
		recoveryStrategies = {
			"Wait a moment before retrying",
			"Consider batching operations",
			"Reduce the frequency of API calls"
		}
	},

	-- Value/Type conversion
	{
		patterns = { "cannot convert", "invalid value", "type mismatch", "expected %w+, got" },
		category = "type_error",
		severity = "medium",
		recoveryStrategies = {
			"Check the expected value format (e.g., UDim2: '0,100,0,50')",
			"For Color3, use '255,128,0' or '#FF8000' format",
			"For Vector3, use 'X,Y,Z' format",
			"Use get_instance to see what type the property expects"
		}
	},

	-- User denial
	{
		patterns = { "user denied", "rejected", "not approved" },
		category = "user_denied",
		severity = "info",
		recoveryStrategies = {
			"The user chose not to approve this operation",
			"Ask if they want a different approach",
			"Explain the purpose better and try again if appropriate"
		}
	}
}

-- Track error history for pattern detection
local errorHistory = {}
local MAX_HISTORY = 50
local MAX_ERROR_AGE_SECONDS = 120 -- Errors older than 2 minutes are considered stale

-- ============================================================================
-- CLASSIFICATION
-- ============================================================================

--[[
    Classify an error and get recovery suggestions
    @param toolName string - The tool that failed
    @param args table - Arguments passed to the tool
    @param errorMessage string - The error message
    @return table - Classification result
]]
function ErrorAnalyzer.classify(toolName, args, errorMessage)
	if not Constants.ERROR_RECOVERY.classifyErrors then
		return {
			category = "unknown",
			severity = "medium",
			recoveryStrategies = {},
			enhancedMessage = errorMessage
		}
	end

	local lowerError = errorMessage:lower()
	local result = {
		category = "unknown",
		severity = "medium",
		recoveryStrategies = {},
		enhancedMessage = errorMessage,
		toolName = toolName,
		timestamp = tick()
	}

	-- Match against patterns
	for _, pattern in ipairs(ERROR_PATTERNS) do
		for _, p in ipairs(pattern.patterns) do
			if lowerError:match(p) then
				result.category = pattern.category
				result.severity = pattern.severity
				result.recoveryStrategies = pattern.recoveryStrategies
				break
			end
		end
		if result.category ~= "unknown" then break end
	end

	-- Add context-specific suggestions based on tool
	result.contextualSuggestions = ErrorAnalyzer.getContextualSuggestions(toolName, args, result.category)

	-- Build enhanced message for the LLM
	result.enhancedMessage = ErrorAnalyzer.buildEnhancedMessage(result, toolName, args, errorMessage)

	-- Record in history
	ErrorAnalyzer.recordError(result)

	if Constants.DEBUG then
		print(string.format("[ErrorAnalyzer] Classified: %s -> %s (severity: %s)",
			errorMessage:sub(1, 50), result.category, result.severity))
	end

	return result
end

--[[
    Get context-specific suggestions based on tool and error category
]]
function ErrorAnalyzer.getContextualSuggestions(toolName, args, category)
	local suggestions = {}

	if toolName == "patch_script" then
		if category == "search_failed" or category == "ambiguous_match" then
			table.insert(suggestions, string.format(
				"For %s, try using get_script first to see the exact current content",
				args.path or "this script"
				))
		end

	elseif toolName == "create_script" or toolName == "create_instance" then
		if category == "parent_error" then
			local parentPath = args.parent or (args.path and args.path:match("(.+)%.[^.]+$"))
			if parentPath then
				table.insert(suggestions, string.format(
					"First verify %s exists using list_children on its parent",
					parentPath
					))
			end
		elseif category == "already_exists" then
			table.insert(suggestions, string.format(
				"Use get_instance('%s') to inspect the existing item",
				args.path or args.parent .. "." .. args.name
				))
		end

	elseif toolName == "set_instance_properties" then
		if category == "property_error" or category == "type_error" then
			table.insert(suggestions, string.format(
				"Use get_instance('%s') to see all available properties and their current values",
				args.path or "target"
				))
		end
	end

	return suggestions
end

--[[
    Build an enhanced error message with recovery guidance
]]
function ErrorAnalyzer.buildEnhancedMessage(classification, toolName, args, originalError)
	local parts = {}

	-- Category indicator
	local categoryEmoji = {
		missing_resource = "??",
		syntax_error = "??",
		property_error = "???",
		already_exists = "??",
		ambiguous_match = "??",
		search_failed = "??",
		invalid_class = "?",
		parent_error = "??",
		rate_limited = "??",
		type_error = "??",
		user_denied = "??",
		unknown = "?"
	}

	table.insert(parts, string.format("%s [%s] %s",
		categoryEmoji[classification.category] or "?",
		classification.category:upper():gsub("_", " "),
		originalError
		))

	-- Add recovery suggestions if enabled
	if Constants.ERROR_RECOVERY.suggestRecovery then
		if #classification.recoveryStrategies > 0 then
			table.insert(parts, "\n\n?? Recovery suggestions:")
			for i, strategy in ipairs(classification.recoveryStrategies) do
				if i <= 3 then -- Limit to top 3
					table.insert(parts, string.format("  %d. %s", i, strategy))
				end
			end
		end

		if #classification.contextualSuggestions > 0 then
			table.insert(parts, "\n?? For this specific case:")
			for _, suggestion in ipairs(classification.contextualSuggestions) do
				table.insert(parts, "  ? " .. suggestion)
			end
		end
	end

	return table.concat(parts, "\n")
end

-- ============================================================================
-- ERROR HISTORY & PATTERN DETECTION
-- ============================================================================

--[[
    Start a new task boundary - clears stale errors and sets task context
    Call this when the user sends a new message
    @param taskId string|nil - Optional task identifier
]]
function ErrorAnalyzer.onNewTask(taskId)
	local now = tick()

	-- Generate task ID if not provided
	currentTaskId = taskId or tostring(now)
	taskStartTime = now

	-- Prune errors that are too old (regardless of task)
	ErrorAnalyzer.pruneStaleErrors()

	if Constants.DEBUG then
		print(string.format("[ErrorAnalyzer] New task started: %s (pruned to %d errors)", 
			currentTaskId:sub(1, 8), #errorHistory))
	end
end

--[[
    Prune errors that are too old to be relevant
]]
function ErrorAnalyzer.pruneStaleErrors()
	local now = tick()
	local freshErrors = {}

	for _, err in ipairs(errorHistory) do
		local age = now - (err.timestamp or 0)
		if age <= MAX_ERROR_AGE_SECONDS then
			table.insert(freshErrors, err)
		end
	end

	errorHistory = freshErrors
end

--[[
    Record an error in history
]]
function ErrorAnalyzer.recordError(classification)
	table.insert(errorHistory, {
		category = classification.category,
		toolName = classification.toolName,
		timestamp = classification.timestamp or tick(),
		taskId = currentTaskId  -- Associate with current task
	})

	-- Trim history
	while #errorHistory > MAX_HISTORY do
		table.remove(errorHistory, 1)
	end
end

--[[
    Detect if we're in an error loop (same category repeating)
    Only considers errors from the CURRENT TASK to avoid false positives
    @return table|nil - Loop info if detected
]]
function ErrorAnalyzer.detectErrorLoop()
	if #errorHistory < 3 then return nil end

	local now = tick()

	-- Filter to only recent errors from current task
	local relevantErrors = {}
	for _, err in ipairs(errorHistory) do
		local isCurrentTask = (err.taskId == currentTaskId) or (currentTaskId == nil)
		local isRecent = (now - (err.timestamp or 0)) <= MAX_ERROR_AGE_SECONDS

		if isCurrentTask and isRecent then
			table.insert(relevantErrors, err)
		end
	end

	-- Need at least 3 relevant errors to detect a loop
	if #relevantErrors < 3 then return nil end

	-- Check last 5 relevant errors for repeating pattern
	local recentWindow = 5
	local startIdx = math.max(1, #relevantErrors - recentWindow + 1)

	local categoryCounts = {}
	local toolCounts = {}

	for i = startIdx, #relevantErrors do
		local err = relevantErrors[i]
		categoryCounts[err.category] = (categoryCounts[err.category] or 0) + 1
		toolCounts[err.toolName] = (toolCounts[err.toolName] or 0) + 1
	end

	-- Check for loop: same category 3+ times in recent window
	for category, count in pairs(categoryCounts) do
		if count >= 3 then
			return {
				detected = true,
				category = category,
				count = count,
				message = string.format(
					"?? ERROR LOOP DETECTED: %d '%s' errors in a row. The current approach is not working. Consider: 1) Re-reading the target first, 2) Trying a completely different approach, 3) Asking the user for clarification.",
					count, category
				)
			}
		end
	end

	-- Check for tool loop: same tool failing repeatedly
	for tool, count in pairs(toolCounts) do
		if count >= 3 then
			return {
				detected = true,
				tool = tool,
				count = count,
				message = string.format(
					"?? TOOL LOOP DETECTED: %s has failed %d times recently. Stop using this tool and try an alternative approach.",
					tool, count
				)
			}
		end
	end

	return nil
end

--[[
    Get error statistics for current session
    @return table
]]
function ErrorAnalyzer.getStatistics()
	local stats = {
		totalErrors = #errorHistory,
		byCategory = {},
		byTool = {},
		recentTrend = "stable" -- stable, improving, worsening
	}

	for _, err in ipairs(errorHistory) do
		stats.byCategory[err.category] = (stats.byCategory[err.category] or 0) + 1
		stats.byTool[err.toolName] = (stats.byTool[err.toolName] or 0) + 1
	end

	-- Determine trend (compare first half to second half)
	if #errorHistory >= 10 then
		local midpoint = math.floor(#errorHistory / 2)
		local firstHalfCount = midpoint
		local secondHalfCount = #errorHistory - midpoint

		if secondHalfCount > firstHalfCount * 1.5 then
			stats.recentTrend = "worsening"
		elseif secondHalfCount < firstHalfCount * 0.5 then
			stats.recentTrend = "improving"
		end
	end

	return stats
end

--[[
    Clear error history (on conversation reset)
]]
function ErrorAnalyzer.clearHistory()
	errorHistory = {}
	if Constants.DEBUG then
		print("[ErrorAnalyzer] Error history cleared")
	end
end

-- ============================================================================
-- ADAPTIVE RECOVERY STRATEGY SELECTION
-- ============================================================================

-- Track recovery attempts to avoid repeating failed strategies
local recoveryAttempts = {}  -- category -> { strategy -> attemptCount }

--[[
    Record that a recovery strategy was attempted
    @param category string
    @param strategy string
]]
function ErrorAnalyzer.recordRecoveryAttempt(category, strategy)
	recoveryAttempts[category] = recoveryAttempts[category] or {}
	recoveryAttempts[category][strategy] = (recoveryAttempts[category][strategy] or 0) + 1

	if Constants.DEBUG then
		print(string.format("[ErrorAnalyzer] Recovery attempt recorded: %s -> %s (count: %d)",
			category, strategy, recoveryAttempts[category][strategy]))
	end
end

--[[
    Clear recovery attempts (on new task or conversation reset)
]]
function ErrorAnalyzer.resetRecoveryAttempts()
	recoveryAttempts = {}
	if Constants.DEBUG then
		print("[ErrorAnalyzer] Recovery attempts reset")
	end
end

-- Define recovery strategies with priority order
local RECOVERY_STRATEGIES = {
	missing_resource = {
		{ strategy = "verify_path", tool = "get_instance", message = "Verify the path exists" },
		{ strategy = "list_parent", tool = "list_children", message = "List parent contents to find correct name" },
		{ strategy = "search_project", tool = "search_scripts", message = "Search for the resource in the project" },
		{ strategy = "create_resource", tool = "create_instance", message = "Create the missing resource" },
	},
	syntax_error = {
		{ strategy = "reread_source", tool = "get_script", message = "Re-read the script to see current state" },
		{ strategy = "smaller_change", tool = "patch_script", message = "Make a smaller, targeted change" },
		{ strategy = "full_rewrite", tool = "edit_script", message = "Rewrite the problematic section entirely" },
	},
	search_failed = {
		{ strategy = "reread_source", tool = "get_script", message = "Re-read the file - content may have changed" },
		{ strategy = "partial_match", tool = "search_scripts", message = "Search for a unique part of the content" },
		{ strategy = "line_numbers", tool = "get_script", message = "Use line numbers to locate the section" },
		{ strategy = "full_replace", tool = "edit_script", message = "Replace the entire script instead of patching" },
	},
	ambiguous_match = {
		{ strategy = "add_context", tool = "get_script", message = "Include more context lines" },
		{ strategy = "unique_anchor", tool = "get_script", message = "Find a unique string nearby as anchor" },
		{ strategy = "line_reference", tool = "get_script", message = "Use line numbers for precise location" },
	},
	parent_error = {
		{ strategy = "verify_parent", tool = "list_children", message = "Verify parent path structure" },
		{ strategy = "create_parent", tool = "create_instance", message = "Create the parent container first" },
		{ strategy = "alternative_location", tool = "list_children", message = "Find alternative parent location" },
	},
	already_exists = {
		{ strategy = "use_existing", tool = "set_instance_properties", message = "Modify the existing resource" },
		{ strategy = "rename_new", tool = "create_instance", message = "Use a different name for the new resource" },
		{ strategy = "delete_first", tool = "delete_instance", message = "Delete the existing one first" },
	},
	property_error = {
		{ strategy = "inspect_instance", tool = "get_instance", message = "Inspect the instance properties" },
		{ strategy = "check_class", tool = "get_instance", message = "Verify the instance class type" },
		{ strategy = "try_alternative", tool = "set_instance_properties", message = "Try alternative property format" },
	},
	type_error = {
		{ strategy = "check_format", tool = "get_instance", message = "Check expected value format" },
		{ strategy = "try_string", tool = "set_instance_properties", message = "Try passing value as string" },
		{ strategy = "try_components", tool = "set_instance_properties", message = "Try passing individual components" },
	},
	user_denied = {
		{ strategy = "explain_better", tool = nil, message = "Explain the purpose of the change" },
		{ strategy = "alternative_approach", tool = nil, message = "Propose an alternative approach" },
		{ strategy = "ask_user", tool = nil, message = "Ask the user what they prefer" },
	},
}

--[[
    Get the best recovery strategy, avoiding already-tried strategies
    @param classification table - From classify()
    @return table - { strategies: array, escalated: boolean, message: string }
]]
function ErrorAnalyzer.getAdaptiveRecovery(classification)
	local loopInfo = ErrorAnalyzer.detectErrorLoop()

	if loopInfo then
		return {
			escalated = true,
			strategies = {},
			message = loopInfo.message,
			forcedPause = true
		}
	end

	local category = classification.category
	local strategies = RECOVERY_STRATEGIES[category] or {}
	local attempts = recoveryAttempts[category] or {}

	-- Filter to strategies not yet exhausted (tried < 2 times)
	local availableStrategies = {}
	local exhaustedCount = 0

	for _, strat in ipairs(strategies) do
		local attemptCount = attempts[strat.strategy] or 0
		if attemptCount < 2 then
			table.insert(availableStrategies, {
				strategy = strat.strategy,
				tool = strat.tool,
				message = strat.message,
				attempts = attemptCount,
				priority = attemptCount == 0 and "recommended" or "fallback"
			})
		else
			exhaustedCount = exhaustedCount + 1
		end
	end

	-- If all strategies exhausted, escalate
	if #availableStrategies == 0 then
		return {
			escalated = true,
			strategies = {},
			message = string.format(
				"?? ESCALATION: All %d recovery strategies for '%s' have been attempted.\n" ..
					"Consider:\n" ..
					"  1. Ask the user for clarification\n" ..
					"  2. Try a completely different approach\n" ..
					"  3. Skip this step and continue with other tasks",
				exhaustedCount, category
			),
			requiresUserInput = true
		}
	end

	-- Sort by priority (untried first, then by original order)
	table.sort(availableStrategies, function(a, b)
		if a.attempts ~= b.attempts then
			return a.attempts < b.attempts
		end
		return false  -- Maintain original order for same attempt count
	end)

	return {
		escalated = false,
		strategies = availableStrategies,
		message = string.format(
			"?? Recovery options (%d/%d available):",
			#availableStrategies, #strategies
		),
		recommended = availableStrategies[1]
	}
end

--[[
    Get the best recovery strategy for current situation (legacy compatibility)
    @param classification table - From classify()
    @return table - Recommended action
]]
function ErrorAnalyzer.getBestRecovery(classification)
	local adaptive = ErrorAnalyzer.getAdaptiveRecovery(classification)

	if adaptive.escalated then
		return {
			action = "escalate",
			message = adaptive.message,
			forcedPause = adaptive.forcedPause or adaptive.requiresUserInput
		}
	end

	local best = adaptive.recommended
	if best then
		return {
			action = best.strategy,
			suggestedTool = best.tool,
			message = best.message
		}
	end

	return {
		action = "generic_retry",
		suggestedTool = nil,
		message = "Review the error and try a different approach"
	}
end

-- ============================================================================
-- FORMATTING FOR LLM
-- ============================================================================

--[[
    Format error info for injection into LLM conversation
    @param classification table - From classify()
    @return string - Formatted error context
]]
function ErrorAnalyzer.formatForLLM(classification)
	local parts = { classification.enhancedMessage }

	-- Add loop warning if applicable
	local loopInfo = ErrorAnalyzer.detectErrorLoop()
	if loopInfo then
		table.insert(parts, "\n" .. loopInfo.message)
	end

	-- Add best recovery suggestion
	local recovery = ErrorAnalyzer.getBestRecovery(classification)
	if recovery.suggestedTool then
		table.insert(parts, string.format(
			"\n?? Recommended: Use %s before retrying",
			recovery.suggestedTool
			))
	end

	return table.concat(parts, "\n")
end

return ErrorAnalyzer
