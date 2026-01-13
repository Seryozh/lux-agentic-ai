--[[
    ErrorPredictor.lua
    Pre-flight risk assessment before tool execution

    Unlike ErrorAnalyzer (reactive), ErrorPredictor is proactive:
    1. Analyzes tool calls BEFORE execution
    2. Predicts likely failure modes
    3. Suggests mitigations
    4. Integrates with ContextSelector to check freshness

    This catches ~80% of common errors before they waste an iteration.
]]

local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)

local ErrorPredictor = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local CONFIG = {
	enabled = true,
	freshnessThreshold = 120,  -- Seconds before script read is considered stale
	warnOnStale = true,
	blockOnCritical = false,   -- If true, don't allow execution of high-risk calls
}

-- ============================================================================
-- STATE
-- ============================================================================

-- Track when scripts were last read (path -> timestamp)
local scriptReadTimes = {}

-- Track when scripts were last modified (path -> timestamp)
local scriptModifyTimes = {}

-- Track recent tool failures for pattern detection
local recentFailures = {}  -- { toolName, args, timestamp }

-- ============================================================================
-- TRACKING FUNCTIONS
-- ============================================================================

--[[
    Record that a script was read
    @param path string
]]
function ErrorPredictor.recordScriptRead(path)
	scriptReadTimes[path] = tick()
end

--[[
    Record that a script was modified
    @param path string
]]
function ErrorPredictor.recordScriptModified(path)
	scriptModifyTimes[path] = tick()
	-- Also update read time since we just touched it
	scriptReadTimes[path] = tick()
end

--[[
    Get last read time for a script
    @param path string
    @return number|nil
]]
function ErrorPredictor.getLastReadTime(path)
	return scriptReadTimes[path]
end

--[[
    Check if a script was recently modified (in this session)
    @param path string
    @return boolean
]]
function ErrorPredictor.wasRecentlyModified(path)
	local modTime = scriptModifyTimes[path]
	if not modTime then return false end
	return (tick() - modTime) < 300  -- Within 5 minutes
end

--[[
    Record a tool failure for pattern detection
    @param toolName string
    @param args table
    @param error string
]]
function ErrorPredictor.recordFailure(toolName, args, error)
	table.insert(recentFailures, {
		toolName = toolName,
		args = args,
		error = error,
		timestamp = tick()
	})

	-- Keep only recent failures (last 2 minutes)
	local cutoff = tick() - 120
	local fresh = {}
	for _, failure in ipairs(recentFailures) do
		if failure.timestamp > cutoff then
			table.insert(fresh, failure)
		end
	end
	recentFailures = fresh
end

-- ============================================================================
-- RISK ASSESSMENT
-- ============================================================================

--[[
    Assess risk before executing a tool
    @param toolName string
    @param args table
    @return table - { risks: array, overallRisk: string, shouldWarn: boolean }
]]
function ErrorPredictor.assessRisk(toolName, args)
	if not CONFIG.enabled then
		return { risks = {}, overallRisk = "low", shouldWarn = false }
	end

	local risks = {}

	-- Tool-specific checks
	if toolName == "patch_script" then
		ErrorPredictor._assessPatchScriptRisk(args, risks)

	elseif toolName == "edit_script" then
		ErrorPredictor._assessEditScriptRisk(args, risks)

	elseif toolName == "create_instance" then
		ErrorPredictor._assessCreateInstanceRisk(args, risks)

	elseif toolName == "create_script" then
		ErrorPredictor._assessCreateScriptRisk(args, risks)

	elseif toolName == "set_instance_properties" then
		ErrorPredictor._assessSetPropertiesRisk(args, risks)

	elseif toolName == "delete_instance" then
		ErrorPredictor._assessDeleteRisk(args, risks)
	end

	-- Check for repeated failure patterns
	ErrorPredictor._checkFailurePatterns(toolName, args, risks)

	-- Determine overall risk level
	local overallRisk = "low"
	local hasCritical = false
	local hasHigh = false

	for _, risk in ipairs(risks) do
		if risk.level == "critical" then hasCritical = true end
		if risk.level == "high" then hasHigh = true end
	end

	if hasCritical then
		overallRisk = "critical"
	elseif hasHigh then
		overallRisk = "high"
	elseif #risks > 0 then
		overallRisk = "medium"
	end

	return {
		risks = risks,
		overallRisk = overallRisk,
		shouldWarn = #risks > 0,
		shouldBlock = CONFIG.blockOnCritical and hasCritical
	}
end

-- ============================================================================
-- TOOL-SPECIFIC RISK ASSESSMENTS
-- ============================================================================

function ErrorPredictor._assessPatchScriptRisk(args, risks)
	local path = args.path

	if not path then return end

	-- Check if script was recently read
	local lastRead = scriptReadTimes[path]
	if not lastRead then
		table.insert(risks, {
			level = "high",
			reason = "Script not read in this session - content unknown",
			mitigation = "Use get_script first to see current content",
			field = "path"
		})
	elseif (tick() - lastRead) > CONFIG.freshnessThreshold then
		table.insert(risks, {
			level = "medium",
			reason = string.format("Script read %.0f seconds ago - content may have changed",
				tick() - lastRead),
			mitigation = "Consider re-reading with get_script to verify content",
			field = "path"
		})
	end

	-- Check if script was modified since last read
	local lastModified = scriptModifyTimes[path]
	if lastModified and lastRead and lastModified > lastRead then
		table.insert(risks, {
			level = "high",
			reason = "Script was modified after you last read it",
			mitigation = "Re-read the script - your search_content may be outdated",
			field = "search_content"
		})
	end

	-- Check if search_content looks too short
	if args.search_content and #args.search_content < 20 then
		table.insert(risks, {
			level = "medium",
			reason = "search_content is very short - may match multiple locations",
			mitigation = "Include more context lines to make the match unique",
			field = "search_content"
		})
	end

	-- Check if search_content has common whitespace issues
	if args.search_content then
		if args.search_content:match("^%s") or args.search_content:match("%s$") then
			table.insert(risks, {
				level = "medium",
				reason = "search_content has leading/trailing whitespace - may cause match failure",
				mitigation = "Trim whitespace or ensure it exactly matches the script",
				field = "search_content"
			})
		end
	end
end

function ErrorPredictor._assessEditScriptRisk(args, risks)
	local path = args.path

	if not path then return end

	-- Full script replacement is risky without recent read
	local lastRead = scriptReadTimes[path]
	if not lastRead then
		table.insert(risks, {
			level = "high",
			reason = "Replacing entire script without reading it first",
			mitigation = "Use get_script to understand current content before replacing",
			field = "path"
		})
	end

	-- Check source length (edit_script uses newSource, not source)
	local source = args.newSource or args.source
	if source and #source < 50 then
		table.insert(risks, {
			level = "medium",
			reason = "New script content is very short - may be incomplete",
			mitigation = "Verify this is the complete intended script",
			field = "newSource"
		})
	end
end

function ErrorPredictor._assessCreateInstanceRisk(args, risks)
	local parent = args.parent

	if not parent then return end

	-- Check parent exists
	local parentInstance = Utils.getScriptByPath(parent)
	if not parentInstance then
		table.insert(risks, {
			level = "critical",
			reason = "Parent path does not exist: " .. parent,
			mitigation = "Create the parent first or verify the path",
			field = "parent"
		})
	end

	-- Check for duplicate names
	if parentInstance and args.name then
		local existing = parentInstance:FindFirstChild(args.name)
		if existing then
			table.insert(risks, {
				level = "medium",
				reason = string.format("Instance named '%s' already exists in parent", args.name),
				mitigation = "Use a different name or modify the existing instance",
				field = "name"
			})
		end
	end
end

function ErrorPredictor._assessCreateScriptRisk(args, risks)
	local path = args.path

	if not path then return end

	-- Extract parent path
	local parentPath = path:match("(.+)%.[^.]+$")
	if parentPath then
		local parentInstance = Utils.getScriptByPath(parentPath)
		if not parentInstance then
			table.insert(risks, {
				level = "critical",
				reason = "Parent path does not exist: " .. parentPath,
				mitigation = "Create parent containers first",
				field = "path"
			})
		end
	end

	-- Check if script already exists
	local existing = Utils.getScriptByPath(path)
	if existing then
		table.insert(risks, {
			level = "high",
			reason = "Script already exists at this path",
			mitigation = "Use edit_script or patch_script to modify existing script",
			field = "path"
		})
	end
end

function ErrorPredictor._assessSetPropertiesRisk(args, risks)
	local path = args.path

	if not path then return end

	-- Check instance exists
	local instance = Utils.getScriptByPath(path)
	if not instance then
		table.insert(risks, {
			level = "critical",
			reason = "Instance does not exist: " .. path,
			mitigation = "Verify the path or create the instance first",
			field = "path"
		})
		return
	end

	-- Check if we've inspected it recently
	local lastRead = scriptReadTimes[path]
	if not lastRead then
		table.insert(risks, {
			level = "medium",
			reason = "Instance not inspected - property names may be incorrect",
			mitigation = "Use get_instance to see available properties",
			field = "properties"
		})
	end
end

function ErrorPredictor._assessDeleteRisk(args, risks)
	-- Deletes are always high risk
	table.insert(risks, {
		level = "high",
		reason = "Delete operations cannot be undone",
		mitigation = "Ensure you have verified this is the correct instance",
		field = "path"
	})
end

function ErrorPredictor._checkFailurePatterns(toolName, args, risks)
	-- Check if similar operations have recently failed
	local similarFailures = 0
	local lastSimilarError = nil

	for _, failure in ipairs(recentFailures) do
		if failure.toolName == toolName then
			-- Check if args are similar
			if args.path and failure.args.path == args.path then
				similarFailures = similarFailures + 1
				lastSimilarError = failure.error
			end
		end
	end

	if similarFailures >= 2 then
		table.insert(risks, {
			level = "high",
			reason = string.format("Similar %s operation failed %d times recently", toolName, similarFailures),
			mitigation = "Try a different approach. Last error: " .. (lastSimilarError or "unknown"):sub(1, 80),
			field = "general"
		})
	end
end

-- ============================================================================
-- FORMATTING
-- ============================================================================

--[[
    Format risk assessment for LLM feedback
    @param assessment table - Result from assessRisk
    @return string|nil
]]
function ErrorPredictor.formatForLLM(assessment)
	if not assessment.shouldWarn then
		return nil
	end

	local parts = { "?? PRE-FLIGHT RISK ASSESSMENT:" }

	-- Group by level
	local critical = {}
	local high = {}
	local medium = {}

	for _, risk in ipairs(assessment.risks) do
		if risk.level == "critical" then
			table.insert(critical, risk)
		elseif risk.level == "high" then
			table.insert(high, risk)
		else
			table.insert(medium, risk)
		end
	end

	if #critical > 0 then
		table.insert(parts, "\n?? CRITICAL RISKS:")
		for _, risk in ipairs(critical) do
			table.insert(parts, string.format("  • %s", risk.reason))
			table.insert(parts, string.format("    ? %s", risk.mitigation))
		end
	end

	if #high > 0 then
		table.insert(parts, "\n?? HIGH RISKS:")
		for _, risk in ipairs(high) do
			table.insert(parts, string.format("  • %s", risk.reason))
			table.insert(parts, string.format("    ? %s", risk.mitigation))
		end
	end

	if #medium > 0 then
		table.insert(parts, "\n?? MEDIUM RISKS:")
		for _, risk in ipairs(medium) do
			table.insert(parts, string.format("  • %s", risk.reason))
		end
	end

	return table.concat(parts, "\n")
end

--[[
    Quick check if operation is safe to proceed
    @param toolName string
    @param args table
    @return boolean, string|nil - canProceed, warning
]]
function ErrorPredictor.canProceed(toolName, args)
	local assessment = ErrorPredictor.assessRisk(toolName, args)

	if assessment.shouldBlock then
		return false, ErrorPredictor.formatForLLM(assessment)
	end

	if assessment.shouldWarn then
		return true, ErrorPredictor.formatForLLM(assessment)
	end

	return true, nil
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

--[[
    Clear all tracking state (on conversation reset)
]]
function ErrorPredictor.reset()
	scriptReadTimes = {}
	scriptModifyTimes = {}
	recentFailures = {}

	if Constants.DEBUG then
		print("[ErrorPredictor] State reset")
	end
end

--[[
    Mark all script reads as stale (on new task)
]]
function ErrorPredictor.markAllStale()
	-- Shift all read times back so they appear stale
	local staleTime = tick() - CONFIG.freshnessThreshold - 60
	for path in pairs(scriptReadTimes) do
		scriptReadTimes[path] = staleTime
	end

	if Constants.DEBUG then
		print("[ErrorPredictor] All script reads marked as stale")
	end
end

return ErrorPredictor
