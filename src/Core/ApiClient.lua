--[[
	ApiClient.lua
	Core module: API Communication & HTTP Request Management

	Responsibilities:
	- API key management (get, save, validate)
	- HTTP request execution with timeout and retry logic
	- OpenRouter API communication
	- Credit balance fetching
	- Token usage tracking
	- AI summary generation for history compression

	This module handles all external HTTP communication with the OpenRouter API.
]]

local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.Shared.Constants)
local Utils = require(script.Parent.Parent.Shared.Utils)

local ApiClient = {}

-- ============================================================================
-- PLUGIN INSTANCE & STATE
-- ============================================================================

-- Store reference to plugin for settings
local pluginInstance = nil

-- Current model (can be changed at runtime)
local currentModel = Constants.OPENROUTER_MODEL

-- Token usage tracking for current session
local tokenUsage = {
	promptTokens = 0,
	completionTokens = 0,
	totalTokens = 0,
	apiCalls = 0,
	totalCost = 0,
	lastRequestCost = 0
}

-- Credit balance (fetched from API)
local creditBalance = nil

-- ============================================================================
-- API KEY MANAGEMENT
-- ============================================================================

--[[
	Get the API Key from plugin settings
	@return string|nil - API key or nil if not set
]]
local function getApiKey()
	if pluginInstance then
		local savedKey = pluginInstance:GetSetting("OPENROUTER_API_KEY")
		if savedKey and savedKey ~= "" then
			return savedKey
		end
	end
	return nil
end

--[[
	Save API key to plugin settings
	@param key string - The API key to save
]]
function ApiClient.saveApiKey(key)
	if pluginInstance then
		pluginInstance:SetSetting("OPENROUTER_API_KEY", key)
	end
end

--[[
	Initialize API client with plugin instance
	@param plugin Plugin - The plugin instance for settings storage
]]
function ApiClient.init(plugin)
	pluginInstance = plugin

	-- Load saved model preference
	local savedModel = plugin:GetSetting("OPENROUTER_MODEL")
	if savedModel and savedModel ~= "" then
		currentModel = savedModel
	end
end

--[[
	Get current model ID
	@return string - Current model ID
]]
function ApiClient.getCurrentModel()
	return currentModel
end

--[[
	Set model and persist to settings
	@param modelId string - Model ID to use
]]
function ApiClient.setModel(modelId)
	currentModel = modelId
	if pluginInstance then
		pluginInstance:SetSetting("OPENROUTER_MODEL", modelId)
	end
end

-- ============================================================================
-- HTTP REQUEST WITH TIMEOUT
-- ============================================================================

--[[
	Execute a function with timeout
	@param fn function - Function to execute
	@param timeout number - Timeout in seconds
	@return result|nil, error|nil
]]
local function withTimeout(fn, timeout)
	local done, result, err = false, nil, nil

	task.spawn(function()
		local ok, res = pcall(fn)
		if ok then
			result = res
		else
			err = res
		end
		done = true
	end)

	local start = tick()
	while not done and (tick() - start) < timeout do
		task.wait(0.1)
	end

	if not done then
		return nil, "Timeout"
	end

	if err then
		return nil, err
	end

	return result, nil
end

-- ============================================================================
-- API KEY VALIDATION & CREDITS
-- ============================================================================

--[[
	Validate an API key by checking credits endpoint
	@param key string - The API key to validate
	@return table - {valid: bool, credits: table|nil, error: string|nil}
]]
function ApiClient.validateApiKey(key)
	local result, err = withTimeout(function()
		return HttpService:RequestAsync({
			Url = Constants.OPENROUTER_CREDITS_ENDPOINT,
			Method = "GET",
			Headers = {
				["Authorization"] = "Bearer " .. key
			}
		})
	end, 10)

	if err then
		return { valid = false, error = "Connection failed: " .. tostring(err) }
	end

	if result.StatusCode == 401 then
		return { valid = false, error = "Invalid API key" }
	end

	if not result.Success then
		return { valid = false, error = "HTTP " .. result.StatusCode }
	end

	local success, parsed = pcall(function()
		return HttpService:JSONDecode(result.Body)
	end)

	if not success or not parsed.data then
		return { valid = false, error = "Invalid response from OpenRouter" }
	end

	local data = parsed.data
	return {
		valid = true,
		credits = {
			total = data.total_credits or 0,
			used = data.total_usage or 0,
			remaining = (data.total_credits or 0) - (data.total_usage or 0)
		}
	}
end

--[[
	Fetch current credit balance
	@return table|nil - {total, used, remaining} or nil on error
]]
function ApiClient.getCredits()
	local key = getApiKey()
	if not key then return nil end

	local result = ApiClient.validateApiKey(key)
	if result.valid then
		creditBalance = result.credits
		return result.credits
	end
	return nil
end

--[[
	Get current credit balance (cached)
	@return table|nil - {total, used, remaining} or nil
]]
function ApiClient.getCreditBalance()
	return creditBalance
end

-- ============================================================================
-- TOKEN USAGE TRACKING
-- ============================================================================

--[[
	Get current token usage statistics
	@return table - Token usage data
]]
function ApiClient.getTokenUsage()
	return tokenUsage
end

--[[
	Reset token usage statistics
]]
function ApiClient.resetTokenUsage()
	tokenUsage = {
		promptTokens = 0,
		completionTokens = 0,
		totalTokens = 0,
		apiCalls = 0,
		totalCost = 0,
		lastRequestCost = 0
	}
end

-- ============================================================================
-- API COMMUNICATION
-- ============================================================================

--[[
	Call OpenRouter API with messages and tools
	@param messages table - Array of messages in OpenAI format
	@param tools table - Array of tool definitions
	@return table - {success: bool, response: table} or {success: false, error: string}
]]
function ApiClient.callAPI(messages, tools)
	local key = getApiKey()
	if not key then
		return { success = false, error = "No API key configured" }
	end

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Calling OpenRouter API (%d messages)", #messages))
	end

	-- Build request
	local requestBody = {
		model = currentModel,
		messages = messages,
		tools = tools,
		max_tokens = Constants.GENERATION_CONFIG.maxOutputTokens or 65536,
		temperature = Constants.GENERATION_CONFIG.temperature or 1.0,
		usage = { include = true }  -- Get cost tracking
	}

	local requestBodyJson = HttpService:JSONEncode(requestBody)

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Request body size: %d characters", #requestBodyJson))
	end

	-- Make HTTP request with retry logic for transient errors
	local MAX_RETRIES = 3
	local RETRY_CODES = { [429] = true, [500] = true, [502] = true, [503] = true, [504] = true }
	local result, err
	local lastError

	for attempt = 1, MAX_RETRIES do
		local startTime = tick()
		result, err = withTimeout(function()
			return HttpService:RequestAsync({
				Url = Constants.OPENROUTER_ENDPOINT,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["Authorization"] = "Bearer " .. key,
					["HTTP-Referer"] = Constants.OPENROUTER_REFERER,
					["X-Title"] = "Lux",
					-- Explicitly tell OpenRouter we're using OpenAI format (no transforms)
					["OpenAI-Beta"] = "assistants=v1"
				},
				Body = requestBodyJson
			})
		end, Constants.REQUEST_TIMEOUT)

		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] API call attempt %d took %.2f seconds", attempt, tick() - startTime))
		end

		-- Check for timeout/network error
		if err then
			lastError = "Request failed: " .. tostring(err)
			if attempt < MAX_RETRIES then
				local backoff = math.pow(2, attempt - 1) * 2  -- 2s, 4s, 8s
				if Constants.DEBUG then
					print(string.format("[Lux DEBUG] Network error, retrying in %.1fs...", backoff))
				end
				task.wait(backoff)
			end
		elseif result.Success then
			-- Success - break out of retry loop
			break
		else
			-- HTTP error - check if retryable
			local statusCode = result.StatusCode

			if statusCode == 401 then
				return { success = false, error = "Invalid API key. Please check your OpenRouter key." }
			elseif statusCode == 402 then
				return { success = false, error = "Insufficient credits. Add credits at openrouter.ai" }
			elseif RETRY_CODES[statusCode] and attempt < MAX_RETRIES then
				-- Retryable error - exponential backoff
				local backoff = math.pow(2, attempt - 1) * 2  -- 2s, 4s, 8s
				lastError = string.format("HTTP %d - retrying...", statusCode)
				if Constants.DEBUG then
					print(string.format("[Lux DEBUG] HTTP %d, retrying in %.1fs (attempt %d/%d)",
						statusCode, backoff, attempt, MAX_RETRIES))
				end
				task.wait(backoff)
			else
				-- Non-retryable error or max retries exceeded
				local errorMsg = "HTTP " .. statusCode
				if statusCode == 429 then
					errorMsg = "Rate limited after " .. MAX_RETRIES .. " retries. Please wait and try again."
				elseif statusCode >= 500 then
					errorMsg = "OpenRouter server error (HTTP " .. statusCode .. "). Please try again later."
				end

				if Constants.DEBUG then
					print(string.format("[Lux DEBUG] API error: %s", errorMsg))
					print(string.format("[Lux DEBUG] Response body: %s", result.Body:sub(1, 500)))
				end

				return { success = false, error = errorMsg }
			end
		end
	end

	-- Check final result after retries
	if err then
		return { success = false, error = lastError or "Request failed after " .. MAX_RETRIES .. " retries" }
	end

	if not result.Success then
		return { success = false, error = "Request failed after " .. MAX_RETRIES .. " retries" }
	end

	-- Parse response
	local success, parsed = pcall(function()
		return HttpService:JSONDecode(result.Body)
	end)

	if not success then
		return { success = false, error = "Failed to parse API response" }
	end

	-- Check for API error in response
	if parsed.error then
		return { success = false, error = parsed.error.message or "Unknown API error" }
	end

	-- Check for valid response
	if not parsed.choices or #parsed.choices == 0 then
		return { success = false, error = "No response from API" }
	end

	-- Extract and track token usage
	if parsed.usage then
		local usage = parsed.usage
		local cost = usage.cost or 0

		tokenUsage.promptTokens = tokenUsage.promptTokens + (usage.prompt_tokens or 0)
		tokenUsage.completionTokens = tokenUsage.completionTokens + (usage.completion_tokens or 0)
		tokenUsage.totalTokens = tokenUsage.totalTokens + (usage.total_tokens or 0)
		tokenUsage.totalCost = tokenUsage.totalCost + cost
		tokenUsage.lastRequestCost = cost
		tokenUsage.apiCalls = tokenUsage.apiCalls + 1

		-- Instant balance update (optimistic)
		if creditBalance and creditBalance.remaining then
			creditBalance.remaining = creditBalance.remaining - cost
			creditBalance.used = creditBalance.used + cost
		end

		if Constants.DEBUG then
			print(string.format("\n💵 [COST] Call #%d: $%.4f | Session total: $%.4f | Tokens: %d in, %d out\n",
				tokenUsage.apiCalls,
				cost,
				tokenUsage.totalCost,
				usage.prompt_tokens or 0,
				usage.completion_tokens or 0
				))
		end
	end

	-- Convert OpenAI response back to internal format
	local choice = parsed.choices[1]
	local internalParts = {}

	if choice.message.content then
		table.insert(internalParts, { text = choice.message.content })
	end

	if choice.message.tool_calls then
		for _, call in ipairs(choice.message.tool_calls) do
			local args = {}
			pcall(function()
				args = HttpService:JSONDecode(call["function"].arguments)
			end)

			table.insert(internalParts, {
				functionCall = {
					name = call["function"].name,
					args = args
				}
			})
		end
	end

	return {
		success = true,
		response = {
			parts = internalParts,
			finishReason = choice.finish_reason
		}
	}
end

-- ============================================================================
-- HISTORY SUMMARIZATION
-- ============================================================================

--[[
	Call API to summarize history
	@param historyToSummarize table - Array of messages to summarize
	@return string|nil - Summary text or nil if failed
]]
function ApiClient.generateSummary(historyToSummarize)
	if Constants.DEBUG then
		print("[Lux DEBUG] Generating summary for " .. #historyToSummarize .. " messages...")
	end

	local key = getApiKey()
	if not key then return nil end

	-- Convert just the text parts for summary
	local textContent = ""
	for _, msg in ipairs(historyToSummarize) do
		local role = msg.role
		local text = ""
		if msg.parts then
			for _, part in ipairs(msg.parts) do
				if part.text then text = text .. part.text end
				if part.functionCall then text = text .. " [Tool Call: " .. part.functionCall.name .. "]" end
				if part.functionResponse then text = text .. " [Tool Result]" end
			end
		end
		textContent = textContent .. string.format("\n%s: %s", role, text)
	end

	local requestBody = {
		model = Constants.SUMMARY_MODEL or Constants.OPENROUTER_MODEL,
		messages = {
			{
				role = "system",
				content = "You are a technical summarizer. Summarize the following conversation logs from a Roblox Studio coding session. Focus strictly on:\n1. Technical decisions made\n2. Current state of files (what was edited/created)\n3. Pending tasks or errors\nDiscard casual chatter. Be concise."
			},
			{
				role = "user",
				content = textContent
			}
		},
		max_tokens = 2000,
		temperature = 0.5
	}

	local success, result = pcall(function()
		return HttpService:RequestAsync({
			Url = Constants.OPENROUTER_ENDPOINT,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["Authorization"] = "Bearer " .. key,
				["HTTP-Referer"] = Constants.OPENROUTER_REFERER,
				["X-Title"] = "Lux"
			},
			Body = HttpService:JSONEncode(requestBody)
		})
	end)

	if success and result.Success then
		local ok, parsed = pcall(HttpService.JSONDecode, HttpService, result.Body)
		if ok and parsed.choices and parsed.choices[1] then
			return parsed.choices[1].message.content
		end
	end

	return nil
end

return ApiClient
