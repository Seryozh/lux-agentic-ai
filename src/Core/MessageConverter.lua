--[[
	MessageConverter.lua
	Core module: Message Format Conversion

	Responsibilities:
	- Convert internal conversation format to OpenAI format
	- Sanitize tool responses for JSON encoding
	- Handle function call/response transformations

	This module provides clean conversions between the internal message format
	used by Lux and the OpenAI API format expected by OpenRouter.
]]

local HttpService = game:GetService("HttpService")

local MessageConverter = {}

-- ============================================================================
-- RESPONSE SANITIZATION
-- ============================================================================

--[[
	Sanitize tool response to ensure it's safe for JSON encoding and API submission
	@param response table - The tool response
	@return table - Sanitized response
]]
local function sanitizeToolResponse(response)
	if type(response) ~= "table" then
		return response
	end

	local sanitized = {}

	for key, value in pairs(response) do
		local valueType = type(value)

		if valueType == "string" then
			-- Remove null bytes and truncate very long strings
			local cleaned = value:gsub("\0", "")
			if #cleaned > 10000 then
				cleaned = cleaned:sub(1, 10000) .. "... [truncated]"
			end
			sanitized[key] = cleaned

		elseif valueType == "number" or valueType == "boolean" then
			sanitized[key] = value

		elseif valueType == "table" then
			sanitized[key] = sanitizeToolResponse(value)

		elseif valueType == "nil" then
			sanitized[key] = nil

		else
			-- Userdata, function, thread - convert to string
			sanitized[key] = tostring(value)
		end
	end

	return sanitized
end

--[[
	Public interface for sanitizing tool responses
	@param response table - The tool response
	@return table - Sanitized response
]]
function MessageConverter.sanitizeResponse(response)
	return sanitizeToolResponse(response)
end

-- ============================================================================
-- MESSAGE FORMAT CONVERSION
-- ============================================================================

--[[
	Convert internal conversation format to OpenAI format
	@param contents table - Conversation history in internal format
	@return table - Messages in OpenAI format
]]
function MessageConverter.toOpenAI(contents)
	local messages = {}
	local toolCallIds = {} -- Queue to store IDs for pending tool calls

	-- Convert messages
	for _, msg in ipairs(contents) do
		local role = msg.role
		if role == "model" then role = "assistant" end

		-- Accumulate text content for this message
		local textContent = ""
		local toolCalls = nil

		if msg.parts then
			for _, part in ipairs(msg.parts) do
				if part.text then
					textContent = textContent .. part.text
				elseif part.functionCall then
					if not toolCalls then toolCalls = {} end

					local callId = "call_" .. HttpService:GenerateGUID(false)
					table.insert(toolCallIds, callId)

					table.insert(toolCalls, {
						id = callId,
						type = "function",
						["function"] = {
							name = part.functionCall.name,
							arguments = HttpService:JSONEncode(part.functionCall.args or {})
						}
					})
				end
			end
		end

		-- Add text/tool_calls message
		if textContent ~= "" or toolCalls then
			local message = { role = role }
			if textContent ~= "" then message.content = textContent end
			if toolCalls then message.tool_calls = toolCalls end
			table.insert(messages, message)
		end

		-- Add tool response messages
		if msg.parts then
			for _, part in ipairs(msg.parts) do
				if part.functionResponse then
					local callId = table.remove(toolCallIds, 1) or "call_unknown"

					table.insert(messages, {
						role = "tool",
						tool_call_id = callId,
						name = part.functionResponse.name,
						content = HttpService:JSONEncode(part.functionResponse.response)
					})
				end
			end
		end
	end

	return messages
end

return MessageConverter
