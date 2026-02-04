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
local actionsCompleted = {}
local currentTaskStartTime = 0

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

local function estimateTokens(text, projectMapSize)
	-- Rough token estimation: ~4 chars per token
	local baseTokens = 800 -- Optimized system prompt
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
	-- Clear chat history
	for _, child in ipairs(chatScroll:GetChildren()) do
		if child:IsA("TextLabel") or child:IsA("Frame") then
			child:Destroy()
		end
	end
	messageOrder = 0
	actionsCompleted = {}
	estimatedTokens = 0
	currentTaskStartTime = 0
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

local lastPlan = nil  -- Track the latest plan for continuation

local function showTaskSummary(plan)
	messageOrder += 1
	local summaryFrame = Instance.new("Frame")
	summaryFrame.Size = UDim2.new(1, -16, 0, 0)
	summaryFrame.AutomaticSize = Enum.AutomaticSize.Y
	summaryFrame.Position = UDim2.new(0, 8, 0, 0)
	summaryFrame.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
	summaryFrame.BorderSizePixel = 0
	summaryFrame.LayoutOrder = messageOrder
	summaryFrame.Parent = chatScroll

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = summaryFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = summaryFrame

	local summaryText = "✓ Step Complete\n\n"
	if #actionsCompleted > 0 then
		summaryText = summaryText .. "Applied " .. #actionsCompleted .. " action(s):\n"
		for i, action in ipairs(actionsCompleted) do
			summaryText = summaryText .. "  " .. i .. ". " .. action .. "\n"
		end
	end

	local elapsedTime = math.floor(tick() - currentTaskStartTime)
	summaryText = summaryText .. "\nCompleted in " .. elapsedTime .. "s"

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(200, 255, 200)
	label.Text = summaryText
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSans
	label.TextSize = 13
	label.Parent = summaryFrame

	-- Add action buttons based on plan status
	messageOrder += 1
	local btnFrame = Instance.new("Frame")
	btnFrame.Size = UDim2.new(1, -16, 0, 36)
	btnFrame.Position = UDim2.new(0, 8, 0, 0)
	btnFrame.BackgroundTransparency = 1
	btnFrame.LayoutOrder = messageOrder
	btnFrame.Parent = chatScroll

	-- Check if there are more steps in the plan
	local hasMoreSteps = plan and plan.current_step and plan.total_steps and plan.current_step < plan.total_steps

	if hasMoreSteps then
		-- Show "Continue" button for next step
		local continueBtn = Instance.new("TextButton")
		continueBtn.Size = UDim2.new(0, 140, 0, 30)
		continueBtn.Position = UDim2.new(0, 0, 0, 0)
		continueBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 80)
		continueBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		continueBtn.Text = "Continue Next Step"
		continueBtn.Font = Enum.Font.SourceSansBold
		continueBtn.TextSize = 14
		continueBtn.Parent = btnFrame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = continueBtn

		continueBtn.MouseButton1Click:Connect(function()
			-- Auto-send "continue" message to proceed with next step
			inputBox.Text = "continue"
			sendMessage()
		end)

		-- Also add "Start New Task" button next to it
		local newTaskBtn = Instance.new("TextButton")
		newTaskBtn.Size = UDim2.new(0, 120, 0, 30)
		newTaskBtn.Position = UDim2.new(0, 148, 0, 0)
		newTaskBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
		newTaskBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		newTaskBtn.Text = "Start New Task"
		newTaskBtn.Font = Enum.Font.SourceSansBold
		newTaskBtn.TextSize = 14
		newTaskBtn.Parent = btnFrame

		local btnCorner2 = Instance.new("UICorner")
		btnCorner2.CornerRadius = UDim.new(0, 4)
		btnCorner2.Parent = newTaskBtn

		newTaskBtn.MouseButton1Click:Connect(function()
			resetChat()
		end)
	else
		-- Plan complete or no plan - show "Start New Task" only
		local newTaskBtn = Instance.new("TextButton")
		newTaskBtn.Size = UDim2.new(0, 120, 0, 30)
		newTaskBtn.Position = UDim2.new(0, 0, 0, 0)
		newTaskBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
		newTaskBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		newTaskBtn.Text = "Start New Task"
		newTaskBtn.Font = Enum.Font.SourceSansBold
		newTaskBtn.TextSize = 14
		newTaskBtn.Parent = btnFrame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = newTaskBtn

		newTaskBtn.MouseButton1Click:Connect(function()
			resetChat()
		end)
	end
end

local function pollLoop(sessionId)
	-- LONG-POLLING: Continuously poll without artificial delay
	-- The backend holds the connection for up to 25s, so we get near-instant responses
	while isProcessing do
		local pollData, err = Backend.poll(sessionId)
		if pollData then
			-- 1. Handle Tool Requests
			if pollData.pending_requests then
				for _, req in ipairs(pollData.pending_requests) do
					local data = ScriptReader.handleRequest(req.request_type, req.target)
					Backend.respond(sessionId, req.request_id, data)
				end
			end

			-- 2. Handle Incremental Actions
			if pollData.queued_actions and #pollData.queued_actions > 0 then
				addDebug("Received " .. #pollData.queued_actions .. " incremental actions")
				-- For now, we'll just execute them to show the speed improvement
				-- In a full UI update, we would show an "Approve" button
				for _, action in ipairs(pollData.queued_actions) do
					local success, err = ActionExecutor.execute(action)
					if success then
						table.insert(actionsCompleted, action.type .. ": " .. action.target)
					else
						addDebug("Action Error: " .. tostring(err))
					end
				end
			end
		end
		-- NO WAIT: Immediately poll again (backend handles the waiting)
		-- Small yield to prevent blocking the main thread
		task.wait(0.05)
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
	actionsCompleted = {}
	currentTaskStartTime = tick()

	task.spawn(pollLoop, SESSION_ID)

	task.spawn(function()
		local projectMap = ProjectMap.buildLazy()  -- LAZY LOADING: Only top-level

		requestCount += 1
		updateRequestCount()

		local response, err = Backend.sendChat(SESSION_ID, text, projectMap, API_KEY)

		isProcessing = false

		if err then
			updateStatus("Error", Color3.fromRGB(255, 100, 100))
			addMessage("Error: " .. err, false)
			return
		end

		-- Estimate and show token usage after getting response
		local tokens = estimateTokens(text .. (response.message or ""), #projectMap)
		estimatedTokens = tokens
		updateRequestCount()

		updateStatus("Ready", Color3.fromRGB(100, 200, 100))

		-- Display compact plan progress if exists
		if response.plan and response.plan.steps and #response.plan.steps > 0 then
			local current = response.plan.current_step or 0
			local total = response.plan.total_steps or #response.plan.steps
			local planStatus = string.format("📋 Step %d/%d", current, total)
			updateStatus(planStatus, Color3.fromRGB(100, 200, 255))

			-- Only show plan if it's a new plan or significant progress
			if current == 1 or current == total then
				messageOrder += 1
				local planFrame = Instance.new("Frame")
				planFrame.Size = UDim2.new(1, -16, 0, 0)
				planFrame.AutomaticSize = Enum.AutomaticSize.Y
				planFrame.Position = UDim2.new(0, 8, 0, 0)
				planFrame.BackgroundColor3 = Color3.fromRGB(35, 50, 65)
				planFrame.BorderSizePixel = 0
				planFrame.LayoutOrder = messageOrder
				planFrame.Parent = chatScroll

				local planCorner = Instance.new("UICorner")
				planCorner.CornerRadius = UDim.new(0, 3)
				planCorner.Parent = planFrame

				local planPadding = Instance.new("UIPadding")
				planPadding.PaddingLeft = UDim.new(0, 6)
				planPadding.PaddingRight = UDim.new(0, 6)
				planPadding.PaddingTop = UDim.new(0, 4)
				planPadding.PaddingBottom = UDim.new(0, 4)
				planPadding.Parent = planFrame

				local planText = planStatus .. ": " .. table.concat(response.plan.steps, " → ")

				local planLabel = Instance.new("TextLabel")
				planLabel.Size = UDim2.new(1, 0, 0, 0)
				planLabel.AutomaticSize = Enum.AutomaticSize.Y
				planLabel.BackgroundTransparency = 1
				planLabel.TextColor3 = Color3.fromRGB(180, 200, 220)
				planLabel.Text = planText
				planLabel.TextWrapped = true
				planLabel.TextXAlignment = Enum.TextXAlignment.Left
				planLabel.Font = Enum.Font.SourceSansItalic
				planLabel.TextSize = 11
				planLabel.Parent = planFrame
			end
		end

		addMessage(response.message, false)

		if response.actions and #response.actions > 0 then
			-- Add "Apply All" button at the top
			if #response.actions >= 1 then
				messageOrder += 1
				local applyAllFrame = Instance.new("Frame")
				applyAllFrame.Size = UDim2.new(1, -16, 0, 32)
				applyAllFrame.Position = UDim2.new(0, 8, 0, 0)
				applyAllFrame.BackgroundTransparency = 1
				applyAllFrame.LayoutOrder = messageOrder
				applyAllFrame.Parent = chatScroll

				local applyAllBtn = Instance.new("TextButton")
				applyAllBtn.Size = UDim2.new(0, 140, 0, 28)
				applyAllBtn.Position = UDim2.new(0, 0, 0, 0)
				applyAllBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 80)
				applyAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				applyAllBtn.Text = "✓ Apply All Actions"
				applyAllBtn.Font = Enum.Font.SourceSansBold
				applyAllBtn.TextSize = 13
				applyAllBtn.Parent = applyAllFrame

				local applyAllCorner = Instance.new("UICorner")
				applyAllCorner.CornerRadius = UDim.new(0, 4)
				applyAllCorner.Parent = applyAllBtn

				applyAllBtn.MouseButton1Click:Connect(function()
					applyAllBtn.Text = "Applying..."
					applyAllBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
					updateStatus("Applying all...", Color3.fromRGB(100, 200, 255))

					for _, action in ipairs(response.actions) do
						local results = ActionExecutor.execute({action})
						for _, r in ipairs(results) do
							if not r:match("^ERROR:") then
								table.insert(actionsCompleted, ActionExecutor.describe(action))
							else
								addDebug(r)
							end
						end
					end

					applyAllFrame:Destroy()
					-- Clear individual action buttons
					for _, child in ipairs(chatScroll:GetChildren()) do
						if child.Name == "ActionButtonFrame" then
							child:Destroy()
						end
					end

					showTaskSummary(response.plan)
					updateStatus("Ready", Color3.fromRGB(100, 200, 100))
				end)
			end

			-- Show compact action list
			messageOrder += 1
			local actionListFrame = Instance.new("Frame")
			actionListFrame.Size = UDim2.new(1, -16, 0, 0)
			actionListFrame.AutomaticSize = Enum.AutomaticSize.Y
			actionListFrame.Position = UDim2.new(0, 8, 0, 0)
			actionListFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
			actionListFrame.BorderSizePixel = 0
			actionListFrame.LayoutOrder = messageOrder
			actionListFrame.Parent = chatScroll

			local actionCorner = Instance.new("UICorner")
			actionCorner.CornerRadius = UDim.new(0, 3)
			actionCorner.Parent = actionListFrame

			local actionPadding = Instance.new("UIPadding")
			actionPadding.PaddingLeft = UDim.new(0, 6)
			actionPadding.PaddingRight = UDim.new(0, 6)
			actionPadding.PaddingTop = UDim.new(0, 4)
			actionPadding.PaddingBottom = UDim.new(0, 4)
			actionPadding.Parent = actionListFrame

			local actionText = ""
			for i, action in ipairs(response.actions) do
				local desc = ActionExecutor.describe(action)
				actionText = actionText .. i .. ". " .. desc .. "\n"
			end

			local actionLabel = Instance.new("TextLabel")
			actionLabel.Size = UDim2.new(1, 0, 0, 0)
			actionLabel.AutomaticSize = Enum.AutomaticSize.Y
			actionLabel.BackgroundTransparency = 1
			actionLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
			actionLabel.Text = actionText
			actionLabel.TextWrapped = true
			actionLabel.TextXAlignment = Enum.TextXAlignment.Left
			actionLabel.Font = Enum.Font.SourceSans
			actionLabel.TextSize = 12
			actionLabel.Parent = actionListFrame

			-- Show task summary after all actions processed
			if #actionsCompleted > 0 or #response.actions > 0 then
				showTaskSummary(response.plan)
			end
		else
			-- No actions - check if there's a plan that might continue
			local hasActivePlan = response.plan and response.plan.current_step and response.plan.total_steps
				and response.plan.current_step < response.plan.total_steps

			messageOrder += 1
			local btnFrame = Instance.new("Frame")
			btnFrame.Size = UDim2.new(1, -16, 0, 36)
			btnFrame.Position = UDim2.new(0, 8, 0, 0)
			btnFrame.BackgroundTransparency = 1
			btnFrame.LayoutOrder = messageOrder
			btnFrame.Parent = chatScroll

			if hasActivePlan then
				-- Show continue button for plan
				local continueBtn = Instance.new("TextButton")
				continueBtn.Size = UDim2.new(0, 140, 0, 30)
				continueBtn.Position = UDim2.new(0, 0, 0, 0)
				continueBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 80)
				continueBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				continueBtn.Text = "Continue Next Step"
				continueBtn.Font = Enum.Font.SourceSansBold
				continueBtn.TextSize = 14
				continueBtn.Parent = btnFrame

				local btnCorner = Instance.new("UICorner")
				btnCorner.CornerRadius = UDim.new(0, 4)
				btnCorner.Parent = continueBtn

				continueBtn.MouseButton1Click:Connect(function()
					inputBox.Text = "continue"
					sendMessage()
				end)
			else
				-- No plan, show new task button
				local newTaskBtn = Instance.new("TextButton")
				newTaskBtn.Size = UDim2.new(0, 120, 0, 30)
				newTaskBtn.Position = UDim2.new(0, 0, 0, 0)
				newTaskBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
				newTaskBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				newTaskBtn.Text = "Start New Task"
				newTaskBtn.Font = Enum.Font.SourceSansBold
				newTaskBtn.TextSize = 14
				newTaskBtn.Parent = btnFrame

				local btnCorner = Instance.new("UICorner")
				btnCorner.CornerRadius = UDim.new(0, 4)
				btnCorner.Parent = newTaskBtn

				newTaskBtn.MouseButton1Click:Connect(function()
					resetChat()
				end)
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

newChatButton.MouseButton1Click:Connect(function()
	if not isProcessing then
		resetChat()
	end
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

-- Build script index for semantic search
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
