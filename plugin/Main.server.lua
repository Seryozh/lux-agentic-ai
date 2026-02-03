--[[
    Luxembourg Plugin - Main Entry Point

    This is a Roblox Studio plugin. It:
    1. Creates a toolbar button and dock widget (chat UI)
    2. On send: scans the game tree, sends to backend, polls for agent requests
    3. Applies script changes from the response

    To install: place this in your Roblox Studio plugins folder.
]]

local ProjectMap = require(script.ProjectMap)
local Backend = require(script.Backend)
local ScriptReader = require(script.ScriptReader)
local ActionExecutor = require(script.ActionExecutor)

-- Plugin setup
local toolbar = plugin:CreateToolbar("Luxembourg")
local button = toolbar:CreateButton("Open Chat", "Open Luxembourg AI Chat", "rbxassetid://0")

-- Create the dock widget (chat window)
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, -- initially disabled
	false, -- override previous state
	300,   -- default width
	400,   -- default height
	200,   -- min width
	200    -- min height
)
local widget = plugin:CreateDockWidgetPluginGui("LuxembourgChat", widgetInfo)
widget.Title = "Luxembourg"

-- Session state
local SESSION_ID = game:GetService("HttpService"):GenerateGUID(false)
local API_KEY = "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"
local isProcessing = false

-- ============================================================
-- UI (simple chat interface)
-- ============================================================

local screenGui = Instance.new("Frame")
screenGui.Size = UDim2.new(1, 0, 1, 0)
screenGui.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
screenGui.Parent = widget

-- Chat history display
local chatScroll = Instance.new("ScrollingFrame")
chatScroll.Size = UDim2.new(1, 0, 1, -50)
chatScroll.Position = UDim2.new(0, 0, 0, 0)
chatScroll.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
chatScroll.BorderSizePixel = 0
chatScroll.ScrollBarThickness = 6
chatScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
chatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
chatScroll.Parent = screenGui

local chatLayout = Instance.new("UIListLayout")
chatLayout.SortOrder = Enum.SortOrder.LayoutOrder
chatLayout.Padding = UDim.new(0, 4)
chatLayout.Parent = chatScroll

-- Input area
local inputFrame = Instance.new("Frame")
inputFrame.Size = UDim2.new(1, 0, 0, 44)
inputFrame.Position = UDim2.new(0, 0, 1, -44)
inputFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
inputFrame.BorderSizePixel = 0
inputFrame.Parent = screenGui

local inputBox = Instance.new("TextBox")
inputBox.Size = UDim2.new(1, -60, 1, -8)
inputBox.Position = UDim2.new(0, 8, 0, 4)
inputBox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
inputBox.PlaceholderText = "Ask Luxembourg..."
inputBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
inputBox.Text = ""
inputBox.TextXAlignment = Enum.TextXAlignment.Left
inputBox.ClearTextOnFocus = false
inputBox.Font = Enum.Font.SourceSans
inputBox.TextSize = 14
inputBox.Parent = inputFrame

local sendButton = Instance.new("TextButton")
sendButton.Size = UDim2.new(0, 44, 1, -8)
sendButton.Position = UDim2.new(1, -52, 0, 4)
sendButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
sendButton.TextColor3 = Color3.fromRGB(255, 255, 255)
sendButton.Text = ">"
sendButton.Font = Enum.Font.SourceSansBold
sendButton.TextSize = 18
sendButton.Parent = inputFrame

-- ============================================================
-- Chat functions
-- ============================================================

local messageOrder = 0

local function addMessage(text, isUser)
	messageOrder += 1

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = isUser and Color3.fromRGB(100, 180, 255) or Color3.fromRGB(220, 220, 220)
	label.Text = (isUser and "You: " or "Lux: ") .. text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSans
	label.TextSize = 14
	label.LayoutOrder = messageOrder
	label.Parent = chatScroll
end

local function addDebug(text)
	-- Debug/status messages in dim color
	messageOrder += 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(120, 120, 120)
	label.Text = "  " .. text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSansItalic
	label.TextSize = 12
	label.LayoutOrder = messageOrder
	label.Parent = chatScroll
end

local function setStatus(text)
	local existing = chatScroll:FindFirstChild("_status")
	if not existing then
		messageOrder += 1
		existing = Instance.new("TextLabel")
		existing.Name = "_status"
		existing.Size = UDim2.new(1, -16, 0, 20)
		existing.Position = UDim2.new(0, 8, 0, 0)
		existing.BackgroundTransparency = 1
		existing.TextColor3 = Color3.fromRGB(150, 150, 150)
		existing.TextXAlignment = Enum.TextXAlignment.Left
		existing.Font = Enum.Font.SourceSansItalic
		existing.TextSize = 13
		existing.LayoutOrder = 999999
		existing.Parent = chatScroll
	end
	existing.Text = text
	existing.Visible = text ~= ""
end

-- ============================================================
-- Polling loop: runs while the agent is processing
-- ============================================================

local function pollLoop(sessionId)
	while isProcessing do
		local pollData, err = Backend.poll(sessionId)
		if pollData and pollData.pending_requests then
			for _, req in ipairs(pollData.pending_requests) do
				-- Show what the agent is doing
				if req.request_type == "get_metadata" then
					addDebug("Requesting metadata for: " .. req.target)
					setStatus("Reading metadata: " .. req.target)
				elseif req.request_type == "get_full_script" then
					addDebug("Reading full script: " .. req.target)
					setStatus("Reading script: " .. req.target)
				else
					addDebug("Agent request: " .. req.request_type .. " → " .. req.target)
				end

				local data = ScriptReader.handleRequest(req.request_type, req.target)

				if data.error then
					addDebug("  Not found: " .. data.error)
				end

				Backend.respond(sessionId, req.request_id, data)
			end
		end
		wait(0.5)
	end
end

-- ============================================================
-- Send message
-- ============================================================

local function sendMessage()
	local text = inputBox.Text
	if text == "" or isProcessing then return end

	-- Check API key
	if API_KEY == "" then
		API_KEY = plugin:GetSetting("OpenRouterKey") or ""
		if API_KEY == "" then
			addMessage("Please set your OpenRouter API key first. Go to plugin settings.", false)
			return
		end
	end

	inputBox.Text = ""
	addMessage(text, true)
	setStatus("Thinking...")
	isProcessing = true

	-- Run polling in a separate thread
	task.spawn(pollLoop, SESSION_ID)

	-- Send chat request (this blocks until the agent finishes)
	task.spawn(function()
		addDebug("Scanning project map...")
		local projectMap = ProjectMap.build()
		addDebug("Project map built. Sending to backend...")
		local response, err = Backend.sendChat(SESSION_ID, text, projectMap, API_KEY)

		isProcessing = false  -- stops the poll loop
		setStatus("")

		if err then
			addMessage("Error: " .. err, false)
			return
		end

		-- Show the response message
		addMessage(response.message, false)

		-- Step-by-step approval: show each action, let user approve or skip
		if response.actions and #response.actions > 0 then
			addDebug(#response.actions .. " actions proposed:")

			for i, action in ipairs(response.actions) do
				local desc = ActionExecutor.describe(action)
				addDebug("Step " .. i .. "/" .. #response.actions .. ": " .. desc)

				-- Create approve/skip/deny-all buttons
				messageOrder += 1
				local btnFrame = Instance.new("Frame")
				btnFrame.Size = UDim2.new(1, -16, 0, 30)
				btnFrame.Position = UDim2.new(0, 8, 0, 0)
				btnFrame.BackgroundTransparency = 1
				btnFrame.LayoutOrder = messageOrder
				btnFrame.Parent = chatScroll

				local approveBtn = Instance.new("TextButton")
				approveBtn.Size = UDim2.new(0, 70, 0, 26)
				approveBtn.Position = UDim2.new(0, 0, 0, 0)
				approveBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 40)
				approveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				approveBtn.Text = "Apply"
				approveBtn.Font = Enum.Font.SourceSansBold
				approveBtn.TextSize = 14
				approveBtn.Parent = btnFrame

				local skipBtn = Instance.new("TextButton")
				skipBtn.Size = UDim2.new(0, 70, 0, 26)
				skipBtn.Position = UDim2.new(0, 78, 0, 0)
				skipBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
				skipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				skipBtn.Text = "Skip"
				skipBtn.Font = Enum.Font.SourceSansBold
				skipBtn.TextSize = 14
				skipBtn.Parent = btnFrame

				local denyAllBtn = Instance.new("TextButton")
				denyAllBtn.Size = UDim2.new(0, 80, 0, 26)
				denyAllBtn.Position = UDim2.new(0, 156, 0, 0)
				denyAllBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
				denyAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				denyAllBtn.Text = "Deny All"
				denyAllBtn.Font = Enum.Font.SourceSansBold
				denyAllBtn.TextSize = 14
				denyAllBtn.Parent = btnFrame

				local decision = nil
				local c1 = approveBtn.MouseButton1Click:Connect(function() decision = "apply" end)
				local c2 = skipBtn.MouseButton1Click:Connect(function() decision = "skip" end)
				local c3 = denyAllBtn.MouseButton1Click:Connect(function() decision = "deny_all" end)

				while decision == nil do
					task.wait(0.1)
				end

				c1:Disconnect()
				c2:Disconnect()
				c3:Disconnect()
				btnFrame:Destroy()

				if decision == "deny_all" then
					addDebug("Remaining actions cancelled.")
					break
				elseif decision == "skip" then
					addDebug("Skipped: " .. desc)
				elseif decision == "apply" then
					local results = ActionExecutor.execute({action})
					for _, r in ipairs(results) do
						addMessage(r, false)
					end
				end
			end
		end
	end)
end

-- ============================================================
-- Connect UI
-- ============================================================

sendButton.MouseButton1Click:Connect(sendMessage)
inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		sendMessage()
	end
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

-- Prompt for API key if not set
if API_KEY == "" then
	addMessage("Welcome to Luxembourg! Set your OpenRouter API key in plugin settings to get started.", false)
end
