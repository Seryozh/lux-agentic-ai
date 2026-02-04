local HttpService = game:GetService("HttpService")

local ProjectMap = require(script.ProjectMap)
local Backend = require(script.Backend)
local ScriptReader = require(script.ScriptReader)
local ActionExecutor = require(script.ActionExecutor)
local ScriptIndex = require(script.ScriptIndex)

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
local estimatedTokens = 0

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

local newChatButton = Instance.new("TextButton")
newChatButton.Size = UDim2.new(0, 60, 0, 18)
newChatButton.Position = UDim2.new(1, -180, 0.5, -9)
newChatButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
newChatButton.TextColor3 = Color3.fromRGB(150, 150, 150)
newChatButton.Text = "New Chat"
newChatButton.Font = Enum.Font.SourceSans
newChatButton.TextSize = 11
newChatButton.Parent = statusBar
local newChatCorner = Instance.new("UICorner")
newChatCorner.CornerRadius = UDim.new(0, 3)
newChatCorner.Parent = newChatButton

local creditsLabel = Instance.new("TextLabel")
creditsLabel.Size = UDim2.new(0, 80, 1, 0)
creditsLabel.Position = UDim2.new(1, -110, 0, 0)
creditsLabel.BackgroundTransparency = 1
creditsLabel.TextColor3 = Color3.fromRGB(255, 180, 100)
creditsLabel.Text = "~0 tokens"
creditsLabel.TextXAlignment = Enum.TextXAlignment.Right
creditsLabel.Font = Enum.Font.SourceSans
creditsLabel.TextSize = 11
creditsLabel.Parent = statusBar

local requestsLabel = Instance.new("TextLabel")
requestsLabel.Size = UDim2.new(0, 30, 1, 0)
requestsLabel.Position = UDim2.new(1, -25, 0, 0)
requestsLabel.BackgroundTransparency = 1
requestsLabel.TextColor3 = Color3.fromRGB(100, 180, 255)
requestsLabel.Text = "0"
requestsLabel.TextXAlignment = Enum.TextXAlignment.Right
requestsLabel.Font = Enum.Font.SourceSans
requestsLabel.TextSize = 11
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
chatLayout.Padding = UDim.new(0, 8)
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

-- API Key Screen
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

-- Helper functions
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

local function estimateTokens(text, projectMapSize)
	local baseTokens = 800
	local textTokens = math.ceil(#text / 4)
	local mapTokens = math.ceil((projectMapSize or 0) / 4)
	return baseTokens + textTokens + mapTokens
end

local function updateRequestCount()
	requestsLabel.Text = tostring(requestCount)
	if estimatedTokens > 0 then
		local k = estimatedTokens >= 1000
		creditsLabel.Text = k and ("~" .. math.floor(estimatedTokens/1000) .. "k tokens") or ("~" .. estimatedTokens .. " tokens")
	end
end

local function resetChat()
	for _, child in ipairs(chatScroll:GetChildren()) do
		if child:IsA("TextLabel") or child:IsA("Frame") then
			child:Destroy()
		end
	end
	messageOrder = 0
	estimatedTokens = 0
	SESSION_ID = HttpService:GenerateGUID(false)
	updateRequestCount()
	updateStatus("Ready", Color3.fromRGB(100, 200, 100))
	addMessage("New chat started. What would you like to build?", false)
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


local function showActions(actions)
	if not actions or #actions == 0 then return end

	messageOrder += 1
	local actionsFrame = Instance.new("Frame")
	actionsFrame.Size = UDim2.new(1, -16, 0, 0)
	actionsFrame.AutomaticSize = Enum.AutomaticSize.Y
	actionsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	actionsFrame.BorderSizePixel = 0
	actionsFrame.LayoutOrder = messageOrder
	actionsFrame.Parent = chatScroll

	local actionsCorner = Instance.new("UICorner")
	actionsCorner.CornerRadius = UDim.new(0, 4)
	actionsCorner.Parent = actionsFrame

	local actionsPadding = Instance.new("UIPadding")
	actionsPadding.PaddingLeft = UDim.new(0, 10)
	actionsPadding.PaddingRight = UDim.new(0, 10)
	actionsPadding.PaddingTop = UDim.new(0, 8)
	actionsPadding.PaddingBottom = UDim.new(0, 8)
	actionsPadding.Parent = actionsFrame

	local actionsText = ""
	for i, action in ipairs(actions) do
		actionsText = actionsText .. i .. ". " .. ActionExecutor.describe(action) .. "\n"
	end

	local actionsLabel = Instance.new("TextLabel")
	actionsLabel.Size = UDim2.new(1, 0, 0, 0)
	actionsLabel.AutomaticSize = Enum.AutomaticSize.Y
	actionsLabel.BackgroundTransparency = 1
	actionsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	actionsLabel.Text = actionsText
	actionsLabel.TextWrapped = true
	actionsLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionsLabel.Font = Enum.Font.SourceSans
	actionsLabel.TextSize = 12
	actionsLabel.Parent = actionsFrame

	return actionsFrame
end

local function showApplyButton(actions, onApply)
	messageOrder += 1
	local btnFrame = Instance.new("Frame")
	btnFrame.Size = UDim2.new(1, -16, 0, 36)
	btnFrame.BackgroundTransparency = 1
	btnFrame.LayoutOrder = messageOrder
	btnFrame.Parent = chatScroll

	local applyBtn = Instance.new("TextButton")
	applyBtn.Size = UDim2.new(0, 150, 0, 32)
	applyBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 40)
	applyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	applyBtn.Text = "✓ Apply All Actions"
	applyBtn.Font = Enum.Font.SourceSansBold
	applyBtn.TextSize = 14
	applyBtn.Parent = btnFrame

	local applyCorner = Instance.new("UICorner")
	applyCorner.CornerRadius = UDim.new(0, 4)
	applyCorner.Parent = applyBtn

	local isApplying = false
	applyBtn.MouseButton1Click:Connect(function()
		if isApplying then return end  -- Prevent double-click
		isApplying = true

		applyBtn.Text = "Applying..."
		applyBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		onApply()
	end)

	return btnFrame
end

local function showComplete()
	messageOrder += 1
	local completeFrame = Instance.new("Frame")
	completeFrame.Size = UDim2.new(1, -16, 0, 0)
	completeFrame.AutomaticSize = Enum.AutomaticSize.Y
	completeFrame.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
	completeFrame.BorderSizePixel = 0
	completeFrame.LayoutOrder = messageOrder
	completeFrame.Parent = chatScroll

	local completeCorner = Instance.new("UICorner")
	completeCorner.CornerRadius = UDim.new(0, 4)
	completeCorner.Parent = completeFrame

	local completePadding = Instance.new("UIPadding")
	completePadding.PaddingLeft = UDim.new(0, 10)
	completePadding.PaddingRight = UDim.new(0, 10)
	completePadding.PaddingTop = UDim.new(0, 8)
	completePadding.PaddingBottom = UDim.new(0, 8)
	completePadding.Parent = completeFrame

	local completeLabel = Instance.new("TextLabel")
	completeLabel.Size = UDim2.new(1, 0, 0, 0)
	completeLabel.AutomaticSize = Enum.AutomaticSize.Y
	completeLabel.BackgroundTransparency = 1
	completeLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
	completeLabel.Text = "✓ Actions Applied"
	completeLabel.Font = Enum.Font.SourceSansBold
	completeLabel.TextSize = 13
	completeLabel.TextXAlignment = Enum.TextXAlignment.Left
	completeLabel.Parent = completeFrame
end

local function pollLoop(sessionId)
	while isProcessing do
		local pollData, err = Backend.poll(sessionId)
		if pollData and pollData.pending_requests then
			for _, req in ipairs(pollData.pending_requests) do
				local data = ScriptReader.handleRequest(req.request_type, req.target)
				Backend.respond(sessionId, req.request_id, data)
			end
		end
		task.wait(0.1)
	end
end

function sendMessage()
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
		local projectMap = ProjectMap.buildLazy()
		requestCount += 1
		updateRequestCount()

		local response, err = Backend.sendChat(SESSION_ID, text, projectMap, API_KEY)
		isProcessing = false

		if err then
			updateStatus("Error", Color3.fromRGB(255, 100, 100))
			addMessage("Error: " .. err, false)
			return
		end

		local tokens = estimateTokens(text .. (response.message or ""), #projectMap)
		estimatedTokens = tokens
		updateRequestCount()
		updateStatus("Ready", Color3.fromRGB(100, 200, 100))

		addMessage(response.message, false)

		if response.actions and #response.actions > 0 then
			local actionsFrame = showActions(response.actions)

			local applyBtnFrame = showApplyButton(response.actions, function()
				updateStatus("Applying...", Color3.fromRGB(100, 200, 255))

				local successCount = 0
				for _, action in ipairs(response.actions) do
					local results = ActionExecutor.execute({action})
					for _, r in ipairs(results) do
						if not r:match("^ERROR:") then
							successCount = successCount + 1
						end
					end
				end

				-- Use task.defer to destroy frames AFTER callback completes
				-- (can't destroy from within child's callback)
				task.defer(function()
					if actionsFrame and actionsFrame.Parent then
						actionsFrame:Destroy()
					end
					if applyBtnFrame and applyBtnFrame.Parent then
						applyBtnFrame:Destroy()
					end
				end)

				showComplete()
				updateStatus("Ready", Color3.fromRGB(100, 200, 100))
			end)
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
	addMessage("API key set! Ready to build.", false)
end)

sendButton.MouseButton1Click:Connect(sendMessage)
inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		sendMessage()
	end
end)

newChatButton.MouseButton1Click:Connect(function()
	if not isProcessing then
		resetChat()
	end
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

task.spawn(function()
	print("[Luxembourg] Building script index...")
	local startTime = tick()
	ScriptIndex.build()
	local elapsed = math.floor((tick() - startTime) * 1000)
	print("[Luxembourg] Script index built in " .. elapsed .. "ms")
end)

if API_KEY == "" then
	showApiKeyScreen()
else
	showChatScreen()
	updateStatus("Ready", Color3.fromRGB(100, 200, 100))
end
