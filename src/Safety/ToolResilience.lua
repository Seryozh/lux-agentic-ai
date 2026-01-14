--[[
    ToolResilience.lua - Self-Healing Tool Connection Layer (v1.0)

    This module provides automatic recovery mechanisms for the tool execution layer.
    It sits between OpenRouterClient and Tools to catch and heal instabilities.

    Self-Healing Capabilities:
    1. Automatic retry with exponential backoff
    2. State synchronization detection and recovery
    3. Graceful degradation for partial failures
    4. Health monitoring and anomaly detection
    5. Tool output sanitization and validation
    6. Context repair after failures
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Utils = require(script.Parent.Parent.Shared.Utils)
local ContextSelector = require(script.Parent.Parent.Context.ContextSelector)

local ToolResilience = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local RESILIENCE_CONFIG = {
	-- Retry configuration
	maxRetries = 2,                     -- Max automatic retries per tool
	retryableErrors = {
		"timeout",
		"connection",
		"temporarily unavailable",
		"rate limit",
		"try again"
	},
	retryBackoffMs = {100, 500, 1000},  -- Exponential backoff: 100ms, 500ms, 1s

	-- State sync detection
	stateSyncCheckEnabled = true,
	stalePaths = {},                     -- Track paths that might be stale

	-- Health monitoring
	healthCheckEnabled = true,
	errorRateThreshold = 0.3,            -- 30% error rate triggers warning
	windowSize = 20,                     -- Track last 20 tool calls

	-- Output validation
	validateOutputs = true,
	sanitizeOutputs = true,
	maxOutputSize = 50000,               -- Truncate outputs over 50KB

	-- Graceful degradation
	degradationEnabled = true,
	fallbackStrategies = {},
}

-- ============================================================================
-- HEALTH TRACKING
-- ============================================================================

local healthMetrics = {
	totalCalls = 0,
	successfulCalls = 0,
	failedCalls = 0,
	retriedCalls = 0,
	autoRecoveredCalls = 0,
	recentResults = {},  -- Rolling window of last N results
	toolStats = {},      -- Per-tool statistics
}

--[[
    Record a tool execution result
    @param toolName string
    @param success boolean
    @param recovered boolean - Was this auto-recovered?
]]
local function recordToolResult(toolName, success, recovered)
	healthMetrics.totalCalls = healthMetrics.totalCalls + 1

	if success then
		healthMetrics.successfulCalls = healthMetrics.successfulCalls + 1
	else
		healthMetrics.failedCalls = healthMetrics.failedCalls + 1
	end

	if recovered then
		healthMetrics.autoRecoveredCalls = healthMetrics.autoRecoveredCalls + 1
	end

	-- Add to rolling window
	table.insert(healthMetrics.recentResults, {
		timestamp = tick(),
		toolName = toolName,
		success = success,
		recovered = recovered
	})

	-- Keep only last N results
	if #healthMetrics.recentResults > RESILIENCE_CONFIG.windowSize then
		table.remove(healthMetrics.recentResults, 1)
	end

	-- Per-tool stats
	if not healthMetrics.toolStats[toolName] then
		healthMetrics.toolStats[toolName] = {
			total = 0,
			successful = 0,
			failed = 0,
			recovered = 0
		}
	end

	local toolStat = healthMetrics.toolStats[toolName]
	toolStat.total = toolStat.total + 1
	if success then
		toolStat.successful = toolStat.successful + 1
	else
		toolStat.failed = toolStat.failed + 1
	end
	if recovered then
		toolStat.recovered = toolStat.recovered + 1
	end
end

--[[
    Check current system health
    @return table - {healthy: bool, errorRate: number, warnings: array}
]]
function ToolResilience.checkHealth()
	if not RESILIENCE_CONFIG.healthCheckEnabled then
		return { healthy = true, errorRate = 0, warnings = {} }
	end

	local warnings = {}

	-- Calculate error rate from recent window
	local recentErrors = 0
	for _, result in ipairs(healthMetrics.recentResults) do
		if not result.success then
			recentErrors = recentErrors + 1
		end
	end

	local errorRate = 0
	if #healthMetrics.recentResults > 0 then
		errorRate = recentErrors / #healthMetrics.recentResults
	end

	-- Check if error rate exceeds threshold
	local healthy = true
	if errorRate > RESILIENCE_CONFIG.errorRateThreshold then
		healthy = false
		table.insert(warnings, string.format(
			"High error rate: %.1f%% (%d/%d recent calls failed)",
			errorRate * 100,
			recentErrors,
			#healthMetrics.recentResults
		))
	end

	-- Check for tools with consistently high failure rates
	for toolName, stats in pairs(healthMetrics.toolStats) do
		if stats.total >= 5 then  -- Only check if sufficient sample size
			local toolErrorRate = stats.failed / stats.total
			if toolErrorRate > 0.5 then
				table.insert(warnings, string.format(
					"Tool '%s' has high failure rate: %.1f%% (%d/%d)",
					toolName,
					toolErrorRate * 100,
					stats.failed,
					stats.total
				))
			end
		end
	end

	return {
		healthy = healthy,
		errorRate = errorRate,
		warnings = warnings,
		metrics = {
			totalCalls = healthMetrics.totalCalls,
			successRate = healthMetrics.totalCalls > 0
				and (healthMetrics.successfulCalls / healthMetrics.totalCalls)
				or 0,
			autoRecoveryRate = healthMetrics.failedCalls > 0
				and (healthMetrics.autoRecoveredCalls / healthMetrics.failedCalls)
				or 0
		}
	}
end

-- ============================================================================
-- ERROR CLASSIFICATION
-- ============================================================================

--[[
    Classify an error to determine if it's retryable
    @param error string - Error message
    @return table - {retryable: bool, reason: string, strategy: string}
]]
local function classifyError(error)
	if not error then
		return { retryable = false, reason = "unknown", strategy = nil }
	end

	local errorLower = error:lower()

	-- Check for retryable error patterns
	for _, pattern in ipairs(RESILIENCE_CONFIG.retryableErrors) do
		if errorLower:find(pattern, 1, true) then
			return {
				retryable = true,
				reason = pattern,
				strategy = "simple_retry"
			}
		end
	end

	-- Check for specific recoverable errors
	if errorLower:find("script not found") or errorLower:find("instance not found") then
		return {
			retryable = true,
			reason = "path_not_found",
			strategy = "refresh_and_retry"
		}
	end

	if errorLower:find("search content not found") or errorLower:find("exact match") then
		return {
			retryable = true,
			reason = "stale_content",
			strategy = "refresh_and_retry"
		}
	end

	if errorLower:find("property") and errorLower:find("cannot") then
		return {
			retryable = false,
			reason = "property_error",
			strategy = "suggest_fix"
		}
	end

	-- Unknown error - not retryable by default
	return {
		retryable = false,
		reason = "unknown",
		strategy = nil
	}
end

-- ============================================================================
-- STATE SYNCHRONIZATION
-- ============================================================================

--[[
    Detect if a tool failure is due to stale state
    @param toolName string
    @param args table
    @param error string
    @return table - {isStale: bool, suggestion: string}
]]
local function detectStaleState(toolName, args, error)
	if not RESILIENCE_CONFIG.stateSyncCheckEnabled then
		return { isStale = false, suggestion = nil }
	end

	local path = args.path
	if not path then
		return { isStale = false, suggestion = nil }
	end

	-- Check if this path was recently flagged as potentially stale
	if RESILIENCE_CONFIG.stalePaths[path] then
		local staleness = tick() - RESILIENCE_CONFIG.stalePaths[path]
		if staleness < 300 then  -- Within 5 minutes
			return {
				isStale = true,
				suggestion = string.format(
					"This script/instance may have changed. Re-read with get_script or get_instance before retrying."
				)
			}
		end
	end

	-- Check ContextSelector freshness data
	local freshness = ContextSelector.getFreshness(path)
	if freshness.modifiedAfterRead then
		-- Mark as stale
		RESILIENCE_CONFIG.stalePaths[path] = tick()

		return {
			isStale = true,
			suggestion = string.format(
				"Script was modified after last read (%.0f seconds ago). Use get_script to refresh.",
				freshness.timeSinceRead or 0
			)
		}
	end

	return { isStale = false, suggestion = nil }
end

--[[
    Attempt to synchronize state before retry
    @param toolName string
    @param args table
    @return table - {synced: bool, info: string}
]]
local function attemptStateSync(toolName, args)
	local path = args.path
	if not path then
		return { synced = false, info = "No path to sync" }
	end

	-- Clear stale flag for this path
	RESILIENCE_CONFIG.stalePaths[path] = nil

	-- Record that we're re-syncing (ContextSelector will track freshness)
	-- The actual re-read will happen when AI calls get_script in response

	return {
		synced = true,
		info = string.format("Flagged path '%s' for re-read", path)
	}
end

-- ============================================================================
-- OUTPUT VALIDATION & SANITIZATION
-- ============================================================================

--[[
    Validate tool output for common issues
    @param toolName string
    @param output table
    @return table - {valid: bool, issues: array, sanitized: table}
]]
local function validateAndSanitizeOutput(toolName, output)
	if not RESILIENCE_CONFIG.validateOutputs then
		return { valid = true, issues = {}, sanitized = output }
	end

	local issues = {}
	local sanitized = Utils.deepCopy(output) or {}

	-- 1. Check for nil/invalid responses
	if not output then
		table.insert(issues, "Output is nil")
		return {
			valid = false,
			issues = issues,
			sanitized = { error = "Tool returned nil output" }
		}
	end

	-- 2. Size check - prevent massive outputs
	local outputStr = game:GetService("HttpService"):JSONEncode(sanitized)
	if #outputStr > RESILIENCE_CONFIG.maxOutputSize then
		table.insert(issues, string.format(
			"Output too large (%d chars), truncating to %d",
			#outputStr,
			RESILIENCE_CONFIG.maxOutputSize
		))

		-- Truncate large fields
		if sanitized.source and #sanitized.source > 10000 then
			sanitized.source = sanitized.source:sub(1, 10000) .. "\n... [truncated]"
			sanitized.truncated = true
		end

		if sanitized.content and #sanitized.content > 10000 then
			sanitized.content = sanitized.content:sub(1, 10000) .. "\n... [truncated]"
			sanitized.truncated = true
		end
	end

	-- 3. Sanitize dangerous characters
	if RESILIENCE_CONFIG.sanitizeOutputs then
		for key, value in pairs(sanitized) do
			if type(value) == "string" then
				-- Remove null bytes
				sanitized[key] = value:gsub("\0", "")
			end
		end
	end

	-- 4. Tool-specific validations
	if toolName == "get_script" then
		if sanitized.success and not sanitized.source then
			table.insert(issues, "get_script succeeded but returned no source")
			sanitized.error = "Script source is empty or missing"
			sanitized.success = false
		end
	end

	if toolName == "get_instance" then
		if sanitized.success and not sanitized.properties then
			table.insert(issues, "get_instance succeeded but returned no properties")
			sanitized.error = "Instance properties missing"
			sanitized.success = false
		end
	end

	return {
		valid = #issues == 0,
		issues = issues,
		sanitized = sanitized
	}
end

-- ============================================================================
-- RETRY LOGIC WITH BACKOFF
-- ============================================================================

--[[
    Execute tool with automatic retry on transient failures
    @param toolExecuteFn function - The actual Tools.execute function
    @param toolName string
    @param args table
    @return table - {result: table, attempts: number, recovered: bool}
]]
local function executeWithRetry(toolExecuteFn, toolName, args)
	local attempts = 0
	local lastError = nil
	local recovered = false

	for attempt = 1, RESILIENCE_CONFIG.maxRetries + 1 do
		attempts = attempt

		-- Execute tool
		local success, result = pcall(toolExecuteFn, toolName, args)

		if not success then
			-- pcall failure (Lua error)
			lastError = tostring(result)
			if Constants.DEBUG then
				warn(string.format("[ToolResilience] Attempt %d/%d failed with Lua error: %s",
					attempt, RESILIENCE_CONFIG.maxRetries + 1, lastError))
			end

			-- Wait before retry
			if attempt <= RESILIENCE_CONFIG.maxRetries then
				local backoffMs = RESILIENCE_CONFIG.retryBackoffMs[attempt] or 1000
				task.wait(backoffMs / 1000)
			end

		elseif result and result.error then
			-- Tool returned error
			lastError = result.error

			-- Classify error
			local classification = classifyError(lastError)

			if not classification.retryable or attempt > RESILIENCE_CONFIG.maxRetries then
				-- Not retryable or out of retries
				if Constants.DEBUG and attempt > 1 then
					warn(string.format("[ToolResilience] Giving up after %d attempts. Last error: %s",
						attempt, lastError))
				end
				return { result = result, attempts = attempts, recovered = false }
			end

			-- Check for stale state
			local staleCheck = detectStaleState(toolName, args, lastError)
			if staleCheck.isStale and classification.strategy == "refresh_and_retry" then
				-- Attempt state sync
				attemptStateSync(toolName, args)

				-- Enhance error with sync suggestion
				result.error = result.error .. "\n\n" .. staleCheck.suggestion
				result.staleSuggestion = staleCheck.suggestion

				if Constants.DEBUG then
					print(string.format("[ToolResilience] Detected stale state for '%s'. Suggesting re-read.",
						args.path or "unknown"))
				end

				-- Return immediately with suggestion (let AI fix it)
				return { result = result, attempts = attempts, recovered = false }
			end

			if Constants.DEBUG then
				warn(string.format("[ToolResilience] Attempt %d/%d failed: %s (retryable: %s)",
					attempt, RESILIENCE_CONFIG.maxRetries + 1, lastError, tostring(classification.retryable)))
			end

			-- Wait before retry
			if attempt <= RESILIENCE_CONFIG.maxRetries then
				local backoffMs = RESILIENCE_CONFIG.retryBackoffMs[attempt] or 1000
				task.wait(backoffMs / 1000)
			end

		else
			-- Success!
			if attempt > 1 then
				recovered = true
				if Constants.DEBUG then
					print(string.format("[ToolResilience] Recovered after %d attempts", attempt))
				end
			end

			-- Validate and sanitize output
			local validation = validateAndSanitizeOutput(toolName, result)
			if not validation.valid then
				if Constants.DEBUG then
					warn(string.format("[ToolResilience] Output validation issues: %s",
						table.concat(validation.issues, ", ")))
				end
			end

			return {
				result = validation.sanitized,
				attempts = attempts,
				recovered = recovered,
				validationIssues = validation.issues
			}
		end
	end

	-- Exhausted all retries
	return {
		result = { error = lastError or "Tool execution failed after retries" },
		attempts = attempts,
		recovered = false
	}
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Execute a tool with full resilience layer
    @param toolExecuteFn function - The actual Tools.execute function
    @param toolName string
    @param args table
    @return table - Tool result (with potential enhancements)
]]
function ToolResilience.executeResilient(toolExecuteFn, toolName, args)
	local startTime = tick()

	-- Execute with retry logic
	local execution = executeWithRetry(toolExecuteFn, toolName, args)

	local duration = tick() - startTime
	local success = execution.result and not execution.result.error

	-- Record metrics
	recordToolResult(toolName, success, execution.recovered)

	-- Add resilience metadata to result
	if execution.recovered then
		execution.result.resilience = {
			recovered = true,
			attempts = execution.attempts,
			duration = duration
		}
	end

	if execution.validationIssues and #execution.validationIssues > 0 then
		if not execution.result.resilience then
			execution.result.resilience = {}
		end
		execution.result.resilience.validationIssues = execution.validationIssues
	end

	-- Health check (if unhealthy, add warning to output)
	if RESILIENCE_CONFIG.healthCheckEnabled then
		local health = ToolResilience.checkHealth()
		if not health.healthy and execution.result.error then
			-- Append health warning to error
			execution.result.healthWarning = health.warnings[1]  -- First warning
		end
	end

	if Constants.DEBUG then
		print(string.format("[ToolResilience] %s completed in %.2fs (attempts: %d, success: %s, recovered: %s)",
			toolName, duration, execution.attempts, tostring(success), tostring(execution.recovered)))
	end

	return execution.result
end

--[[
    Get current health metrics
    @return table - Health metrics
]]
function ToolResilience.getMetrics()
	return {
		totalCalls = healthMetrics.totalCalls,
		successfulCalls = healthMetrics.successfulCalls,
		failedCalls = healthMetrics.failedCalls,
		retriedCalls = healthMetrics.retriedCalls,
		autoRecoveredCalls = healthMetrics.autoRecoveredCalls,
		successRate = healthMetrics.totalCalls > 0
			and (healthMetrics.successfulCalls / healthMetrics.totalCalls)
			or 0,
		recoveryRate = healthMetrics.failedCalls > 0
			and (healthMetrics.autoRecoveredCalls / healthMetrics.failedCalls)
			or 0,
		toolStats = healthMetrics.toolStats
	}
end

--[[
    Reset all metrics and state
]]
function ToolResilience.reset()
	healthMetrics = {
		totalCalls = 0,
		successfulCalls = 0,
		failedCalls = 0,
		retriedCalls = 0,
		autoRecoveredCalls = 0,
		recentResults = {},
		toolStats = {},
	}
	RESILIENCE_CONFIG.stalePaths = {}

	if Constants.DEBUG then
		print("[ToolResilience] Reset all metrics and state")
	end
end

--[[
    Configure resilience behavior
    @param config table - Configuration overrides
]]
function ToolResilience.configure(config)
	for key, value in pairs(config) do
		if RESILIENCE_CONFIG[key] ~= nil then
			RESILIENCE_CONFIG[key] = value
		end
	end
end

return ToolResilience
