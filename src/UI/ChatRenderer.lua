--[[
    UI/ChatRenderer.lua
    Chat message rendering and management
    Enhanced with timestamps, better styling, and improved UX
    v1.4.0 - Collapsible containers (planning, tool groups) with expand/collapse
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Create)
local MarkdownParser = require(script.Parent.Parent.Shared.MarkdownParser)

local ChatRenderer = {}

-- Track if we've hidden the status panel
local statusPanelHidden = false

-- Track tool activity for session summary
local toolActivityLog = {}

-- Track grouped tool activities (for batching multiple approvals)
local pendingToolGroup = nil
local toolGroupFrame = nil
local toolGroupList = {}

-- Track current system message group (for auto-grouping consecutive system messages)
local currentSystemGroup = nil
local systemGroupItems = {}
local systemGroupState = nil

--[[
    Hide the status panel to give more room for chat
    @param state table - State table with ui references
]]
function ChatRenderer.hideStatusPanel(state)
	if statusPanelHidden then return end
	if not state or not state.ui then return end

	local statusPanel = state.ui.statusPanel
	local buttonContainer = state.ui.mainFrame and state.ui.mainFrame:FindFirstChild("ButtonContainer")

	if statusPanel then
		statusPanel.Visible = false
		statusPanel.Size = UDim2.new(1, 0, 0, 0) -- Collapse size
	end

	if buttonContainer then
		buttonContainer.Visible = false
		buttonContainer.Size = UDim2.new(1, 0, 0, 0) -- Collapse size
	end

	-- Expand chat container to use the freed space
	if state.ui.chatContainer then
		state.ui.chatContainer.Size = UDim2.new(1, 0, 1, -100) -- More room for chat
	end

	statusPanelHidden = true

	if Constants.DEBUG then
		print("[Lux DEBUG] Status panel hidden to maximize chat space")
	end
end

--[[
    Show the status panel (when chat is cleared)
    @param state table - State table with ui references
]]
function ChatRenderer.showStatusPanel(state)
	if not statusPanelHidden then return end
	if not state or not state.ui then return end

	local statusPanel = state.ui.statusPanel
	local buttonContainer = state.ui.mainFrame and state.ui.mainFrame:FindFirstChild("ButtonContainer")

	if statusPanel then
		statusPanel.Visible = true
		statusPanel.Size = UDim2.new(1, 0, 0, 120)
	end

	if buttonContainer then
		buttonContainer.Visible = true
		buttonContainer.Size = UDim2.new(1, 0, 0, 30)
	end

	-- Restore chat container size
	if state.ui.chatContainer then
		state.ui.chatContainer.Size = UDim2.new(1, 0, 1, -200)
	end

	statusPanelHidden = false
end

--[[
    Reset the status panel state (for conversation reset)
]]
function ChatRenderer.resetStatusPanelState()
	statusPanelHidden = false
end

--[[
    Format timestamp for display
    @param timestamp number - Unix timestamp from tick()
    @return string - Formatted time (e.g., "3:45 PM")
]]
local function formatTimestamp(timestamp)
	-- Convert tick() to a readable time
	-- tick() returns seconds since some epoch, we need relative time
	local now = tick()
	local diff = now - timestamp

	if diff < 60 then
		return "just now"
	elseif diff < 3600 then
		local mins = math.floor(diff / 60)
		return string.format("%dm ago", mins)
	elseif diff < 86400 then
		local hours = math.floor(diff / 3600)
		return string.format("%dh ago", hours)
	else
		local days = math.floor(diff / 86400)
		return string.format("%dd ago", days)
	end
end

--[[
    Add hover effect to a button
    @param button TextButton
    @param normalColor Color3
]]
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

--[[
    Add a chat message to the UI
    @param state table - State table with ui and chatMessages
    @param role string - "user" or "assistant" or "system"
    @param text string - Message text
    @return number - Message index
]]
function ChatRenderer.addMessage(state, role, text)
	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Adding chat message: %s (%d chars)", role, #text))
	end

	-- Finalize any active system group when a text message is added
	-- This ensures tool operations are separated by conversation messages
	if (role == "assistant" or role == "user") and currentSystemGroup then
		ChatRenderer.finalizeCollapsibleSystemGroup()
	end

	-- Hide status panel when first message is added to maximize chat space
	if #state.chatMessages == 0 then
		ChatRenderer.hideStatusPanel(state)
	end

	local timestamp = tick()
	table.insert(state.chatMessages, {
		role = role,
		text = text,
		timestamp = timestamp
	})

	-- Determine colors based on role
	local bgColor = Constants.COLORS.messageAssistant
	local roleLabel = "Lux AI"
	local roleColor = Constants.COLORS.textSecondary

	if role == "user" then
		bgColor = Constants.COLORS.messageUser
		roleLabel = "You"
		roleColor = Color3.fromRGB(150, 170, 255)
	elseif role == "system" then
		bgColor = Constants.COLORS.messageSystem
		roleLabel = "System"
		roleColor = Constants.COLORS.accentWarning
	end

	-- Create message bubble
	local messageFrame = Create.new("Frame", {
		Name = "Message_" .. #state.chatMessages,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = bgColor,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = #state.chatMessages,
		Parent = state.ui.chatHistory
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = messageFrame
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = messageFrame
	})

	Create.new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = messageFrame
	})

	-- Header row (Role + Timestamp)
	local headerRow = Create.new("Frame", {
		Name = "HeaderRow",
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = messageFrame
	})

	-- Role label
	Create.new("TextLabel", {
		Name = "Role",
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = roleLabel,
		TextColor3 = roleColor,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = headerRow
	})

	-- Timestamp label
	local timestampLabel = Create.new("TextLabel", {
		Name = "Timestamp",
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = formatTimestamp(timestamp),
		TextColor3 = Constants.COLORS.textMuted,
		Font = Enum.Font.Gotham,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = headerRow
	})

	-- Store timestamp for updating later
	messageFrame:SetAttribute("MessageTimestamp", timestamp)

	-- Message text - Using TextLabel for consistent RichText rendering
	-- Note: AutomaticSize can be buggy with RichText, so we manually calculate height
	local parsedText = MarkdownParser.parse(text)

	local textLabel = Create.new("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, -4, 0, 0),  -- Start with auto height
		BackgroundTransparency = 1,
		Text = parsedText,
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = Constants.UI.FONT_SIZE_NORMAL,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		RichText = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = messageFrame
	})

	-- Workaround for AutomaticSize issues with RichText/TextWrapped
	-- Manually calculate and set height based on TextBounds
	task.defer(function()
		if textLabel and textLabel.Parent then
			task.wait(0.02) -- Wait for layout

			-- Get the actual text bounds
			local absoluteWidth = textLabel.AbsoluteSize.X
			if absoluteWidth > 0 then
				-- Use TextService to calculate proper height
				local TextService = game:GetService("TextService")
				local success, textSize = pcall(function()
					return TextService:GetTextSize(
						text, -- Use original text, not parsed (more accurate estimate)
						Constants.UI.FONT_SIZE_NORMAL,
						Constants.UI.FONT_NORMAL,
						Vector2.new(absoluteWidth, math.huge)
					)
				end)

				if success and textSize then
					-- Add padding and set minimum height
					local calculatedHeight = math.max(20, textSize.Y + 4)
					textLabel.Size = UDim2.new(1, -4, 0, calculatedHeight)
				end
			end
		end
	end)

	-- Auto-scroll to bottom
	task.spawn(function()
		task.wait(0.05) -- Wait for layout to recalculate
		local canvasSize = state.ui.chatHistory.AbsoluteCanvasSize.Y
		local frameSize = state.ui.chatHistory.AbsoluteSize.Y
		state.ui.chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
	end)

	return #state.chatMessages
end

--[[
    Update an existing message's text
    @param state table - State table with ui and chatMessages
    @param messageIndex number - Index of message to update
    @param newText string - New text content
]]
function ChatRenderer.updateMessage(state, messageIndex, newText)
	for _, child in ipairs(state.ui.chatHistory:GetChildren()) do
		if child.Name == "Message_" .. messageIndex then
			local textLabel = child:FindFirstChild("Text")
			if textLabel then
				textLabel.Text = MarkdownParser.parse(newText)

				-- Update in state
				if state.chatMessages[messageIndex] then
					state.chatMessages[messageIndex].text = newText
				end

				-- Auto-scroll after update
				task.spawn(function()
					task.wait(0.05)
					local canvasSize = state.ui.chatHistory.AbsoluteCanvasSize.Y
					local frameSize = state.ui.chatHistory.AbsoluteSize.Y
					state.ui.chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
				end)
			end
			break
		end
	end
end

--[[
    Clear all chat messages
    @param state table - State table with ui and chatMessages
    @param aiClient table - OpenRouterClient module to reset conversation
]]
function ChatRenderer.clearHistory(state, aiClient)
	state.chatMessages = {}
	for _, child in ipairs(state.ui.chatHistory:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("^Message_") then
			child:Destroy()
		end
	end
	aiClient.resetConversation()

	-- Show status panel again when chat is cleared
	ChatRenderer.showStatusPanel(state)
	ChatRenderer.resetStatusPanelState()

	if Constants.DEBUG then
		print("[Lux DEBUG] Chat history cleared")
	end
end

--[[
    Show thinking indicator with animated dots and streaming thoughts
    @param state table - State table
]]
local thinkingContainer = nil
local thinkingMessageIndex = nil
local thoughtBlocks = {}
local thinkingState = nil  -- Store state reference for scrolling
local thinkingAnimation = nil -- Store animation connection

function ChatRenderer.showThinking(state)
	if thinkingContainer then return end
	if not state or not state.ui then return end

	-- Store state reference for auto-scrolling
	thinkingState = state

	-- Create a message-like container for thoughts
	thinkingMessageIndex = #state.chatMessages + 1

	thinkingContainer = Create.new("Frame", {
		Name = "ThinkingContainer",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Constants.COLORS.messageAssistant,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = thinkingMessageIndex,
		Parent = state.ui.chatHistory
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = thinkingContainer
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = thinkingContainer
	})

	Create.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = thinkingContainer
	})

	-- Header row
	local headerRow = Create.new("Frame", {
		Name = "HeaderRow",
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = thinkingContainer
	})

	-- Role label
	Create.new("TextLabel", {
		Name = "Role",
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "Lux AI",
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = headerRow
	})

	-- Animated thinking indicator
	local thinkingLabel = Create.new("TextLabel", {
		Name = "ThinkingIndicator",
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = "thinking",
		TextColor3 = Constants.COLORS.accentPrimary,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = headerRow
	})

	-- Animate the thinking dots
	local dots = {"", ".", "..", "..."}
	local dotIndex = 1
	thinkingAnimation = task.spawn(function()
		while thinkingContainer and thinkingContainer.Parent do
			thinkingLabel.Text = "thinking" .. dots[dotIndex]
			dotIndex = (dotIndex % 4) + 1
			task.wait(0.4)
		end
	end)

	-- Scroll to show it
	task.spawn(function()
		task.wait(0.05)
		if state and state.ui and state.ui.chatHistory then
			state.ui.chatHistory.CanvasPosition = Vector2.new(0, state.ui.chatHistory.AbsoluteCanvasSize.Y)
		end
	end)
end

function ChatRenderer.hideThinking()
	if thinkingContainer then
		thinkingContainer:Destroy()
		thinkingContainer = nil
	end
	thoughtBlocks = {}
	thinkingMessageIndex = nil
	thinkingState = nil
	thinkingAnimation = nil
end

--[[
    Persist the thinking container as a COLLAPSIBLE "Planning" message in chat
    Now creates a collapsed-by-default container with expand/collapse toggle
    Call this BEFORE hideThinking() when you want to keep the thoughts visible
    @param state table - State table with ui references
    @return boolean - True if successfully persisted
]]
function ChatRenderer.persistThinking(state)
	if not thinkingContainer then 
		return false 
	end

	if not state or not state.ui or not state.ui.chatHistory then
		return false
	end

	-- Collect all thought text from the blocks
	local thoughtTexts = {}
	for _, block in ipairs(thoughtBlocks) do
		local textLabel = block:FindFirstChild("ThoughtText")
		if textLabel then
			-- Extract the text (includes emoji prefix)
			table.insert(thoughtTexts, textLabel.Text)
		end
	end

	-- If no thoughts were captured, just destroy and return
	if #thoughtTexts == 0 then
		if thinkingContainer then
			thinkingContainer:Destroy()
		end
		thinkingContainer = nil
		thoughtBlocks = {}
		thinkingMessageIndex = nil
		thinkingState = nil
		thinkingAnimation = nil
		return false
	end

	-- Destroy the old thinking container - we'll create a new collapsible one
	local oldLayoutOrder = thinkingContainer.LayoutOrder
	thinkingContainer:Destroy()
	thinkingContainer = nil
	thoughtBlocks = {}
	thinkingMessageIndex = nil
	thinkingState = nil
	thinkingAnimation = nil

	-- Create preview text from first thought
	local previewText = thoughtTexts[1]:gsub("^[" .. Constants.ICONS.ARROW_RIGHT .. Constants.ICONS.READ .. Constants.ICONS.SUCCESS .. Constants.ICONS.ERROR .. "]%s*", ""):sub(1, 50)
	if #previewText >= 50 then previewText = previewText .. Constants.ICONS.THINKING end

	-- Create the new collapsible container (collapsed by default)
	local container = ChatRenderer.addCollapsiblePlanning(state, thoughtTexts, previewText)

	if container then
		-- Set the correct layout order
		container.LayoutOrder = oldLayoutOrder

		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] Persisted %d thoughts as COLLAPSIBLE planning message", #thoughtTexts))
		end

		return true
	end

	return false
end

--[[
    Add a thought block to the thinking indicator
    @param text string - Thought text
    @param type string - "thinking" | "tool" | "result"
]]
function ChatRenderer.addThought(text, thoughtType)
	if not thinkingContainer then return end
	if not thinkingState then return end  -- Safety check

	thoughtType = thoughtType or "thinking"

	-- Choose color based on type
	local bgColor = Constants.COLORS.backgroundLight
	local textColor = Constants.COLORS.textPrimary
	local prefixIcon = Constants.ICONS.ARROW_RIGHT

	if thoughtType == "tool" then
		bgColor = Color3.fromRGB(50, 60, 80)
		textColor = Color3.fromRGB(150, 180, 255)
		prefixIcon = Constants.ICONS.READ
	elseif thoughtType == "result" then
		bgColor = Color3.fromRGB(40, 60, 50)
		textColor = Color3.fromRGB(150, 255, 180)
		prefixIcon = Constants.ICONS.SUCCESS
	elseif thoughtType == "error" then
		bgColor = Color3.fromRGB(70, 40, 40)
		textColor = Color3.fromRGB(255, 180, 180)
		prefixIcon = Constants.ICONS.ERROR
	end

	local thoughtBlock = Create.new("Frame", {
		Name = "ThoughtBlock_" .. #thoughtBlocks,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = bgColor,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = #thoughtBlocks + 2, -- +2 because header row is 1
		Parent = thinkingContainer
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 6),
		Parent = thoughtBlock
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = thoughtBlock
	})

	-- Use TextLabel instead of TextBox for consistent RichText rendering
	Create.new("TextLabel", {
		Name = "ThoughtText",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = prefixIcon .. " " .. MarkdownParser.parse(text),
		TextColor3 = textColor,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = Constants.UI.FONT_SIZE_SMALL,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = thoughtBlock
	})

	table.insert(thoughtBlocks, thoughtBlock)

	-- Auto-scroll to show new thought
	if thinkingState and thinkingState.ui and thinkingState.ui.chatHistory then
		local capturedState = thinkingState
		task.spawn(function()
			task.wait(0.05)
			if capturedState and capturedState.ui then
				local chatHistory = capturedState.ui.chatHistory
				if chatHistory then
					local canvasSize = chatHistory.AbsoluteCanvasSize.Y
					local frameSize = chatHistory.AbsoluteSize.Y
					chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
				end
			end
		end)
	end
end

function ChatRenderer.updateThinkingStatus(iteration, toolName)
	if not thinkingContainer then return end

	if toolName then
		ChatRenderer.addThought(string.format("**Step %d**: Using tool `%s`", iteration, toolName), "tool")
	else
		ChatRenderer.addThought(string.format("Step %d: Analyzing...", iteration), "thinking")
	end
end

--[[
    Add a compact tool activity message to chat (inline, not in thinking panel)
    This shows tool execution in the main chat flow for better visibility
    @param state table - State table with ui and chatMessages
    @param toolIntent string - What the tool is about to do
    @param toolResult string - Result of the tool execution (nil if pending)
    @param status string - "pending" | "success" | "error"
    @return number - Message index
]]
function ChatRenderer.addToolActivity(state, toolIntent, toolResult, status)
	if not state or not state.ui then return end

	status = status or "pending"

	-- Track activity for summary
	table.insert(toolActivityLog, {
		intent = toolIntent,
		result = toolResult,
		status = status,
		timestamp = tick()
	})

	-- Create compact tool message
	local timestamp = tick()
	local layoutOrder = #state.chatMessages + 1

	-- Choose styling based on status
	local bgColor = Color3.fromRGB(40, 45, 55) -- Dark blue-gray for tools
	local borderColor = Constants.COLORS.accentPrimary
	local statusIcon = Constants.ICONS.PENDING

	if status == "success" then
		bgColor = Color3.fromRGB(35, 50, 40) -- Dark green tint
		borderColor = Constants.COLORS.accentSuccess
		statusIcon = Constants.ICONS.SUCCESS
	elseif status == "error" then
		bgColor = Color3.fromRGB(55, 35, 35) -- Dark red tint
		borderColor = Constants.COLORS.accentError
		statusIcon = Constants.ICONS.ERROR
	end

	-- Combine intent and result if both present
	local displayText = toolIntent
	if toolResult and toolResult ~= "" then
		displayText = displayText .. "\n" .. statusIcon .. " " .. toolResult
	elseif status == "pending" then
		displayText = Constants.ICONS.PENDING .. " " .. displayText
	end

	-- Create the tool activity frame (more compact than regular messages)
	local activityFrame = Create.new("Frame", {
		Name = "ToolActivity_" .. layoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = bgColor,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = layoutOrder,
		Parent = state.ui.chatHistory
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 6),
		Parent = activityFrame
	})

	Create.new("UIStroke", {
		Color = borderColor,
		Thickness = 1,
		Transparency = 0.5,
		Parent = activityFrame
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = activityFrame
	})

	-- Activity text (smaller, more compact)
	Create.new("TextLabel", {
		Name = "ActivityText",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = MarkdownParser.parse(displayText),
		TextColor3 = Color3.fromRGB(180, 190, 210),
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 12, -- Slightly smaller than regular messages
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = activityFrame
	})

	-- Auto-scroll
	task.spawn(function()
		task.wait(0.05)
		if state.ui.chatHistory then
			local canvasSize = state.ui.chatHistory.AbsoluteCanvasSize.Y
			local frameSize = state.ui.chatHistory.AbsoluteSize.Y
			state.ui.chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
		end
	end)

	return layoutOrder
end

--[[
    Add a completion summary message showing what was accomplished
    @param state table - State table with ui and chatMessages
    @param summary table - { totalTools: number, successful: number, failed: number, items: table }
]]
function ChatRenderer.addCompletionSummary(state, summary)
	if not state or not state.ui then return end
	if not summary or summary.totalTools == 0 then return end

	-- Build summary text
	local lines = {}
	table.insert(lines, "**" .. Constants.ICONS.SUCCESS .. " Task Complete**")

	if summary.items and #summary.items > 0 then
		table.insert(lines, "")
		for _, item in ipairs(summary.items) do
			local icon = item.success and Constants.ICONS.SUCCESS or Constants.ICONS.FAIL
			table.insert(lines, string.format("  %s %s", icon, item.description))
		end
	end

	-- Stats line
	if summary.successful > 0 or summary.failed > 0 then
		table.insert(lines, "")
		local statsText = string.format("*%d operations completed", summary.successful)
		if summary.failed > 0 then
			statsText = statsText .. string.format(", %d failed", summary.failed)
		end
		statsText = statsText .. "*"
		table.insert(lines, statsText)
	end

	local summaryText = table.concat(lines, "\n")

	-- Add as a special system message with success styling
	local timestamp = tick()
	local layoutOrder = #state.chatMessages + 1

	table.insert(state.chatMessages, {
		role = "system",
		text = summaryText,
		timestamp = timestamp,
		isSummary = true
	})

	local summaryFrame = Create.new("Frame", {
		Name = "Summary_" .. layoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(35, 55, 45), -- Success green tint
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = layoutOrder,
		Parent = state.ui.chatHistory
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = summaryFrame
	})

	Create.new("UIStroke", {
		Color = Constants.COLORS.accentSuccess,
		Thickness = 1,
		Transparency = 0.3,
		Parent = summaryFrame
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = summaryFrame
	})

	Create.new("TextLabel", {
		Name = "SummaryText",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = MarkdownParser.parse(summaryText),
		TextColor3 = Color3.fromRGB(180, 230, 200),
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = summaryFrame
	})

	-- Auto-scroll
	task.spawn(function()
		task.wait(0.05)
		if state.ui.chatHistory then
			local canvasSize = state.ui.chatHistory.AbsoluteCanvasSize.Y
			local frameSize = state.ui.chatHistory.AbsoluteSize.Y
			state.ui.chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
		end
	end)

	-- Clear activity log for next task
	toolActivityLog = {}
end

--[[
    Get the current tool activity log
    @return table - Array of tool activities
]]
function ChatRenderer.getToolActivityLog()
	return toolActivityLog
end

--[[
    Clear the tool activity log (call when starting new task)
]]
function ChatRenderer.clearToolActivityLog()
	toolActivityLog = {}
end

--[[
    Start a grouped tool activity container
    Groups multiple tool approvals into a single compact UI element
    @param state table - State table with ui references
    @param groupTitle string - Title for the group (e.g., "Executing 4 operations")
]]
function ChatRenderer.startToolGroup(state, groupTitle)
	if not state or not state.ui then return end

	-- If there's already a group, finalize it
	if toolGroupFrame then
		ChatRenderer.finalizeToolGroup(state)
	end

	local layoutOrder = #state.chatMessages + 1000 -- High order to stay at bottom

	toolGroupFrame = Create.new("Frame", {
		Name = "ToolGroup_" .. tick(),
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Constants.COLORS.toolActivityBg,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = layoutOrder,
		Parent = state.ui.chatHistory
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 6),
		Parent = toolGroupFrame
	})

	Create.new("UIStroke", {
		Color = Constants.COLORS.toolSuccessBorder,
		Thickness = 1,
		Transparency = 0.6,
		Parent = toolGroupFrame
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = toolGroupFrame
	})

	Create.new("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toolGroupFrame
	})

	-- Header row
	Create.new("TextLabel", {
		Name = "GroupHeader",
		Text = Constants.ICONS.READ .. " " .. (groupTitle or "Tool Execution"),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
		Parent = toolGroupFrame
	})

	toolGroupList = {}
	pendingToolGroup = state
end

--[[
    Add an item to the current tool group
    @param text string - Description of the tool action
    @param status string - "pending" | "success" | "error"
]]
function ChatRenderer.addToolGroupItem(text, status)
	if not toolGroupFrame then return end

	status = status or "success"

	local icon = Constants.ICONS.SUCCESS
	local textColor = Color3.fromRGB(140, 200, 160) -- Soft green

	if status == "pending" then
		icon = Constants.ICONS.PENDING
		textColor = Color3.fromRGB(160, 180, 220) -- Soft blue
	elseif status == "error" then
		icon = Constants.ICONS.FAIL
		textColor = Color3.fromRGB(220, 140, 140) -- Soft red
	end

	local itemLabel = Create.new("TextLabel", {
		Name = "Item_" .. #toolGroupList,
		Text = icon .. " " .. text,
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		TextColor3 = textColor,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = #toolGroupList + 1,
		Parent = toolGroupFrame
	})

	table.insert(toolGroupList, {
		label = itemLabel,
		text = text,
		status = status
	})

	-- Auto-scroll
	if pendingToolGroup and pendingToolGroup.ui and pendingToolGroup.ui.chatHistory then
		task.spawn(function()
			task.wait(0.03)
			local chatHistory = pendingToolGroup.ui.chatHistory
			local canvasSize = chatHistory.AbsoluteCanvasSize.Y
			local frameSize = chatHistory.AbsoluteSize.Y
			chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
		end)
	end
end

--[[
    Update the status of a tool group item
    @param index number - Index of the item (1-based)
    @param status string - New status ("success" | "error")
]]
function ChatRenderer.updateToolGroupItem(index, status)
	if not toolGroupList or not toolGroupList[index] then return end

	local item = toolGroupList[index]
	local icon = Constants.ICONS.SUCCESS
	local textColor = Color3.fromRGB(140, 200, 160)

	if status == "error" then
		icon = Constants.ICONS.FAIL
		textColor = Color3.fromRGB(220, 140, 140)
	end

	item.label.Text = icon .. " " .. item.text
	item.label.TextColor3 = textColor
	item.status = status
end

--[[
    Finalize the tool group (stop adding items, fix layout order)
    @param state table - State table with ui references
]]
function ChatRenderer.finalizeToolGroup(state)
	if not toolGroupFrame then return end

	-- Update layout order to be in sequence
	local newOrder = #state.chatMessages + 1
	toolGroupFrame.LayoutOrder = newOrder

	-- Update header to show completion
	local header = toolGroupFrame:FindFirstChild("GroupHeader")
	if header then
		local successCount = 0
		local errorCount = 0
		for _, item in ipairs(toolGroupList) do
			if item.status == "success" then
				successCount = successCount + 1
			elseif item.status == "error" then
				errorCount = errorCount + 1
			end
		end

		local statusText = string.format("%d completed", successCount)
		if errorCount > 0 then
			statusText = statusText .. string.format(", %d failed", errorCount)
		end
		header.Text = Constants.ICONS.SUCCESS .. " " .. statusText
	end

	-- Clear references
	toolGroupFrame = nil
	toolGroupList = {}
	pendingToolGroup = nil
end

--[[
    Add a compact system message (single line, minimal styling)
    Used for tool approvals to reduce visual clutter
    @param state table - State table with ui references
    @param text string - Message text
    @param icon string - Icon prefix (default "?")
    @return Frame - The created message frame
]]
function ChatRenderer.addCompactSystemMessage(state, text, icon)
	if not state or not state.ui then return end

	icon = icon or Constants.ICONS.SUCCESS
	local layoutOrder = #state.chatMessages + 1

	local msgFrame = Create.new("Frame", {
		Name = "CompactSystem_" .. layoutOrder,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = Constants.COLORS.messageSystem,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
		Parent = state.ui.chatHistory
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = msgFrame
	})

	Create.new("TextLabel", {
		Name = "Text",
		Text = icon .. " " .. text,
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(160, 190, 170), -- Soft green-gray
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = msgFrame
	})

	-- Auto-scroll
	task.spawn(function()
		task.wait(0.03)
		if state.ui.chatHistory then
			local canvasSize = state.ui.chatHistory.AbsoluteCanvasSize.Y
			local frameSize = state.ui.chatHistory.AbsoluteSize.Y
			state.ui.chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
		end
	end)

	return msgFrame
end

--[[
    Add verification prompt as a chat message (instead of in input container)
    This ensures the verification is visible and scrolls with chat
    @param state table - State table with ui references
    @param request table - { question: string, context: string, suggestions: table }
    @param onResponse function - Callback with { positive: bool, feedback: string }
    @return Frame - The verification message frame
]]
function ChatRenderer.addVerificationPrompt(state, request, onResponse)
	if not state or not state.ui then return end

	local layoutOrder = #state.chatMessages + 1

	-- Create verification frame styled as a chat message
	local verifyFrame = Create.new("Frame", {
		Name = "Verification_" .. layoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Constants.COLORS.messageVerification,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = layoutOrder,
		Parent = state.ui.chatHistory
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = verifyFrame
	})

	Create.new("UIStroke", {
		Color = Constants.COLORS.accentPrimary,
		Thickness = 1,
		Transparency = 0.5,
		Parent = verifyFrame
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = verifyFrame
	})

	Create.new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = verifyFrame
	})

	-- Header
	local verificationType = request.verificationType or "visual"
	local headerIcon = Constants.ICONS.INFO
	local headerText = "Verification"

	if verificationType == "functional" then
		headerIcon = Constants.ICONS.READ
		headerText = "Testing"
	elseif verificationType == "both" then
		headerIcon = Constants.ICONS.INFO .. Constants.ICONS.READ
		headerText = "Verification & Testing"
	end

	Create.new("TextLabel", {
		Name = "Header",
		Text = headerIcon .. " " .. headerText,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.accentPrimary,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = verifyFrame
	})

	-- Context (what was done)
	if request.context and request.context ~= "" then
		Create.new("TextLabel", {
			Name = "Context",
			Text = request.context,
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			TextColor3 = Constants.COLORS.textMuted,
			Font = Constants.UI.FONT_NORMAL,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = verifyFrame
		})
	end

	-- Question
	Create.new("TextLabel", {
		Name = "Question",
		Text = "\"" .. (request.question or "Does this look correct?") .. "\"",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = verifyFrame
	})

	-- Suggestions checklist
	if request.suggestions and #request.suggestions > 0 then
		local suggestionsFrame = Create.new("Frame", {
			Name = "Suggestions",
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundColor3 = Color3.fromRGB(35, 42, 50),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 4,
			Parent = verifyFrame
		})

		Create.new("UICorner", {
			CornerRadius = UDim.new(0, 4),
			Parent = suggestionsFrame
		})

		Create.new("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			Parent = suggestionsFrame
		})

		Create.new("UIListLayout", {
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = suggestionsFrame
		})

		for i, suggestion in ipairs(request.suggestions) do
			Create.new("TextLabel", {
				Name = "Suggestion_" .. i,
				Text = "- " .. suggestion,
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				TextColor3 = Constants.COLORS.textSecondary,
				Font = Constants.UI.FONT_NORMAL,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = i,
				Parent = suggestionsFrame
			})
		end
	end

	-- Button row
	local buttonRow = Create.new("Frame", {
		Name = "ButtonRow",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = verifyFrame
	})

	Create.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttonRow
	})

	-- Helper for button creation
	local function createButton(name, text, color, order)
		local btn = Create.new("TextButton", {
			Name = name,
			Text = text,
			Size = UDim2.new(0, 90, 1, 0),
			BackgroundColor3 = color,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			LayoutOrder = order,
			Parent = buttonRow
		})
		Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = btn })
		addHoverEffect(btn, color)
		return btn
	end

	-- "Looks Good" button
	local positiveBtn = createButton("PositiveBtn", Constants.ICONS.SUCCESS .. " Looks Good", Constants.COLORS.accentSuccess, 1)
	positiveBtn.MouseButton1Click:Connect(function()
		-- Disable buttons
		buttonRow.Visible = false
		-- Add response indicator
		Create.new("TextLabel", {
			Name = "Response",
			Text = Constants.ICONS.SUCCESS .. " Confirmed as working",
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			TextColor3 = Constants.COLORS.accentSuccess,
			Font = Constants.UI.FONT_NORMAL,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 6,
			Parent = verifyFrame
		})
		if onResponse then
			onResponse({ positive = true, feedback = "Looks good" })
		end
	end)

	-- "Problem" button
	local negativeBtn = createButton("NegativeBtn", Constants.ICONS.ERROR .. " Problem", Constants.COLORS.accentError, 2)
	negativeBtn.MouseButton1Click:Connect(function()
		-- Show text input for details
		buttonRow.Visible = false
		ChatRenderer.showVerificationInput(verifyFrame, onResponse, false)
	end)

	-- "Describe" button
	local describeBtn = createButton("DescribeBtn", Constants.ICONS.INFO .. " Details", Constants.COLORS.accentPrimary, 3)
	describeBtn.MouseButton1Click:Connect(function()
		buttonRow.Visible = false
		ChatRenderer.showVerificationInput(verifyFrame, onResponse, nil)
	end)

	-- Auto-scroll to show verification
	task.spawn(function()
		task.wait(0.05)
		if state.ui.chatHistory then
			local canvasSize = state.ui.chatHistory.AbsoluteCanvasSize.Y
			local frameSize = state.ui.chatHistory.AbsoluteSize.Y
			state.ui.chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize + 20))
		end
	end)

	return verifyFrame
end

--[[
    Show text input for verification feedback
    @param verifyFrame Frame - The verification frame
    @param onResponse function - Callback
    @param isNegative boolean|nil - Whether this is for a negative response
]]
function ChatRenderer.showVerificationInput(verifyFrame, onResponse, isNegative)
	local inputFrame = Create.new("Frame", {
		Name = "InputArea",
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		Parent = verifyFrame
	})

	local textBox = Create.new("TextBox", {
		Name = "FeedbackInput",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Color3.fromRGB(30, 35, 42),
		TextColor3 = Constants.COLORS.textPrimary,
		PlaceholderText = isNegative == false and "What's the problem?" or "Describe what you see...",
		PlaceholderColor3 = Constants.COLORS.textMuted,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Text = "",
		Parent = inputFrame
	})

	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = textBox })
	Create.new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = textBox
	})

	local submitBtn = Create.new("TextButton", {
		Name = "SubmitBtn",
		Text = "Send",
		Size = UDim2.new(0.4, 0, 0, 24),
		Position = UDim2.new(0.3, 0, 0, 34),
		BackgroundColor3 = Constants.COLORS.accentPrimary,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		Parent = inputFrame
	})
	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = submitBtn })
	addHoverEffect(submitBtn, Constants.COLORS.accentPrimary)

	submitBtn.MouseButton1Click:Connect(function()
		local feedbackText = textBox.Text
		if feedbackText == "" then
			feedbackText = isNegative == false and "Something doesn't look right" or "No additional details"
		end

		-- Replace input with response indicator
		inputFrame:Destroy()
		Create.new("TextLabel", {
			Name = "Response",
			Text = Constants.ICONS.INFO .. " Feedback: \"" .. feedbackText:sub(1, 50) .. (feedbackText:len() > 50 and Constants.ICONS.THINKING or "") .. "\"",
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			TextColor3 = Constants.COLORS.textSecondary,
			Font = Constants.UI.FONT_NORMAL,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 6,
			Parent = verifyFrame
		})

		if onResponse then
			onResponse({
				positive = isNegative == nil and nil or not isNegative,
				feedback = feedbackText
			})
		end
	end)

	-- Auto-focus and handle enter
	task.defer(function()
		textBox:CaptureFocus()
	end)

	textBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and textBox.Text ~= "" then
			submitBtn.MouseButton1Click:Fire()
		end
	end)
end

--[[
    Remove a verification prompt (when no longer needed)
    @param verifyFrame Frame - The verification frame to remove
]]
function ChatRenderer.removeVerificationPrompt(verifyFrame)
	if verifyFrame and verifyFrame.Parent then
		verifyFrame:Destroy()
	end
end

-- ============================================================================
-- COLLAPSIBLE CONTAINERS (Enhanced with animation and improved UX)
-- ============================================================================

local TweenService = game:GetService("TweenService")

-- Animation config for collapsibles
local COLLAPSE_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

--[[
    Create a collapsible container with expand/collapse toggle
    Enhanced with: larger icons, smooth animation, better preview, hover effects
    @param state table - State with ui references
    @param config table - { 
        title: string, 
        icon: string, 
        headerColor: Color3,
        bgColor: Color3,
        collapsed: boolean (default true),
        previewText: string (shown when collapsed)
    }
    @return Frame, Frame - container frame, content frame (where to add children)
]]
function ChatRenderer.createCollapsibleContainer(state, config)
	if not state or not state.ui then return nil, nil end

	config = config or {}
	local title = config.title or "Details"
	local icon = config.icon or "[+]"
	local headerColor = config.headerColor or Constants.COLORS.accentWarning
	local bgColor = config.bgColor or Constants.COLORS.toolActivityBg
	local collapsed = config.collapsed ~= false -- Default to collapsed
	local previewText = config.previewText or ""

	local layoutOrder = #state.chatMessages + 1

	-- Main container
	local container = Create.new("Frame", {
		Name = "Collapsible_" .. tick(),
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = bgColor,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		ClipsDescendants = true,
		LayoutOrder = layoutOrder,
		Parent = state.ui.chatHistory
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = container
	})

	Create.new("UIStroke", {
		Color = headerColor,
		Thickness = 1,
		Transparency = 0.6,
		Parent = container
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = container
	})

	Create.new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = container
	})

	-- Header row (clickable) - Now with background for hover
	local headerRow = Create.new("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = Constants.COLORS.collapsibleHeader or Color3.fromRGB(45, 50, 65),
		BackgroundTransparency = 0.5,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 0,
		Parent = container
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 6),
		Parent = headerRow
	})

	-- Toggle arrow icon (LARGER and more visible)
	local toggleIcon = Create.new("TextLabel", {
		Name = "ToggleIcon",
		Size = UDim2.new(0, 24, 0, 24),
		Position = UDim2.new(0, 4, 0.5, -12),
		BackgroundTransparency = 1,
		Text = collapsed and Constants.ICONS.EXPAND or Constants.ICONS.COLLAPSE,
		TextColor3 = headerColor,
		Font = Enum.Font.GothamBold,
		TextSize = 16, -- Larger icon
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = headerRow
	})

	-- Title label (positioned after icon)
	local titleLabel = Create.new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.new(0, 32, 0, 0),
		BackgroundTransparency = 1,
		Text = icon .. " " .. title,
		TextColor3 = headerColor,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = headerRow
	})

	-- Expand/collapse hint text
	local hintLabel = Create.new("TextLabel", {
		Name = "Hint",
		Size = UDim2.new(0, 60, 1, 0),
		Position = UDim2.new(1, -64, 0, 0),
		BackgroundTransparency = 1,
		Text = collapsed and "expand" or "collapse",
		TextColor3 = Constants.COLORS.textMuted,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = headerRow
	})

	-- Preview text container (shown when collapsed) - More prominent
	local previewContainer = Create.new("Frame", {
		Name = "PreviewContainer",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		BackgroundTransparency = 0.5,
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = collapsed and previewText ~= "",
		LayoutOrder = 1,
		Parent = container
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = previewContainer
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = previewContainer
	})

	local previewLabel = Create.new("TextLabel", {
		Name = "Preview",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = "\"" .. previewText .. "\"",
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = previewContainer
	})

	-- Content frame (holds the actual content, hidden when collapsed)
	local contentFrame = Create.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = not collapsed,
		LayoutOrder = 2,
		Parent = container
	})

	Create.new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = contentFrame
	})

	-- State tracking
	local isCollapsed = collapsed
	local isAnimating = false

	-- Toggle collapse/expand on header click with animation
	headerRow.MouseButton1Click:Connect(function()
		if isAnimating then return end
		isAnimating = true

		isCollapsed = not isCollapsed

		-- Update hint text
		hintLabel.Text = isCollapsed and "expand" or "collapse"

		-- Animate toggle icon rotation via text change
		if isCollapsed then
			-- Collapsing animation
			toggleIcon.Text = Constants.ICONS.COLLAPSE
			task.wait(0.05)
			toggleIcon.Text = Constants.ICONS.EXPAND

			-- Hide content with fade
			local fadeTween = TweenService:Create(contentFrame, COLLAPSE_TWEEN_INFO, {
				BackgroundTransparency = 1
			})
			fadeTween:Play()
			fadeTween.Completed:Wait()

			contentFrame.Visible = false
			previewContainer.Visible = previewText ~= ""

			-- Fade in preview
			if previewText ~= "" then
				previewContainer.BackgroundTransparency = 1
				local previewTween = TweenService:Create(previewContainer, COLLAPSE_TWEEN_INFO, {
					BackgroundTransparency = 0.5
				})
				previewTween:Play()
			end
		else
			-- Expanding animation
			toggleIcon.Text = Constants.ICONS.EXPAND
			task.wait(0.05)
			toggleIcon.Text = Constants.ICONS.COLLAPSE

			-- Hide preview first
			if previewContainer.Visible then
				local hideTween = TweenService:Create(previewContainer, COLLAPSE_TWEEN_INFO, {
					BackgroundTransparency = 1
				})
				hideTween:Play()
				hideTween.Completed:Wait()
			end
			previewContainer.Visible = false

			-- Show content
			contentFrame.Visible = true
		end

		isAnimating = false

		-- Auto-scroll after toggle
		task.spawn(function()
			task.wait(0.1)
			if state.ui.chatHistory then
				local canvasSize = state.ui.chatHistory.AbsoluteCanvasSize.Y
				local frameSize = state.ui.chatHistory.AbsoluteSize.Y
				state.ui.chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
			end
		end)
	end)

	-- Hover effects on header
	headerRow.MouseEnter:Connect(function()
		if not isAnimating then
			TweenService:Create(headerRow, TweenInfo.new(0.15), {
				BackgroundTransparency = 0.3,
				BackgroundColor3 = Constants.COLORS.collapsibleHeaderHover or Color3.fromRGB(55, 60, 78)
			}):Play()
			toggleIcon.TextColor3 = Constants.COLORS.textPrimary
			hintLabel.TextColor3 = Constants.COLORS.textSecondary
		end
	end)

	headerRow.MouseLeave:Connect(function()
		TweenService:Create(headerRow, TweenInfo.new(0.15), {
			BackgroundTransparency = 0.5,
			BackgroundColor3 = Constants.COLORS.collapsibleHeader or Color3.fromRGB(45, 50, 65)
		}):Play()
		toggleIcon.TextColor3 = headerColor
		hintLabel.TextColor3 = Constants.COLORS.textMuted
	end)

	return container, contentFrame
end

--[[
    Add a collapsible planning message (collapsed by default)
    @param state table - State with ui references
    @param thoughts table - Array of thought strings to display
    @param summary string - Short summary shown when collapsed
    @return Frame - The collapsible container
]]
function ChatRenderer.addCollapsiblePlanning(state, thoughts, summary)
	if not state or not state.ui then return nil end
	if not thoughts or #thoughts == 0 then return nil end

	-- Create preview summary
	local previewText = summary or thoughts[1]:sub(1, 60)
	if #previewText > 60 then previewText = previewText .. "..." end

	local container, contentFrame = ChatRenderer.createCollapsibleContainer(state, {
		title = "Planning Phase",
		icon = Constants.ICONS.THINKING,
		headerColor = Constants.COLORS.accentWarning,
		bgColor = Constants.COLORS.messagePlanning or Color3.fromRGB(45, 45, 60),
		collapsed = true,
		previewText = previewText
	})

	if not container or not contentFrame then return nil end

	-- Add thoughts as content
	for i, thought in ipairs(thoughts) do
		-- Determine thought type from prefix
		local bgColor = Constants.COLORS.backgroundLight
		local textColor = Constants.COLORS.textPrimary

		if thought:find(Constants.ICONS.READ) then
			bgColor = Color3.fromRGB(45, 55, 70)
			textColor = Color3.fromRGB(150, 180, 255)
		elseif thought:find(Constants.ICONS.SUCCESS) then
			bgColor = Color3.fromRGB(40, 55, 45)
			textColor = Color3.fromRGB(150, 255, 180)
		elseif thought:find(Constants.ICONS.ERROR) or thought:find(Constants.ICONS.FAIL) then
			bgColor = Color3.fromRGB(60, 40, 40)
			textColor = Color3.fromRGB(255, 180, 180)
		end

		local thoughtFrame = Create.new("Frame", {
			Name = "Thought_" .. i,
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundColor3 = bgColor,
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = i,
			Parent = contentFrame
		})

		Create.new("UICorner", {
			CornerRadius = UDim.new(0, 4),
			Parent = thoughtFrame
		})

		Create.new("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			Parent = thoughtFrame
		})

		Create.new("TextLabel", {
			Name = "Text",
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			Text = thought,
			TextColor3 = textColor,
			Font = Constants.UI.FONT_NORMAL,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			RichText = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = thoughtFrame
		})
	end

	-- Add to chat messages for tracking
	table.insert(state.chatMessages, {
		role = "assistant",
		text = table.concat(thoughts, "\n"),
		timestamp = tick(),
		isPlanningPhase = true,
		isCollapsible = true
	})

	container.Name = "Message_" .. #state.chatMessages
	container.LayoutOrder = #state.chatMessages

	return container
end

--[[
    Start a collapsible system message group
    Used for grouping consecutive tool approvals
    @param state table - State with ui references
    @param groupTitle string - Title for the group (e.g., "Creating HealthBar")
]]
function ChatRenderer.startCollapsibleSystemGroup(state, groupTitle)
	if not state or not state.ui then return end

	-- Finalize any existing group first
	if currentSystemGroup then
		ChatRenderer.finalizeCollapsibleSystemGroup()
	end

	local container, contentFrame = ChatRenderer.createCollapsibleContainer(state, {
		title = groupTitle or "Operations",
		icon = Constants.ICONS.READ,
		headerColor = Constants.COLORS.toolSuccessBorder or Constants.COLORS.accentSuccess,
		bgColor = Constants.COLORS.toolActivityBg or Color3.fromRGB(35, 40, 45),
		collapsed = true,
		previewText = "Click to expand..."
	})

	if container and contentFrame then
		currentSystemGroup = container
		systemGroupItems = {}
		systemGroupState = state

		-- Store content frame reference
		container:SetAttribute("ContentFrame", contentFrame.Name)
	end
end

--[[
    Add an item to the current collapsible system group
    @param text string - The item text (e.g., "Approved: create instance ...")
    @param status string - "success" | "error" | "pending"
]]
function ChatRenderer.addCollapsibleSystemItem(text, status)
	if not currentSystemGroup then return end

	local contentFrame = currentSystemGroup:FindFirstChild("Content")
	if not contentFrame then return end

	status = status or "success"

	local icon = Constants.ICONS.SUCCESS
	local textColor = Color3.fromRGB(140, 200, 160) -- Soft green

	if status == "pending" then
		icon = Constants.ICONS.PENDING
		textColor = Color3.fromRGB(160, 180, 220) -- Soft blue
	elseif status == "error" then
		icon = Constants.ICONS.FAIL
		textColor = Color3.fromRGB(220, 140, 140) -- Soft red
	end

	local itemLabel = Create.new("TextLabel", {
		Name = "Item_" .. #systemGroupItems,
		Text = icon .. " " .. text,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		TextColor3 = textColor,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = #systemGroupItems + 1,
		Parent = contentFrame
	})

	table.insert(systemGroupItems, {
		label = itemLabel,
		text = text,
		status = status
	})

	-- Update preview text in the PreviewContainer
	local previewContainer = currentSystemGroup:FindFirstChild("PreviewContainer")
	if previewContainer then
		local preview = previewContainer:FindFirstChild("Preview")
		if preview then
			preview.Text = "\"" .. string.format("%d operations completed...", #systemGroupItems) .. "\""
		end
	end

	-- Auto-scroll
	if systemGroupState and systemGroupState.ui and systemGroupState.ui.chatHistory then
		task.spawn(function()
			task.wait(0.03)
			local chatHistory = systemGroupState.ui.chatHistory
			local canvasSize = chatHistory.AbsoluteCanvasSize.Y
			local frameSize = chatHistory.AbsoluteSize.Y
			chatHistory.CanvasPosition = Vector2.new(0, math.max(0, canvasSize - frameSize))
		end)
	end
end

--[[
    Finalize the current collapsible system group
    Updates the header with final count
]]
function ChatRenderer.finalizeCollapsibleSystemGroup()
	if not currentSystemGroup then return end

	-- Count successes and errors
	local successCount = 0
	local errorCount = 0
	for _, item in ipairs(systemGroupItems) do
		if item.status == "success" then
			successCount = successCount + 1
		elseif item.status == "error" then
			errorCount = errorCount + 1
		end
	end

	-- Update header title
	local header = currentSystemGroup:FindFirstChild("Header")
	if header then
		local title = header:FindFirstChild("Title")
		if title then
			local statusText = string.format("%d completed", successCount)
			if errorCount > 0 then
				statusText = statusText .. string.format(", %d failed", errorCount)
			end
			title.Text = Constants.ICONS.SUCCESS .. " " .. statusText
		end
	end

	-- Update preview
	local preview = currentSystemGroup:FindFirstChild("Preview")
	if preview then
		preview.Text = string.format("%d operations completed", #systemGroupItems)
	end

	-- Update layout order to proper position
	if systemGroupState then
		local newOrder = #systemGroupState.chatMessages + 1
		currentSystemGroup.LayoutOrder = newOrder
	end

	-- Clear references
	currentSystemGroup = nil
	systemGroupItems = {}
	systemGroupState = nil
end

--[[
    Check if there's an active system group
    @return boolean
]]
function ChatRenderer.hasActiveSystemGroup()
	return currentSystemGroup ~= nil
end

--[[
    Get the current system group item count
    @return number
]]
function ChatRenderer.getSystemGroupItemCount()
	return #systemGroupItems
end

return ChatRenderer
