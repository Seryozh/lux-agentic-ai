--[[
    CircuitBreaker.lua
    Hard safety boundary for the agentic loop

    Implements the circuit breaker pattern to prevent failure spirals:
    - CLOSED: Normal operation, failures counted
    - OPEN: Blocked after threshold failures, requires user intervention
    - HALF-OPEN: Testing state after cooldown, one attempt allowed

    This provides a hard stop that ErrorAnalyzer's loop detection doesn't offer.
]]

local Constants = require(script.Parent.Parent.Shared.Constants)

local CircuitBreaker = {}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
	mode = "closed",       -- closed (normal), open (blocked), half-open (testing)
	failures = 0,
	openedAt = nil,
	lastFailure = nil,
	totalTrips = 0,        -- How many times circuit has opened (lifetime stat)
}

-- Per-tool circuit tracking (optional granular control)
local toolCircuits = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local CONFIG = {
	failureThreshold = 5,      -- Failures before opening
	cooldownPeriod = 30,       -- Seconds before auto-retry (half-open)
	resetOnSuccess = true,     -- Reset counter on any success
	trackPerTool = false,      -- Separate circuits per tool (disabled by default)
	warningThreshold = 3,      -- Warn user after this many failures
}

-- ============================================================================
-- CORE FUNCTIONS
-- ============================================================================

--[[
    Record a failure and potentially open the circuit
    @param toolName string - The tool that failed
    @param error string - The error message
    @return table - { halt: boolean, message: string, requiresUserAction: boolean }
]]
function CircuitBreaker.recordFailure(toolName, error)
	state.failures = state.failures + 1
	state.lastFailure = {
		tool = toolName,
		error = error,
		timestamp = tick()
	}

	-- Track per-tool if enabled
	if CONFIG.trackPerTool then
		toolCircuits[toolName] = toolCircuits[toolName] or { failures = 0 }
		toolCircuits[toolName].failures = toolCircuits[toolName].failures + 1
	end

	-- Check if we should open the circuit
	if state.failures >= CONFIG.failureThreshold then
		state.mode = "open"
		state.openedAt = tick()
		state.totalTrips = state.totalTrips + 1

		if Constants.DEBUG then
			print(string.format("[CircuitBreaker] OPENED after %d failures (trip #%d)",
				state.failures, state.totalTrips))
		end

		return {
			halt = true,
			message = string.format(
				"?? CIRCUIT BREAKER OPEN: %d consecutive failures.\n" ..
					"Last error: %s\n" ..
					"The system is pausing for user input to prevent further issues.\n" ..
					"You can:\n" ..
					"  1. Provide guidance on what to try differently\n" ..
					"  2. Ask me to skip this step and continue\n" ..
					"  3. Reset the conversation to start fresh",
				state.failures,
				error and error:sub(1, 150) or "unknown"
			),
			requiresUserAction = true
		}
	end

	-- Warning at threshold
	if state.failures == CONFIG.warningThreshold then
		return {
			halt = false,
			warning = string.format(
				"?? Warning: %d failures so far. Circuit breaker will activate at %d failures.",
				state.failures, CONFIG.failureThreshold
			)
		}
	end

	return { halt = false }
end

--[[
    Record a success and potentially close the circuit
]]
function CircuitBreaker.recordSuccess()
	if CONFIG.resetOnSuccess then
		state.failures = 0
	end

	-- Transition from half-open to closed on success
	if state.mode == "half-open" then
		state.mode = "closed"
		state.openedAt = nil

		if Constants.DEBUG then
			print("[CircuitBreaker] CLOSED - recovery successful")
		end
	end

	-- Reset per-tool counters
	if CONFIG.trackPerTool then
		toolCircuits = {}
	end
end

--[[
    Check if operations can proceed
    @return boolean, string|nil - canProceed, warning message
]]
function CircuitBreaker.canProceed()
	if state.mode == "closed" then
		return true, nil
	end

	if state.mode == "open" then
		-- Check if cooldown has passed
		local elapsed = tick() - (state.openedAt or 0)
		if elapsed > CONFIG.cooldownPeriod then
			state.mode = "half-open"

			if Constants.DEBUG then
				print("[CircuitBreaker] Transitioning to HALF-OPEN after cooldown")
			end

			return true, "?? Circuit half-open: testing with next operation"
		end

		return false, string.format(
			"?? Circuit open. Waiting %.0f more seconds or provide input to continue.",
			CONFIG.cooldownPeriod - elapsed
		)
	end

	-- half-open: allow one attempt
	return true, "?? Circuit half-open: this is a test operation"
end

--[[
    Force reset the circuit breaker (user intervention)
]]
function CircuitBreaker.forceReset()
	local wasOpen = state.mode ~= "closed"

	state.mode = "closed"
	state.failures = 0
	state.openedAt = nil
	state.lastFailure = nil
	toolCircuits = {}

	if Constants.DEBUG and wasOpen then
		print("[CircuitBreaker] Force reset by user")
	end
end

--[[
    Get current circuit status
    @return table - Status information
]]
function CircuitBreaker.getStatus()
	return {
		mode = state.mode,
		failures = state.failures,
		failureThreshold = CONFIG.failureThreshold,
		lastFailure = state.lastFailure,
		totalTrips = state.totalTrips,
		isOpen = state.mode == "open",
		isHalfOpen = state.mode == "half-open",
		timeUntilHalfOpen = state.mode == "open"
			and math.max(0, CONFIG.cooldownPeriod - (tick() - (state.openedAt or 0)))
			or nil
	}
end

--[[
    Check if a specific tool's circuit is open (when trackPerTool is enabled)
    @param toolName string
    @return boolean, string|nil
]]
function CircuitBreaker.canToolProceed(toolName)
	if not CONFIG.trackPerTool then
		return CircuitBreaker.canProceed()
	end

	local toolState = toolCircuits[toolName]
	if not toolState then
		return true, nil
	end

	if toolState.failures >= CONFIG.failureThreshold then
		return false, string.format(
			"?? Tool '%s' circuit is open after %d failures. Try a different approach.",
			toolName, toolState.failures
		)
	end

	return true, nil
end

--[[
    Format status for inclusion in LLM prompt
    @return string|nil
]]
function CircuitBreaker.formatForPrompt()
	if state.mode == "closed" and state.failures == 0 then
		return nil
	end

	local parts = {}

	if state.mode == "open" then
		table.insert(parts, "?? CIRCUIT BREAKER IS OPEN")
		table.insert(parts, string.format("  Failures: %d", state.failures))
		if state.lastFailure then
			table.insert(parts, string.format("  Last error: %s", state.lastFailure.error:sub(1, 80)))
		end
		table.insert(parts, "  STOP and wait for user guidance before proceeding.")

	elseif state.mode == "half-open" then
		table.insert(parts, "?? CIRCUIT BREAKER HALF-OPEN")
		table.insert(parts, "  Next operation is a test. Be extra careful.")

	elseif state.failures > 0 then
		table.insert(parts, string.format(
			"?? Circuit breaker: %d/%d failures. Consider changing approach.",
			state.failures, CONFIG.failureThreshold
			))
	end

	return table.concat(parts, "\n")
end

--[[
    Get statistics for debugging/monitoring
    @return table
]]
function CircuitBreaker.getStatistics()
	return {
		currentMode = state.mode,
		currentFailures = state.failures,
		totalTrips = state.totalTrips,
		lastFailure = state.lastFailure,
		config = CONFIG
	}
end

return CircuitBreaker
