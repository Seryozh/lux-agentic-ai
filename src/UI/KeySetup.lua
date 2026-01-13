--[[
    UI/KeySetup.lua
    API Key Setup Modal and Settings Screen for BYOK (Bring Your Own Key) flow
]]

local Constants = require(script.Parent.Parent.Constants)
local Create = require(script.Parent.Create)

local KeySetup = {}

-- Store reference to current modal for cleanup
local currentModal = nil

-- ============================================================================
-- KEY INPUT SCREEN (Initial setup or key change)
-- ============================================================================

--[[
    Show the API key input screen
    @param parent Instance - Parent widget to attach modal to
    @param onSuccess function - Callback when key is validated (receives credits table)
    @param showBackButton boolean - Whether to show back button (for settings flow)
    @param onBack function - Callback when back button is pressed
    @return Frame - The modal frame
]]
local function showKeyInput(parent, onSuccess, showBackButton, onBack)
	-- Full-screen modal overlay
	local modal = Create.new("Frame", {
		Name = "KeySetupModal",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(20, 20, 25),
		BorderSizePixel = 0,
		ZIndex = 100,
		Parent = parent
	})

	currentModal = modal

	-- Center container
	local container = Create.new("Frame", {
		Name = "Container",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -40, 0, 420),
		BackgroundTransparency = 1,
		Parent = modal
	})

	Create.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 16),
		Parent = container
	})

	-- Back button (only in settings flow)
	if showBackButton then
		local backButton = Create.new("TextButton", {
			Name = "BackButton",
			Size = UDim2.new(0, 100, 0, 32),
			BackgroundColor3 = Constants.COLORS.backgroundLight,
			Text = "? Back",
			TextColor3 = Constants.COLORS.textSecondary,
			Font = Constants.UI.FONT_NORMAL,
			TextSize = 14,
			LayoutOrder = 0,
			Parent = container
		})

		Create.new("UICorner", {
			CornerRadius = UDim.new(0, 8),
			Parent = backButton
		})

		backButton.MouseButton1Click:Connect(function()
			if onBack then
				onBack()
			end
		end)
	end

	-- Logo/Title
	local title = Create.new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = showBackButton and "Update API Key" or "Welcome to Lux!",
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_HEADER,
		TextSize = 24,
		LayoutOrder = 1,
		Parent = container
	})

	-- Subtitle
	local subtitle = Create.new("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "Enter your OpenRouter API key to get started.\nYour key is stored securely on your computer.",
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 14,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = container
	})

	-- Input container
	local inputContainer = Create.new("Frame", {
		Name = "InputContainer",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		LayoutOrder = 3,
		Parent = container
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = inputContainer
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = inputContainer
	})

	-- API Key input
	local keyInput = Create.new("TextBox", {
		Name = "KeyInput",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "sk-or-v1-...",
		PlaceholderColor3 = Constants.COLORS.textMuted,
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Enum.Font.Code,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = inputContainer
	})

	-- Error message
	local errorLabel = Create.new("TextLabel", {
		Name = "ErrorLabel",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Constants.COLORS.accentError,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 12,
		TextWrapped = true,
		LayoutOrder = 4,
		Parent = container
	})

	-- Button container
	local buttonContainer = Create.new("Frame", {
		Name = "ButtonContainer",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = container
	})

	Create.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		Parent = buttonContainer
	})

	-- Get Key button (opens browser)
	local getKeyButton = Create.new("TextButton", {
		Name = "GetKeyButton",
		Size = UDim2.new(0, 140, 0, 44),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		Text = "Get Free Key",
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 14,
		Parent = buttonContainer
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = getKeyButton
	})

	-- Validate button
	local validateButton = Create.new("TextButton", {
		Name = "ValidateButton",
		Size = UDim2.new(0, 140, 0, 44),
		BackgroundColor3 = Constants.COLORS.accentPrimary,
		Text = "Validate & Save",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Constants.UI.FONT_HEADER,
		TextSize = 14,
		Parent = buttonContainer
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = validateButton
	})

	-- Help text
	local helpText = Create.new("TextLabel", {
		Name = "HelpText",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		Text = "Need help? Visit openrouter.ai/keys to create your API key.\nAdd credits at openrouter.ai before using Lux.",
		TextColor3 = Constants.COLORS.textMuted,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 12,
		TextWrapped = true,
		LayoutOrder = 6,
		Parent = container
	})

	-- State
	local isValidating = false

	-- Get Key button handler
	getKeyButton.MouseButton1Click:Connect(function()
		-- Copy URL to clipboard instruction
		errorLabel.Text = "Visit: openrouter.ai/keys"
		errorLabel.TextColor3 = Constants.COLORS.accentPrimary
	end)

	-- Validation function (extracted to avoid code duplication)
	local function performValidation()
		if isValidating then return end

		local key = keyInput.Text:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace

		if key == "" then
			errorLabel.Text = "Please enter your API key"
			errorLabel.TextColor3 = Constants.COLORS.accentError
			return
		end

		if not key:match("^sk%-or%-") then
			errorLabel.Text = "Key should start with 'sk-or-'"
			errorLabel.TextColor3 = Constants.COLORS.accentError
			return
		end

		-- Start validation
		isValidating = true
		validateButton.Text = "Validating..."
		validateButton.BackgroundColor3 = Constants.COLORS.buttonDisabled
		errorLabel.Text = ""

		-- Validate in background
		task.spawn(function()
			local OpenRouterClient = require(script.Parent.Parent.OpenRouterClient)

			local result = OpenRouterClient.validateApiKey(key)

			if result.valid then
				-- Save the key
				OpenRouterClient.saveApiKey(key)

				-- Show success
				errorLabel.Text = string.format("Success! Balance: $%.2f", result.credits.remaining)
				errorLabel.TextColor3 = Constants.COLORS.accentSuccess
				validateButton.Text = "Saved!"
				validateButton.BackgroundColor3 = Constants.COLORS.accentSuccess

				-- Wait a moment then close
				task.wait(1)

				if currentModal then
					currentModal:Destroy()
					currentModal = nil
				end

				if onSuccess then
					onSuccess(result.credits)
				end
			else
				-- Show error
				errorLabel.Text = result.error or "Validation failed"
				errorLabel.TextColor3 = Constants.COLORS.accentError
				validateButton.Text = "Validate & Save"
				validateButton.BackgroundColor3 = Constants.COLORS.accentPrimary
				isValidating = false
			end
		end)
	end

	-- Validate button handler
	validateButton.MouseButton1Click:Connect(function()
		performValidation()
	end)

	-- Enter key to validate
	keyInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			performValidation()
		end
	end)

	return modal
end

-- ============================================================================
-- SETTINGS SCREEN (Model selection + key change)
-- ============================================================================

--[[
    Show the settings screen with model selection
    @param parent Instance - Parent widget to attach modal to
    @param onClose function - Callback when settings are closed
    @param getCurrentModel function - Returns current model ID
    @param setModel function - Called with new model ID when changed
    @return Frame - The modal frame
]]
local function showSettings(parent, onClose, getCurrentModel, setModel)
	-- Full-screen modal overlay
	local modal = Create.new("Frame", {
		Name = "SettingsModal",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(20, 20, 25),
		BorderSizePixel = 0,
		ZIndex = 100,
		Parent = parent
	})

	currentModal = modal

	-- Scroll frame for content
	local scrollFrame = Create.new("ScrollingFrame", {
		Name = "ScrollFrame",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Constants.COLORS.textMuted,
		CanvasSize = UDim2.new(0, 0, 0, 500),
		Parent = modal
	})

	-- Container
	local container = Create.new("Frame", {
		Name = "Container",
		Size = UDim2.new(1, -40, 0, 480),
		Position = UDim2.new(0, 20, 0, 20),
		BackgroundTransparency = 1,
		Parent = scrollFrame
	})

	Create.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 16),
		Parent = container
	})

	-- Header with back button
	local headerContainer = Create.new("Frame", {
		Name = "HeaderContainer",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = container
	})

	local backButton = Create.new("TextButton", {
		Name = "BackButton",
		Size = UDim2.new(0, 80, 0, 36),
		Position = UDim2.new(0, 0, 0.5, -18),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		Text = "? Back",
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 14,
		Parent = headerContainer
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = backButton
	})

	local titleLabel = Create.new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "Settings",
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_HEADER,
		TextSize = 22,
		Parent = headerContainer
	})

	-- Model Selection Section
	local modelSection = Create.new("Frame", {
		Name = "ModelSection",
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = container
	})

	Create.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 12),
		Parent = modelSection
	})

	local modelSectionTitle = Create.new("TextLabel", {
		Name = "SectionTitle",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = "AI Model",
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_HEADER,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = modelSection
	})

	-- Current model state
	local currentModelId = getCurrentModel and getCurrentModel() or Constants.OPENROUTER_MODEL
	local selectedModelButton = nil

	-- Create model option buttons
	for i, modelInfo in ipairs(Constants.AVAILABLE_MODELS) do
		local isSelected = modelInfo.id == currentModelId

		local modelCard = Create.new("Frame", {
			Name = "ModelCard_" .. modelInfo.id,
			Size = UDim2.new(1, 0, 0, 70),
			BackgroundColor3 = isSelected and Constants.COLORS.accentPrimary or Constants.COLORS.backgroundLight,
			LayoutOrder = i + 1,
			Parent = modelSection
		})

		Create.new("UICorner", {
			CornerRadius = UDim.new(0, 8),
			Parent = modelCard
		})

		Create.new("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			Parent = modelCard
		})

		-- Model name + default badge
		local nameText = modelInfo.name
		if modelInfo.isDefault then
			nameText = nameText .. " (Default)"
		end

		local modelName = Create.new("TextLabel", {
			Name = "ModelName",
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
			Text = nameText,
			TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Constants.COLORS.textPrimary,
			Font = Constants.UI.FONT_HEADER,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = modelCard
		})

		local modelDesc = Create.new("TextLabel", {
			Name = "ModelDesc",
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = modelInfo.description,
			TextColor3 = isSelected and Color3.fromRGB(220, 220, 255) or Constants.COLORS.textSecondary,
			Font = Constants.UI.FONT_NORMAL,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = modelCard
		})

		local modelPricing = Create.new("TextLabel", {
			Name = "ModelPricing",
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 0, 38),
			BackgroundTransparency = 1,
			Text = modelInfo.pricing,
			TextColor3 = isSelected and Color3.fromRGB(180, 180, 255) or Constants.COLORS.textMuted,
			Font = Constants.UI.FONT_NORMAL,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = modelCard
		})

		-- Click handler
		local clickButton = Create.new("TextButton", {
			Name = "ClickArea",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			Parent = modelCard
		})

		if isSelected then
			selectedModelButton = modelCard
		end

		clickButton.MouseButton1Click:Connect(function()
			-- Deselect previous
			if selectedModelButton and selectedModelButton ~= modelCard then
				selectedModelButton.BackgroundColor3 = Constants.COLORS.backgroundLight
				for _, child in ipairs(selectedModelButton:GetChildren()) do
					if child:IsA("TextLabel") then
						if child.Name == "ModelName" then
							child.TextColor3 = Constants.COLORS.textPrimary
						elseif child.Name == "ModelDesc" then
							child.TextColor3 = Constants.COLORS.textSecondary
						elseif child.Name == "ModelPricing" then
							child.TextColor3 = Constants.COLORS.textMuted
						end
					end
				end
			end

			-- Select this one
			modelCard.BackgroundColor3 = Constants.COLORS.accentPrimary
			modelName.TextColor3 = Color3.fromRGB(255, 255, 255)
			modelDesc.TextColor3 = Color3.fromRGB(220, 220, 255)
			modelPricing.TextColor3 = Color3.fromRGB(180, 180, 255)
			selectedModelButton = modelCard

			-- Update model
			currentModelId = modelInfo.id
			if setModel then
				setModel(modelInfo.id)
			end
		end)
	end

	-- API Key Section
	local keySection = Create.new("Frame", {
		Name = "KeySection",
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = container
	})

	Create.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 12),
		Parent = keySection
	})

	local keySectionTitle = Create.new("TextLabel", {
		Name = "SectionTitle",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = "API Key",
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_HEADER,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = keySection
	})

	local changeKeyButton = Create.new("TextButton", {
		Name = "ChangeKeyButton",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		Text = "Change API Key",
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 14,
		LayoutOrder = 2,
		Parent = keySection
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = changeKeyButton
	})

	-- Event handlers
	backButton.MouseButton1Click:Connect(function()
		if currentModal then
			currentModal:Destroy()
			currentModal = nil
		end
		if onClose then
			onClose()
		end
	end)

	changeKeyButton.MouseButton1Click:Connect(function()
		-- Destroy current modal
		if currentModal then
			currentModal:Destroy()
			currentModal = nil
		end

		-- Show key input with back button
		showKeyInput(parent, function(credits)
			-- After key is saved, go back to settings
			showSettings(parent, onClose, getCurrentModel, setModel)
		end, true, function()
			-- Back button pressed, go back to settings
			showSettings(parent, onClose, getCurrentModel, setModel)
		end)
	end)

	-- Update canvas size
	local totalHeight = 40 + 16 + 200 + 16 + 80 + 40
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)

	return modal
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Show the API key setup modal (for initial setup)
    @param parent Instance - Parent widget to attach modal to
    @param onSuccess function - Callback when key is validated (receives credits table)
    @return Frame - The modal frame
]]
function KeySetup.show(parent, onSuccess)
	-- Clean up existing modal if any
	if currentModal then
		currentModal:Destroy()
		currentModal = nil
	end

	return showKeyInput(parent, onSuccess, false, nil)
end

--[[
    Show the settings screen (for model selection and key update)
    @param parent Instance - Parent widget to attach modal to
    @param onClose function - Callback when settings are closed
    @param getCurrentModel function - Returns current model ID
    @param setModel function - Called with new model ID when changed
    @return Frame - The modal frame
]]
function KeySetup.showSettings(parent, onClose, getCurrentModel, setModel)
	print("[Lux] KeySetup.showSettings called") -- Debug

	-- Clean up existing modal if any
	if currentModal then
		currentModal:Destroy()
		currentModal = nil
	end

	return showSettings(parent, onClose, getCurrentModel, setModel)
end

--[[
    Hide and destroy the setup modal
]]
function KeySetup.hide()
	if currentModal then
		currentModal:Destroy()
		currentModal = nil
	end
end

--[[
    Check if modal is currently showing
    @return boolean
]]
function KeySetup.isShowing()
	return currentModal ~= nil and currentModal.Parent ~= nil
end

return KeySetup
