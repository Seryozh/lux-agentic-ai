--[[
    Backend: Handles all HTTP communication with the Luxembourg server.

    Three operations:
    1. sendChat()    — sends user message + project map, gets response
    2. poll()        — checks if the agent needs anything (metadata, scripts)
    3. respond()     — sends back what the agent asked for

    Roblox HTTP uses HttpService. All requests are outbound-only (Roblox limitation).
]]

local HttpService = game:GetService("HttpService")

local Backend = {}

-- Production backend URL
-- For local development, change this to "http://localhost:8000"
-- For custom deployments, update to your deployed backend URL
Backend.BASE_URL = "https://web-production-b781.up.railway.app"

function Backend.sendChat(sessionId, userMessage, projectMap, apiKey)
	local body = HttpService:JSONEncode({
		session_id = sessionId,
		user_message = userMessage,
		project_map = projectMap,
		openrouter_key = apiKey,
	})

	local success, result = pcall(function()
		return HttpService:RequestAsync({
			Url = Backend.BASE_URL .. "/chat",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)

	if not success then
		return nil, "HTTP error: " .. tostring(result)
	end

	if result.StatusCode ~= 200 then
		return nil, "Server error " .. result.StatusCode .. ": " .. result.Body
	end

	return HttpService:JSONDecode(result.Body), nil
end

function Backend.poll(sessionId)
	local success, result = pcall(function()
		return HttpService:RequestAsync({
			Url = Backend.BASE_URL .. "/poll/" .. sessionId,
			Method = "GET",
		})
	end)

	if not success then
		return nil, "Poll error: " .. tostring(result)
	end

	if result.StatusCode == 404 then
		return { pending_requests = {} }, nil  -- no session yet, that's fine
	end

	if result.StatusCode ~= 200 then
		return nil, "Poll error " .. result.StatusCode
	end

	return HttpService:JSONDecode(result.Body), nil
end

function Backend.respond(sessionId, requestId, data)
	local body = HttpService:JSONEncode({
		session_id = sessionId,
		request_id = requestId,
		data = data,
	})

	local success, result = pcall(function()
		return HttpService:RequestAsync({
			Url = Backend.BASE_URL .. "/poll/" .. sessionId .. "/respond",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)

	if not success then
		return false, "Respond error: " .. tostring(result)
	end

	return result.StatusCode == 200, nil
end

return Backend
