--[[
    UI/UserFeedback.lua
    Interactive user feedback/verification prompt
    Allows AI to ask user to verify visual changes or test functionality
    
    v2.0 - Now uses chat-based verification (renders in chat history instead of input container)
    
    Design principles:
    - Quick to respond (buttons, not just text)
    - Not annoying (rate limited, smart usage)
    - Helpful (provides context about what to check)
    - Always visible (renders in chat flow, not hidden at bottom)
]]

local Constants = require(script.Parent.Parent.Constants)

local UserFeedback = {}

-- Track feedback timing for rate limiting
local lastFeedbackTime = 0
local feedbackCountThisTurn = 0
local toolsSinceLastFeedback = 0

-- Track current verification frame (for cleanup)
local currentVerificationFrame = nil

--[[
    Reset feedback tracking (call at start of new user message)
]]
function UserFeedback.resetTurnTracking()
	feedbackCountThisTurn = 0
	toolsSinceLastFeedback = 0
end

--[[
    Increment tool counter (call after each tool execution)
]]
function UserFeedback.recordToolCall()
	toolsSinceLastFeedback = toolsSinceLastFeedback + 1
end

--[[
    Check if feedback is allowed based on rate limiting
    @param userMessage string - The user's original message (to check for urgency)
    @return boolean, string - Whether allowed, reason if not
]]
function UserFeedback.canRequestFeedback(userMessage)
	if not Constants.USER_FEEDBACK.enabled then
		return false, "User feedback is disabled"
	end

	-- Check max per turn
	if feedbackCountThisTurn >= Constants.USER_FEEDBACK.maxPerConversationTurn then
		return false, "Already requested feedback this turn"
	end

	-- Check cooldown
	local now = tick()
	if (now - lastFeedbackTime) < Constants.USER_FEEDBACK.cooldownSeconds then
		return false, "Cooldown not expired"
	end

	-- Check minimum tools between
	if toolsSinceLastFeedback < Constants.USER_FEEDBACK.minToolsBetween then
		return false, "Not enough tool calls since last feedback"
	end

	-- Check for urgency keywords
	if Constants.USER_FEEDBACK.skipIfUserSaidUrgent and userMessage then
		local lowerMessage = userMessage:lower()
		for _, keyword in ipairs(Constants.USER_FEEDBACK.urgencyKeywords) do
			if lowerMessage:find(keyword, 1, true) then
				return false, "User indicated urgency"
			end
		end
	end

	return true, nil
end

--[[
    Show the feedback prompt as a chat message
    This is the new preferred method - renders in chat history for visibility
    @param state table - State with ui references (must have chatHistory)
    @param request table - Request details {
        question: string,
        context: string,
        verificationType: "visual" | "functional" | "both",
        suggestions: table (optional array of strings)
    }
    @param onResponse function - Callback with response { positive: bool, feedback: string }
    @return Frame|nil - The verification frame, or nil if ChatRenderer not available
]]
function UserFeedback.showInChat(state, request, onResponse)
	-- Update tracking
	lastFeedbackTime = tick()
	feedbackCountThisTurn = feedbackCountThisTurn + 1
	toolsSinceLastFeedback = 0

	-- Get ChatRenderer module
	local ChatRenderer
	local success = pcall(function()
		ChatRenderer = require(script.Parent.ChatRenderer)
	end)

	if not success or not ChatRenderer then
		warn("[UserFeedback] Could not load ChatRenderer, falling back to legacy mode")
		return nil
	end

	-- Clean up any existing verification frame
	if currentVerificationFrame and currentVerificationFrame.Parent then
		currentVerificationFrame:Destroy()
	end

	-- Create verification in chat using ChatRenderer
	currentVerificationFrame = ChatRenderer.addVerificationPrompt(state, request, function(response)
		-- Clear reference when responded
		currentVerificationFrame = nil
		if onResponse then
			onResponse(response)
		end
	end)

	return currentVerificationFrame
end

--[[
    Show the feedback prompt in the input container (legacy mode)
    @deprecated Use showInChat instead - this is kept for backwards compatibility
    @param inputContainer Frame - The input container to transform
    @param request table - Request details
    @param onResponse function - Callback with response
    @return Frame - The feedback prompt frame
]]
function UserFeedback.show(inputContainer, request, onResponse)
	-- Update tracking
	lastFeedbackTime = tick()
	feedbackCountThisTurn = feedbackCountThisTurn + 1
	toolsSinceLastFeedback = 0

	-- Try to get Create module for UI generation
	local Create
	local success = pcall(function()
		Create = require(script.Parent.Create)
	end)

	if not success then
		warn("[UserFeedback] Could not load Create module")
		return nil
	end

	-- Hide existing input elements
	local textInput = inputContainer:FindFirstChild("TextInput")
	local sendButton = inputContainer:FindFirstChild("SendButton")

	if textInput then textInput.Visible = false end
	if sendButton then sendButton.Visible = false end

	-- Calculate height based on content
	local hasSuggestions = request.suggestions and #request.suggestions > 0
	local baseHeight = 120
	if hasSuggestions then
		baseHeight = baseHeight + (#request.suggestions * 18) + 8
	end

	-- Expand container
	local originalHeight = inputContainer.Size.Y.Offset
	inputContainer:SetAttribute("OriginalHeight", originalHeight)
	inputContainer.Size = UDim2.new(1, 0, 0, baseHeight)

	-- Create feedback prompt frame
	local feedbackFrame = Create.new("Frame", {
		Name = "FeedbackPrompt",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Constants.COLORS.messageVerification or Color3.fromRGB(40, 50, 60),
		Parent = inputContainer
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = feedbackFrame
	})

	Create.new("UIStroke", {
		Color = Constants.COLORS.accentPrimary,
		Thickness = 1,
		Transparency = 0.5,
		Parent = feedbackFrame
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = feedbackFrame
	})

	-- Header with icon
	local verificationType = request.verificationType or "visual"
	local headerIcon = "??"
	local headerText = "Verification"

	if verificationType == "functional" then
		headerIcon = "??"
		headerText = "Testing"
	elseif verificationType == "both" then
		headerIcon = "??"
		headerText = "Verification & Testing"
	end

	Create.new("TextLabel", {
		Name = "Header",
		Text = headerIcon .. " " .. headerText,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.accentPrimary,
		Font = Constants.UI.FONT_HEADER,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = feedbackFrame
	})

	-- Context text (what was done)
	local contextY = 16
	if request.context and request.context ~= "" then
		Create.new("TextLabel", {
			Name = "Context",
			Text = request.context,
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 0, contextY),
			BackgroundTransparency = 1,
			TextColor3 = Constants.COLORS.textMuted,
			Font = Constants.UI.FONT_NORMAL,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = feedbackFrame
		})
		contextY = contextY + 16
	end

	-- Main question
	Create.new("TextLabel", {
		Name = "Question",
		Text = "\"" .. (request.question or "Does this look correct?") .. "\"",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, contextY),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = feedbackFrame
	})

	-- Suggestions (compact)
	local suggestionsEndY = contextY + 22
	if hasSuggestions then
		for i, suggestion in ipairs(request.suggestions) do
			Create.new("TextLabel", {
				Name = "Suggestion_" .. i,
				Text = "• " .. suggestion,
				Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.new(0, 0, 0, suggestionsEndY + ((i-1) * 16)),
				BackgroundTransparency = 1,
				TextColor3 = Constants.COLORS.textSecondary,
				Font = Constants.UI.FONT_NORMAL,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = feedbackFrame
			})
		end
		suggestionsEndY = suggestionsEndY + (#request.suggestions * 16) + 4
	end

	-- Helper for hover effect
	local function addHoverEffect(button, normalColor)
		local hoverColor = Color3.new(
			math.min(1, normalColor.R * 1.2),
			math.min(1, normalColor.G * 1.2),
			math.min(1, normalColor.B * 1.2)
		)
		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = hoverColor
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = normalColor
		end)
	end

	-- Button row
	local buttonRow = Create.new("Frame", {
		Name = "ButtonRow",
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 1, -32),
		BackgroundTransparency = 1,
		Parent = feedbackFrame
	})

	-- "Looks Good" button (positive)
	local positiveBtn = Create.new("TextButton", {
		Name = "PositiveBtn",
		Text = "? Good",
		Size = UDim2.new(0.32, -2, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Constants.COLORS.accentSuccess,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Constants.UI.FONT_HEADER,
		TextSize = 11,
		Parent = buttonRow
	})
	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = positiveBtn })
	addHoverEffect(positiveBtn, Constants.COLORS.accentSuccess)

	positiveBtn.MouseButton1Click:Connect(function()
		if onResponse then
			onResponse({ positive = true, feedback = "Looks good" })
		end
	end)

	-- "Problem" button
	local negativeBtn = Create.new("TextButton", {
		Name = "NegativeBtn",
		Text = "? Issue",
		Size = UDim2.new(0.32, -2, 1, 0),
		Position = UDim2.new(0.34, 0, 0, 0),
		BackgroundColor3 = Constants.COLORS.accentError,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Constants.UI.FONT_HEADER,
		TextSize = 11,
		Parent = buttonRow
	})
	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = negativeBtn })
	addHoverEffect(negativeBtn, Constants.COLORS.accentError)

	negativeBtn.MouseButton1Click:Connect(function()
		if onResponse then
			onResponse({ positive = false, feedback = "Something is wrong" })
		end
	end)

	-- "Describe" button
	local describeBtn = Create.new("TextButton", {
		Name = "DescribeBtn",
		Text = "?? More",
		Size = UDim2.new(0.32, -2, 1, 0),
		Position = UDim2.new(0.68, 0, 0, 0),
		BackgroundColor3 = Constants.COLORS.accentPrimary,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Constants.UI.FONT_HEADER,
		TextSize = 11,
		Parent = buttonRow
	})
	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = describeBtn })
	addHoverEffect(describeBtn, Constants.COLORS.accentPrimary)

	describeBtn.MouseButton1Click:Connect(function()
		if onResponse then
			onResponse({ positive = nil, feedback = "Need to provide more details" })
		end
	end)

	return feedbackFrame
end

--[[
    Hide feedback prompt and restore normal input
    @param inputContainer Frame - The input container
]]
function UserFeedback.hide(inputContainer)
	-- Restore size
	local originalHeight = inputContainer:GetAttribute("OriginalHeight")
	if originalHeight then
		inputContainer.Size = UDim2.new(1, 0, 0, originalHeight)
	end

	-- Remove feedback prompt
	local feedbackPrompt = inputContainer:FindFirstChild("FeedbackPrompt")
	if feedbackPrompt then
		feedbackPrompt:Destroy()
	end

	-- Restore input elements
	local textInput = inputContainer:FindFirstChild("TextInput")
	local sendButton = inputContainer:FindFirstChild("SendButton")

	if textInput then textInput.Visible = true end
	if sendButton then sendButton.Visible = true end
end

--[[
    Remove the current chat-based verification prompt
]]
function UserFeedback.hideCurrentVerification()
	if currentVerificationFrame and currentVerificationFrame.Parent then
		currentVerificationFrame:Destroy()
		currentVerificationFrame = nil
	end
end

--[[
    Get current feedback statistics (for debugging)
    @return table - { lastTime, countThisTurn, toolsSinceLast }
]]
function UserFeedback.getStats()
	return {
		lastTime = lastFeedbackTime,
		countThisTurn = feedbackCountThisTurn,
		toolsSinceLast = toolsSinceLastFeedback
	}
end

return UserFeedback
