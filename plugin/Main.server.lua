local HttpService = game:GetService("HttpService")

local ProjectMap = require(script.ProjectMap)
local Backend = require(script.Backend)
local ScriptReader = require(script.ScriptReader)
local ActionExecutor = require(script.ActionExecutor)

local toolbar = plugin:CreateToolbar("Luxembourg")
local button = toolbar:CreateButton("Open Chat", "Open Luxembourg AI Chat", "rbxassetid://0")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	300,
	400,
	200,
	200
)
local widget = plugin:CreateDockWidgetPluginGui("LuxembourgChat", widgetInfo)
widget.Title = "Luxembourg"

local SESSION_ID = HttpService:GenerateGUID(false)
local API_KEY = plugin:GetSetting("LuxOpenRouterKey") or ""
local isProcessing = false
local requestCount = 0

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(1, 0, 1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = widget

local statusBar = Instance.new("Frame")
statusBar.Size = UDim2.new(1, 0, 0, 24)
statusBar.Position = UDim2.new(0, 0, 0, 0)
statusBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
statusBar.BorderSizePixel = 0
statusBar.Parent = mainFrame

local statusIndicator = Instance.new("Frame")
statusIndicator.Size = UDim2.new(0, 8, 0, 8)
statusIndicator.Position = UDim2.new(0, 8, 0.5, -4)
statusIndicator.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
statusIndicator.Parent = statusBar
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = statusIndicator

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -60, 1, 0)
statusLabel.Position = UDim2.new(0, 22, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.Text = "Ready"
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 12
statusLabel.Parent = statusBar

local requestsLabel = Instance.new("TextLabel")
requestsLabel.Size = UDim2.new(0, 50, 1, 0)
requestsLabel.Position = UDim2.new(1, -55, 0, 0)
requestsLabel.BackgroundTransparency = 1
requestsLabel.TextColor3 = Color3.fromRGB(100, 180, 255)
requestsLabel.Text = "0 reqs"
requestsLabel.TextXAlignment = Enum.TextXAlignment.Right
requestsLabel.Font = Enum.Font.SourceSans
requestsLabel.TextSize = 12
requestsLabel.Parent = statusBar

local chatScroll = Instance.new("ScrollingFrame")
chatScroll.Size = UDim2.new(1, 0, 1, -74)
chatScroll.Position = UDim2.new(0, 0, 0, 24)
chatScroll.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
chatScroll.BorderSizePixel = 0
chatScroll.ScrollBarThickness = 6
chatScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
chatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
chatScroll.Parent = mainFrame

local chatLayout = Instance.new("UIListLayout")
chatLayout.SortOrder = Enum.SortOrder.LayoutOrder
chatLayout.Padding = UDim.new(0, 4)
chatLayout.Parent = chatScroll

local inputFrame = Instance.new("Frame")
inputFrame.Size = UDim2.new(1, 0, 0, 44)
inputFrame.Position = UDim2.new(0, 0, 1, -44)
inputFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
inputFrame.BorderSizePixel = 0
inputFrame.Parent = mainFrame

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

local apiKeyFrame = Instance.new("Frame")
apiKeyFrame.Size = UDim2.new(1, 0, 1, 0)
apiKeyFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
apiKeyFrame.BorderSizePixel = 0
apiKeyFrame.Visible = false
apiKeyFrame.Parent = widget

local apiKeyTitle = Instance.new("TextLabel")
apiKeyTitle.Size = UDim2.new(1, 0, 0, 40)
apiKeyTitle.Position = UDim2.new(0, 0, 0, 40)
apiKeyTitle.BackgroundTransparency = 1
apiKeyTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
apiKeyTitle.Text = "Enter OpenRouter API Key"
apiKeyTitle.Font = Enum.Font.SourceSansBold
apiKeyTitle.TextSize = 16
apiKeyTitle.Parent = apiKeyFrame

local apiKeyDesc = Instance.new("TextLabel")
apiKeyDesc.Size = UDim2.new(1, -32, 0, 60)
apiKeyDesc.Position = UDim2.new(0, 16, 0, 80)
apiKeyDesc.BackgroundTransparency = 1
apiKeyDesc.TextColor3 = Color3.fromRGB(150, 150, 150)
apiKeyDesc.Text = "Get your key from openrouter.ai/keys\nYour key stays on your device."
apiKeyDesc.TextWrapped = true
apiKeyDesc.Font = Enum.Font.SourceSans
apiKeyDesc.TextSize = 13
apiKeyDesc.Parent = apiKeyFrame

local apiKeyInput = Instance.new("TextBox")
apiKeyInput.Size = UDim2.new(1, -32, 0, 36)
apiKeyInput.Position = UDim2.new(0, 16, 0, 150)
apiKeyInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
apiKeyInput.TextColor3 = Color3.fromRGB(255, 255, 255)
apiKeyInput.PlaceholderText = "sk-or-v1-..."
apiKeyInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
apiKeyInput.Text = ""
apiKeyInput.Font = Enum.Font.Code
apiKeyInput.TextSize = 12
apiKeyInput.ClearTextOnFocus = false
apiKeyInput.Parent = apiKeyFrame

local apiKeySave = Instance.new("TextButton")
apiKeySave.Size = UDim2.new(1, -32, 0, 36)
apiKeySave.Position = UDim2.new(0, 16, 0, 200)
apiKeySave.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
apiKeySave.TextColor3 = Color3.fromRGB(255, 255, 255)
apiKeySave.Text = "Save Key"
apiKeySave.Font = Enum.Font.SourceSansBold
apiKeySave.TextSize = 14
apiKeySave.Parent = apiKeyFrame

local apiKeyStatus = Instance.new("TextLabel")
apiKeyStatus.Size = UDim2.new(1, -32, 0, 20)
apiKeyStatus.Position = UDim2.new(0, 16, 0, 245)
apiKeyStatus.BackgroundTransparency = 1
apiKeyStatus.TextColor3 = Color3.fromRGB(255, 100, 100)
apiKeyStatus.Text = ""
apiKeyStatus.Font = Enum.Font.SourceSans
apiKeyStatus.TextSize = 12
apiKeyStatus.Parent = apiKeyFrame

local function showApiKeyScreen()
	apiKeyFrame.Visible = true
	mainFrame.Visible = false
end

local function showChatScreen()
	apiKeyFrame.Visible = false
	mainFrame.Visible = true
end

local function updateStatus(text, color)
	statusLabel.Text = text
	statusIndicator.BackgroundColor3 = color or Color3.fromRGB(100, 100, 100)
end

local function updateRequestCount()
	requestsLabel.Text = requestCount .. " reqs"
end

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

local function pollLoop(sessionId)
	while isProcessing do
		local pollData, err = Backend.poll(sessionId)
		if pollData and pollData.pending_requests then
			for _, req in ipairs(pollData.pending_requests) do
				if req.request_type == "get_metadata" then
					addDebug("Reading metadata: " .. req.target)
					updateStatus("Reading metadata...", Color3.fromRGB(255, 200, 100))
				elseif req.request_type == "get_full_script" then
					addDebug("Reading script: " .. req.target)
					updateStatus("Reading script...", Color3.fromRGB(255, 200, 100))
				end

				local data = ScriptReader.handleRequest(req.request_type, req.target)
				if data.error then
					addDebug("  Not found: " .. data.error)
				end
				Backend.respond(sessionId, req.request_id, data)
			end
		end
		task.wait(0.5)
	end
end

local function sendMessage()
	local text = inputBox.Text
	if text == "" or isProcessing then return end

	if API_KEY == "" then
		showApiKeyScreen()
		return
	end

	inputBox.Text = ""
	addMessage(text, true)
	updateStatus("Thinking...", Color3.fromRGB(100, 200, 255))
	isProcessing = true

	task.spawn(pollLoop, SESSION_ID)

	task.spawn(function()
		addDebug("Scanning project...")
		local projectMap = ProjectMap.build()
		addDebug("Sending to AI...")

		requestCount += 1
		updateRequestCount()

		local response, err = Backend.sendChat(SESSION_ID, text, projectMap, API_KEY)

		isProcessing = false

		if err then
			updateStatus("Error", Color3.fromRGB(255, 100, 100))
			addMessage("Error: " .. err, false)
			return
		end

		updateStatus("Ready", Color3.fromRGB(100, 200, 100))
		addMessage(response.message, false)

		if response.actions and #response.actions > 0 then
			addDebug(#response.actions .. " actions proposed:")

			for i, action in ipairs(response.actions) do
				local desc = ActionExecutor.describe(action)
				addDebug("Step " .. i .. "/" .. #response.actions .. ": " .. desc)

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
					addDebug("Skipped.")
				elseif decision == "apply" then
					updateStatus("Applying...", Color3.fromRGB(100, 200, 255))
					local results = ActionExecutor.execute({action})
					for _, r in ipairs(results) do
						addMessage(r, false)
					end
					updateStatus("Ready", Color3.fromRGB(100, 200, 100))
				end
			end
		end
	end)
end

apiKeySave.MouseButton1Click:Connect(function()
	local key = apiKeyInput.Text
	if key == "" then
		apiKeyStatus.Text = "Please enter a key"
		return
	end
	if not key:match("^sk%-or%-") then
		apiKeyStatus.Text = "Key should start with sk-or-"
		return
	end

	API_KEY = key
	plugin:SetSetting("LuxOpenRouterKey", key)
	apiKeyStatus.TextColor3 = Color3.fromRGB(100, 255, 100)
	apiKeyStatus.Text = "Key saved!"
	task.wait(1)
	showChatScreen()
	addMessage("API key set! You're ready to go.", false)
end)

sendButton.MouseButton1Click:Connect(sendMessage)
inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		sendMessage()
	end
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

if API_KEY == "" then
	showApiKeyScreen()
else
	showChatScreen()
	updateStatus("Ready", Color3.fromRGB(100, 200, 100))
end
