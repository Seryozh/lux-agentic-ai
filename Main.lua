--[[
    Main.lua - Lux Plugin Entry Point (v1.1.0)

    Features:
    - OpenRouter BYOK (Bring Your Own Key) integration
    - Agentic AI chat with tool calling
    - Robust error handling
    - Debug logging for development
]]

-- Services
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- ============================================================================
-- SAFE MODULE LOADING WITH FALLBACK ERROR UI
-- ============================================================================

local success, loadError = pcall(function()
	-- Modules
	local src = script:FindFirstChild("src") or script.Parent:FindFirstChild("src")
	if not src then
		error("[Lux] Cannot find 'src' folder. Make sure the plugin structure is correct:\nLux/\n  Main (Script)\n  src/ (Folder)")
	end

	-- Validate critical modules exist before requiring
	local function validateModule(parent, moduleName)
		local module = parent:FindFirstChild(moduleName)
		if not module then
			error(string.format("[Lux] Cannot find module '%s' in '%s'. Plugin structure may be corrupted.", moduleName, parent:GetFullName()))
		end
		if not module:IsA("ModuleScript") and not module:IsA("Folder") then
			error(string.format("[Lux] '%s' is not a ModuleScript or Folder (found %s). Plugin structure may be corrupted.", moduleName, module.ClassName))
		end

		-- If it's a folder, verify it has an init ModuleScript
		if module:IsA("Folder") then
			local initModule = module:FindFirstChild("init")
			if not initModule then
				error(string.format("[Lux] Folder '%s' is missing 'init' ModuleScript. Found children: %s",
					moduleName,
					table.concat((function()
						local names = {}
						for _, child in ipairs(module:GetChildren()) do
							table.insert(names, child.Name .. " (" .. child.ClassName .. ")")
						end
						return names
					end)(), ", ")))
			end
			if not initModule:IsA("ModuleScript") then
				error(string.format("[Lux] Folder '%s' has 'init' but it's not a ModuleScript (found %s)", moduleName, initModule.ClassName))
			end
		end

		return module
	end

	validateModule(src, "Shared")
	validateModule(src, "OpenRouterClient")
	validateModule(src, "Tools")
	validateModule(src, "UI")

	return {
		Constants = require(src.Shared.Constants),
		Utils = require(src.Shared.Utils),
		IndexManager = require(src.Shared.IndexManager),
		OpenRouterClient = require(src.OpenRouterClient),
		Tools = require(src.Tools),
		Builder = require(src.UI.Builder),
		ChatRenderer = require(src.UI.ChatRenderer),
		InputApproval = require(src.UI.InputApproval),
		UserFeedback = require(src.UI.UserFeedback),
		KeySetup = require(src.UI.KeySetup),
	}
end)

if not success then
	-- CRITICAL ERROR: Show error toolbar and stop
	warn("[Lux] CRITICAL ERROR during module loading:")
	warn(loadError)

	local toolbar = plugin:CreateToolbar("Lux AI")
	local button = toolbar:CreateButton(
		"Lux Error",
		"Plugin failed to load - click for details",
		"rbxasset://textures/ui/ErrorIcon.png",
		"Error"
	)

	button.Click:Connect(function()
		local errorMsg = string.format([[Lux Plugin Failed to Load

Error: %s

This usually happens if:
1. The plugin was not installed correctly
2. Plugin files are corrupted
3. A recent update broke compatibility

Try:
1. Reinstall the plugin from Roblox Creator Store
2. Check Output window for full error details
3. Report this issue to the developer]], loadError)

		warn(errorMsg)
	end)

	return -- Stop execution
end

-- Unpack loaded modules
local Constants = success.Constants
local Utils = success.Utils
local IndexManager = success.IndexManager
local OpenRouterClient = success.OpenRouterClient
local Tools = success.Tools
local Builder = success.Builder
local ChatRenderer = success.ChatRenderer
local InputApproval = success.InputApproval
local UserFeedback = success.UserFeedback
local KeySetup = success.KeySetup

if Constants.DEBUG then
	print("[Lux DEBUG] Loading plugin v" .. Constants.PLUGIN_VERSION)
end

-- Initialize OpenRouterClient with plugin instance (for secure settings)
OpenRouterClient.init(plugin)

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

local state = {
	sessionId = HttpService:GenerateGUID(false),
	scripts = {},
	status = "idle", -- idle | scanning | ready | chatting | error | empty | needs_key
	errorMessage = nil,
	widget = nil,

	-- Chat state
	chatEnabled = false,
	chatMessages = {}, -- {role: "user"|"assistant"|"system", text: string, changes: table}
	pendingChanges = nil, -- Code changes waiting for user approval
	isProcessing = false, -- True while AI is thinking
	lastMessageTime = 0, -- For rate limiting

	-- Credit balance
	creditBalance = nil,

	-- UI elements
	ui = {}
}

-- ============================================================================
-- TOOLBAR & WIDGET SETUP
-- ============================================================================

local toolbar = plugin:CreateToolbar(Constants.PLUGIN_NAME)
local button = toolbar:CreateButton(
	Constants.PLUGIN_NAME,
	"Open Lux - AI Coding Assistant",
	"rbxassetid://118528628257442",
	"Lux Assistant"
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, -- initially disabled
	false, -- override previous state
	Constants.UI.WIDGET_DEFAULT_WIDTH,
	Constants.UI.WIDGET_DEFAULT_HEIGHT,
	Constants.UI.WIDGET_MIN_WIDTH,
	Constants.UI.WIDGET_MIN_HEIGHT
)

state.widget = plugin:CreateDockWidgetPluginGui("Lux", widgetInfo)
state.widget.Title = string.format("%s v%s", Constants.PLUGIN_NAME, Constants.PLUGIN_VERSION)
state.widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- Fix for ZIndex issues

-- ============================================================================
-- UI CREATION
-- ============================================================================

-- Create UI using Builder module
local buttons = Builder.createUI(state.widget, state)

-- ============================================================================
-- STATUS UI UPDATE
-- ============================================================================

local function updateStatusUI()
	local statusText = ""

	if state.status == "needs_key" then
		statusText = [[?? <b>API Key Required</b>

Please enter your OpenRouter API key to get started.]]
		state.ui.statusPanel.BackgroundColor3 = Constants.COLORS.backgroundLight

	elseif state.status == "scanning" then
		statusText = "?? <b>Scanning scripts...</b>"

	elseif state.status == "error" then
		local breakdown = {}
		for location, count in pairs(state.errorBreakdown or {}) do
			table.insert(breakdown, string.format("- %s: %d", location, count))
		end
		statusText = string.format([[? <b>Too Many Scripts</b>

Found %d scripts, but LuaVibe supports maximum %d.

Please reduce the number of scripts in your game.

Scripts found in:
%s]], #state.scripts, Constants.MAX_SCRIPTS, table.concat(breakdown, "\n"))
		state.ui.statusPanel.BackgroundColor3 = Color3.fromRGB(60, 30, 30)

	elseif state.status == "empty" then
		statusText = [[?? <b>No Scripts Yet</b>

Your game has no scripts yet - that's perfectly fine!

Start chatting with the AI to create scripts, or add them manually.]]
		state.ui.statusPanel.BackgroundColor3 = Constants.COLORS.backgroundLight

		-- Enable chat immediately even with 0 scripts
		if not state.chatEnabled then
			state.chatEnabled = true
			state.ui.chatContainer.Visible = true
			state.ui.statusPanel.Size = UDim2.new(1, 0, 0, 80)
		end

	elseif state.status == "ready" or state.status == "chatting" then
		local scriptCount = #state.scripts
		if scriptCount == 0 then
			statusText = [[? <b>Ready to Chat!</b>

No scripts found. Ask the AI to help you create scripts for your game!]]
		else
			statusText = string.format([[? <b>Ready to Chat!</b>

Found %d scripts. Ask questions, request code changes, or get help with your game!]], scriptCount)
		end
		state.ui.statusPanel.BackgroundColor3 = Constants.COLORS.backgroundLight

		-- Show chat UI
		if not state.chatEnabled then
			state.chatEnabled = true
			state.ui.chatContainer.Visible = true
			state.ui.statusPanel.Size = UDim2.new(1, 0, 0, 80) -- Make status panel smaller
		end
	end

	state.ui.statusLabel.Text = statusText
end

local function updateTokenUI()
	if not state.ui.tokenStatusLabel then
		return
	end

	local usage = OpenRouterClient.getTokenUsage()

	-- Show cost-focused display
	local balanceText = ""
	if state.creditBalance then
		balanceText = string.format(" | Balance: $%.4f", state.creditBalance.remaining)
	end

	-- Token counter for compression
	local estTokens = OpenRouterClient.estimateTokenCount()
	local tokenLimit = Constants.COMPRESSION_THRESHOLD or 50000
	local tokensUntil = math.max(0, tokenLimit - estTokens)

	state.ui.tokenStatusLabel.Text = string.format(
		"?? Session: $%.4f%s | ?? Compress in: %d tokens",
		usage.totalCost,
		balanceText,
		tokensUntil
	)
end

-- ============================================================================
-- CORE FUNCTIONS
-- ============================================================================

local function scanAndUpdateUI()
	if Constants.DEBUG then
		print("[Lux DEBUG] Scanning scripts...")
	end

	state.status = "scanning"
	updateStatusUI()

	local result = IndexManager.scanScripts()
	state.scripts = result.scripts

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Found %d scripts", result.totalCount))
	end

	if result.totalCount > Constants.MAX_SCRIPTS then
		state.status = "error"
		state.errorBreakdown = result.breakdown
		warn(string.format("[Lux] ERROR: Too many scripts (%d > %d)", result.totalCount, Constants.MAX_SCRIPTS))
	elseif result.totalCount == 0 then
		state.status = "empty"
	else
		state.status = "ready"
	end

	updateStatusUI()
end

--[[
    Check API configuration and show key setup if needed
    @return boolean - true if API is configured
]]
local function checkAndSetupAPI()
	local isConfigured, errorMsg = OpenRouterClient.checkConfiguration()

	if not isConfigured then
		if Constants.DEBUG then
			print("[Lux DEBUG] API not configured: " .. (errorMsg or "unknown"))
		end

		-- Show key setup modal
		state.status = "needs_key"
		updateStatusUI()

		KeySetup.show(state.ui.mainFrame, function(credits)
			-- Key saved successfully
			if Constants.DEBUG then
				print(string.format("[Lux DEBUG] API key saved, balance: $%.2f", credits.remaining))
			end

			state.creditBalance = credits

			-- Check for low balance warning
			if credits.remaining < Constants.LOW_BALANCE_WARNING then
				ChatRenderer.addMessage(state, "system",
					string.format("?? Low balance: $%.2f remaining. Add credits at openrouter.ai",
						credits.remaining))
			end

			-- Continue with normal startup
			scanAndUpdateUI()
			OpenRouterClient.onSessionStart()
			updateTokenUI()
		end)

		return false
	end

	return true
end

--[[
    Fetch and update credit balance
]]
local function refreshCreditBalance()
	task.spawn(function()
		local credits = OpenRouterClient.getCredits()
		if credits then
			state.creditBalance = credits
			updateTokenUI()

			-- Check for low balance warning
			if credits.remaining < Constants.LOW_BALANCE_WARNING then
				ChatRenderer.addMessage(state, "system",
					string.format("?? Low balance: $%.2f remaining. Add credits at openrouter.ai",
						credits.remaining))
			end
		end
	end)
end

--[[
    Split message text by "thought pivots" (Wait, Actually, etc.)
    @param text string - The text to split
    @return table - Array of string parts
]]
local function splitByThoughtPivots(text)
	local parts = {}
	local currentPart = ""

	-- Split by newlines first to analyze paragraphs
	-- This handles the most common case of "thinking blocks"
	for line in text:gmatch("([^\n]*)\n?") do
		if line == "" then 
			currentPart = currentPart .. "\n"
			-- continue
		else
			local trimmed = line:gsub("^%s+", "")
			local lower = trimmed:lower()

			-- Pivot keywords that suggest a change in direction
			local isPivot = false
			if lower:match("^wait%W") or lower:match("^wait$") then isPivot = true end
			if lower:match("^actually%W") or lower:match("^actually$") then isPivot = true end
			if lower:match("^hold on%W") or lower:match("^hold on$") then isPivot = true end
			if lower:match("^correction%W") or lower:match("^correction$") then isPivot = true end
			if lower:match("^on second thought") then isPivot = true end

			if isPivot and currentPart:gsub("%s", "") ~= "" then
				-- Push current part if it has content
				table.insert(parts, currentPart)
				currentPart = line .. "\n"
			else
				currentPart = currentPart .. line .. "\n"
			end
		end
	end

	if currentPart:gsub("%s", "") ~= "" then
		table.insert(parts, currentPart)
	end

	-- Filter out empty parts and trim trailing newlines
	local finalParts = {}
	for _, p in ipairs(parts) do
		local trimmed = p:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			table.insert(finalParts, trimmed)
		end
	end

	if #finalParts == 0 and text ~= "" then
		return {text}
	end

	return finalParts
end

--[[
    Handle approval flow - shows inline approval prompt and resumes loop
    Now uses collapsible system groups for batched approvals
    @param operation table - Operation awaiting approval
]]
local function handleApproval(operation)
	-- Get input container
	local inputContainer = state.ui.mainFrame:FindFirstChild("ChatContainer"):FindFirstChild("InputContainer")

	if not inputContainer then
		warn("[Lux] Could not find InputContainer for approval prompt")
		return
	end

	-- Start a collapsible group if this is the first approval (or none exists)
	if not ChatRenderer.hasActiveSystemGroup() then
		-- Determine a good group title based on the operation type
		local groupTitle = "Executing Operations"
		if operation.type == "create_instance" or operation.type == "create_script" then
			local name = (operation.data and operation.data.name) or "items"
			groupTitle = "Creating " .. name
		elseif operation.type == "patch_script" or operation.type == "edit_script" then
			groupTitle = "Modifying Scripts"
		elseif operation.type == "delete_instance" then
			groupTitle = "Deleting Items"
		end
		ChatRenderer.startCollapsibleSystemGroup(state, groupTitle)
	end

	-- Show inline approval prompt
	local approvalPrompt = InputApproval.show(inputContainer, operation, function()
		-- APPROVE callback
		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] User approved: %s", operation.type))
		end

		-- Hide approval prompt
		InputApproval.hide(inputContainer)

		-- Add to collapsible group instead of individual message
		local displayPath = operation.path or (operation.data and operation.data.parent and string.format("%s.%s", operation.data.parent, operation.data.name)) or "?"
		local itemText = string.format("%s %s", operation.type:gsub("_", " "), displayPath)
		ChatRenderer.addCollapsibleSystemItem(itemText, "success")

		-- Record approved operation for completion summary (with defensive nil check)
		if OpenRouterClient.recordToolExecution then
			local description = string.format("%s %s", operation.type:gsub("_", " "), displayPath)
			OpenRouterClient.recordToolExecution(operation.type, description, true)
		end

		-- Resume the agent loop
		local response = OpenRouterClient.resumeWithApproval(true)

		-- Handle response (might be another approval, success, or error)
		handleAgentResponse(response)

	end, function()
		-- DENY callback
		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] User denied: %s", operation.type))
		end

		-- Hide approval prompt
		InputApproval.hide(inputContainer)

		-- Add to collapsible group with error status
		local displayPath = operation.path or (operation.data and operation.data.parent and string.format("%s.%s", operation.data.parent, operation.data.name)) or "?"
		local itemText = string.format("%s %s (denied)", operation.type:gsub("_", " "), displayPath)
		ChatRenderer.addCollapsibleSystemItem(itemText, "error")

		-- Record denied operation for completion summary (with defensive nil check)
		if OpenRouterClient.recordToolExecution then
			local description = string.format("%s %s (denied)", operation.type:gsub("_", " "), displayPath)
			OpenRouterClient.recordToolExecution(operation.type, description, false)
		end

		-- Resume the agent loop with denial
		local response = OpenRouterClient.resumeWithApproval(false)

		-- Handle response
		handleAgentResponse(response)
	end)
end

--[[
    Handle user feedback request - shows verification prompt and resumes loop
    Now uses chat-based verification (rendered in chat history) for better visibility
    @param feedbackRequest table - Feedback request from AI
]]
local function handleUserFeedbackRequest(feedbackRequest)
	-- Show feedback prompt IN THE CHAT (not in input container)
	-- This ensures the verification is always visible and scrolls with chat
	UserFeedback.showInChat(state, feedbackRequest, function(feedbackResponse)
		-- Callback when user responds
		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] User feedback received: %s (positive=%s)", 
				feedbackResponse.feedback or "?", 
				tostring(feedbackResponse.positive)))
		end

		-- Note: Chat-based verification handles its own UI cleanup
		-- No need to call UserFeedback.hide()

		-- Resume the agent loop with user's feedback
		local response = OpenRouterClient.resumeWithFeedback(feedbackResponse)

		-- Handle response (might be another feedback request, approval, success, or error)
		handleAgentResponse(response)
	end)
end

--[[
    Handle agent response - recursive to support multiple sequential approvals/feedbacks
    @param response table - Response from OpenRouterClient.processLoop or resumeWithApproval
]]
function handleAgentResponse(response)
	-- Update token UI after every response
	updateTokenUI()

	if response.awaitingApproval then
		-- Pause detected - show approval prompt
		if Constants.DEBUG then
			print("[Lux DEBUG] Agent paused for approval")
		end

		-- Show AI's planning/reasoning text BEFORE approval prompts
		-- This gives users context about what the AI is doing and why
		if response.thinkingText and response.thinkingText ~= "" then
			-- Only show if we haven't shown this exact text before (avoid duplicates)
			local trimmedText = Utils.trim(response.thinkingText)
			if trimmedText ~= "" and not state.lastShownThinkingText or state.lastShownThinkingText ~= trimmedText then
				state.lastShownThinkingText = trimmedText
				ChatRenderer.addMessage(state, "assistant", trimmedText)
			end
		end

		-- Show inline approval
		handleApproval(response.operation)

	elseif response.awaitingUserFeedback then
		-- AI requested user feedback/verification
		if Constants.DEBUG then
			print("[Lux DEBUG] Agent paused for user feedback")
		end

		-- Persist thinking phase before showing feedback UI
		ChatRenderer.persistThinking(state)

		-- Show AI's context text if any
		if response.thinkingText and response.thinkingText ~= "" then
			local trimmedText = Utils.trim(response.thinkingText)
			if trimmedText ~= "" and not state.lastShownThinkingText or state.lastShownThinkingText ~= trimmedText then
				state.lastShownThinkingText = trimmedText
				ChatRenderer.addMessage(state, "assistant", trimmedText)
			end
		end

		-- Show user feedback request
		handleUserFeedbackRequest(response.feedbackRequest)

	elseif response.success then
		-- Agent completed successfully
		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] Agent completed: %d chars", #(response.text or "")))
		end

		-- Finalize any active system group (collapsible approvals)
		if ChatRenderer.hasActiveSystemGroup() then
			ChatRenderer.finalizeCollapsibleSystemGroup()
		end

		-- Re-enable input
		state.isProcessing = false
		state.ui.sendButton.Text = "Send"
		state.ui.sendButton.BackgroundColor3 = Constants.COLORS.accentPrimary
		state.ui.textInput.TextEditable = true

		-- Show final response
		if response.text and response.text ~= "" then
			local textParts = splitByThoughtPivots(response.text)
			for _, part in ipairs(textParts) do
				ChatRenderer.addMessage(state, "assistant", part)
			end
		end

		-- Show completion summary if there were tool executions (with defensive nil checks)
		if OpenRouterClient.getToolExecutionSummary and ChatRenderer.addCompletionSummary then
			local summary = OpenRouterClient.getToolExecutionSummary()
			if summary and summary.totalTools and summary.totalTools > 0 then
				ChatRenderer.addCompletionSummary(state, summary)
			end
		end

	else
		-- Error
		if Constants.DEBUG then
			print(string.format("[Lux DEBUG] Agent error: %s", response.error or "unknown"))
		end

		-- Finalize any active system group even on error
		if ChatRenderer.hasActiveSystemGroup() then
			ChatRenderer.finalizeCollapsibleSystemGroup()
		end

		-- Re-enable input
		state.isProcessing = false
		state.ui.sendButton.Text = "Send"
		state.ui.sendButton.BackgroundColor3 = Constants.COLORS.accentPrimary
		state.ui.textInput.TextEditable = true

		-- Show error
		ChatRenderer.addMessage(state, "assistant", "? Error: " .. (response.error or "Unknown error"))
		warn("[Lux] Chat error: " .. (response.error or "unknown"))
	end
end

local function sendChatMessage(message)
	if state.isProcessing then
		warn("[Lux] Already processing a message, please wait...")
		return
	end

	-- Rate limiting (edge case #18)
	if Constants.ENABLE_COOLDOWN then
		local now = tick()
		if now - state.lastMessageTime < Constants.CHAT_COOLDOWN_SECONDS then
			warn(string.format("[Lux] Please wait %d seconds between messages", Constants.CHAT_COOLDOWN_SECONDS))
			return
		end
		state.lastMessageTime = now
	end

	-- Validate message (edge case #16)
	message = Utils.trim(message)
	if message == "" then
		return
	end

	if Constants.DEBUG then
		print(string.format("[Lux DEBUG] Sending chat message: %s", message:sub(1, 50)))
	end

	-- Add user message to UI
	ChatRenderer.addMessage(state, "user", message)
	state.ui.textInput.Text = ""

	-- Reset thinking text tracker for new conversation turn
	state.lastShownThinkingText = nil

	-- Disable input while processing (edge case #17)
	state.isProcessing = true
	state.status = "chatting"
	state.ui.sendButton.Text = "..."
	state.ui.sendButton.BackgroundColor3 = Constants.COLORS.buttonDisabled
	state.ui.textInput.TextEditable = false

	-- Send to AI (in background to keep UI responsive)
	task.spawn(function()
		-- Reset tool tracking for new task (with defensive nil checks)
		if OpenRouterClient.resetToolLog then
			OpenRouterClient.resetToolLog()
		elseif Constants.DEBUG then
			warn("[Lux DEBUG] OpenRouterClient.resetToolLog is nil")
		end

		if ChatRenderer.clearToolActivityLog then
			ChatRenderer.clearToolActivityLog()
		elseif Constants.DEBUG then
			warn("[Lux DEBUG] ChatRenderer.clearToolActivityLog is nil")
		end

		-- Show thinking indicator (Priority 2.1)
		ChatRenderer.showThinking(state)

		local response
		if #OpenRouterClient.getConversationHistory() == 0 then
			response = OpenRouterClient.startConversation(message, function(iteration, status)
				ChatRenderer.updateThinkingStatus(iteration,
					status:match("^executing_(.+)") or (status == "thinking" and nil))
			end, ChatRenderer)
		else
			response = OpenRouterClient.continueConversation(message, function(iteration, status)
				ChatRenderer.updateThinkingStatus(iteration,
					status:match("^executing_(.+)") or (status == "thinking" and nil))
			end, ChatRenderer)
		end

		-- Handle response (might pause for approval or feedback)
		-- NOTE: We persist thinking if approval/feedback is pending, hide otherwise
		if response.awaitingApproval or response.awaitingUserFeedback then
			-- Persist the thinking/planning phase as a permanent message
			ChatRenderer.persistThinking(state)
		else
			-- Normal completion - just hide the thinking indicator
			ChatRenderer.hideThinking()
		end

		handleAgentResponse(response)
	end)
end

-- ============================================================================
-- EVENT CONNECTIONS
-- ============================================================================
-- Button click toggles widget
button.Click:Connect(function()
	state.widget.Enabled = not state.widget.Enabled
end)

-- When widget opens, check API key and scan scripts
state.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if state.widget.Enabled then
		-- Check if API key is configured
		if checkAndSetupAPI() then
			-- API is configured, proceed normally
			scanAndUpdateUI()
			OpenRouterClient.onSessionStart()
			refreshCreditBalance()
		end
	end
end)

-- Rescan button
buttons.rescanButton.MouseButton1Click:Connect(function()
	if not state.isProcessing then
		scanAndUpdateUI()
	end
end)

-- Reset Context button (both the original and the header button)
local function performContextReset()
	if not state.isProcessing then
		-- Show confirmation dialog (v4.0 - prevent accidental resets)
		local confirmDialog = plugin:CreateDockWidgetPluginGui(
			"LuxConfirmReset",
			DockWidgetPluginGuiInfo.new(
				Enum.InitialDockState.Float,
				false,  -- initialEnabled
				false,  -- initialEnabledShouldOverrideRestore
				350,    -- floatXSize
				150,    -- floatYSize
				350,    -- minWidth
				150     -- minHeight
			)
		)

		-- Create confirmation UI
		local confirmFrame = Instance.new("Frame")
		confirmFrame.Size = UDim2.new(1, 0, 1, 0)
		confirmFrame.BackgroundColor3 = Constants.COLORS.backgroundDark
		confirmFrame.BorderSizePixel = 0
		confirmFrame.Parent = confirmDialog

		local messageLabel = Instance.new("TextLabel")
		messageLabel.Size = UDim2.new(1, -24, 0, 60)
		messageLabel.Position = UDim2.new(0, 12, 0, 12)
		messageLabel.BackgroundTransparency = 1
		messageLabel.Text = "Reset conversation?\n\nThis will clear all chat history and context. This action cannot be undone."
		messageLabel.TextColor3 = Constants.COLORS.textPrimary
		messageLabel.Font = Enum.Font.Gotham
		messageLabel.TextSize = 14
		messageLabel.TextWrapped = true
		messageLabel.TextXAlignment = Enum.TextXAlignment.Left
		messageLabel.TextYAlignment = Enum.TextYAlignment.Top
		messageLabel.Parent = confirmFrame

		-- Button container
		local buttonContainer = Instance.new("Frame")
		buttonContainer.Size = UDim2.new(1, -24, 0, 36)
		buttonContainer.Position = UDim2.new(0, 12, 1, -48)
		buttonContainer.BackgroundTransparency = 1
		buttonContainer.Parent = confirmFrame

		-- Cancel button
		local cancelButton = Instance.new("TextButton")
		cancelButton.Size = UDim2.new(0.48, 0, 1, 0)
		cancelButton.Position = UDim2.new(0, 0, 0, 0)
		cancelButton.BackgroundColor3 = Constants.COLORS.backgroundLight
		cancelButton.BorderSizePixel = 0
		cancelButton.Text = "Cancel"
		cancelButton.TextColor3 = Constants.COLORS.textPrimary
		cancelButton.Font = Enum.Font.GothamBold
		cancelButton.TextSize = 14
		cancelButton.Parent = buttonContainer

		-- Confirm button
		local confirmButton = Instance.new("TextButton")
		confirmButton.Size = UDim2.new(0.48, 0, 1, 0)
		confirmButton.Position = UDim2.new(0.52, 0, 0, 0)
		confirmButton.BackgroundColor3 = Constants.COLORS.accentError
		confirmButton.BorderSizePixel = 0
		confirmButton.Text = "Reset"
		confirmButton.TextColor3 = Color3.new(1, 1, 1)
		confirmButton.Font = Enum.Font.GothamBold
		confirmButton.TextSize = 14
		confirmButton.Parent = buttonContainer

		-- Button corners
		for _, button in ipairs({cancelButton, confirmButton}) do
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = button
		end

		-- Cancel action
		cancelButton.MouseButton1Click:Connect(function()
			confirmDialog.Enabled = false
			confirmDialog:Destroy()
		end)

		-- Confirm action
		confirmButton.MouseButton1Click:Connect(function()
			confirmDialog.Enabled = false
			confirmDialog:Destroy()

			-- Perform the actual reset
			OpenRouterClient.resetConversation()

			-- Clear chat UI
			for _, message in ipairs(state.ui.chatHistory:GetChildren()) do
				if message:IsA("Frame") then
					message:Destroy()
				end
			end

			-- Reset token tracking UI
			updateTokenUI()

			-- Add system message to confirm
			ChatRenderer.addMessage(state, "system", "✅ Context reset. Starting fresh conversation.")

			if Constants.DEBUG then
				print("[Lux DEBUG] Context reset - conversation history cleared")
			end
		end)

		-- Show dialog
		confirmDialog.Enabled = true
	end
end

buttons.resetContextButton.MouseButton1Click:Connect(performContextReset)

-- Header reset button (always visible during chat)
buttons.headerResetButton.MouseButton1Click:Connect(performContextReset)

-- Settings button (model selection and API key)
buttons.settingsButton.MouseButton1Click:Connect(function()
	if not state.isProcessing then
		-- Show settings screen with model selection
		KeySetup.showSettings(
			state.ui.mainFrame,
			function()
				-- Settings closed - refresh balance
				refreshCreditBalance()
			end,
			function()
				-- Get current model
				return OpenRouterClient.getCurrentModel()
			end,
			function(modelId)
				-- Set new model
				OpenRouterClient.setModel(modelId)

				-- Find model name for display
				local modelName = modelId
				for _, model in ipairs(Constants.AVAILABLE_MODELS) do
					if model.id == modelId then
						modelName = model.name
						break
					end
				end

				ChatRenderer.addMessage(state, "system",
					string.format("?? Switched to %s", modelName))

				if Constants.DEBUG then
					print(string.format("[Lux DEBUG] Model changed to: %s", modelId))
				end
			end
		)
	end
end)

-- Send button
buttons.sendButton.MouseButton1Click:Connect(function()
	if state.chatEnabled and not state.isProcessing then
		sendChatMessage(state.ui.textInput.Text)
	end
end)

-- Enter key to send
buttons.textInput.FocusLost:Connect(function(enterPressed)
	if enterPressed and state.chatEnabled and not state.isProcessing then
		sendChatMessage(state.ui.textInput.Text)
	end
end)

-- Cleanup on unload (edge case #1, #4)
plugin.Unloading:Connect(function()
	if Constants.DEBUG then
		print("[Lux DEBUG] Plugin unloading, cleaning up...")
	end

	-- Clear any pending operations
	state.isProcessing = false
	OpenRouterClient.resetConversation()
	KeySetup.hide()
end)

if Constants.DEBUG then
	print("[Lux DEBUG] Plugin loaded successfully!")
end
print("[Lux] Ready! Click the toolbar button to open.")
