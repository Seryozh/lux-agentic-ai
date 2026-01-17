--[[
    UI/Builder.lua
    Main UI structure creation for Lux plugin
    Enhanced with hover effects and better styling

    Supports two modes:
    - Classic: Single-pane vertical chat (for narrow widgets)
    - Command Center: Three-pane dashboard (for wider widgets)
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Create)
local Components = require(script.Parent.Components)

-- Lazy-load Command Center to avoid circular dependencies
local CommandCenterBuilder = nil

local Builder = {}

--[[
    Add hover effect to a button
    @param button TextButton
    @param normalColor Color3
    @param hoverColor Color3 (optional)
]]
local function addHoverEffect(button, normalColor, hoverColor)
	hoverColor = hoverColor or Color3.new(
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
    Create the classic single-pane UI structure (legacy)
    @param widget DockWidgetPluginGui - The plugin widget container
    @param state table - State table to store UI references
    @return table - { rescanButton, sendButton, textInput }
]]
function Builder.createClassicUI(widget, state)
	-- Main container
	local mainFrame = Create.new("Frame", {
		Name = "MainFrame",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Constants.COLORS.background,
		BorderSizePixel = 0,
		Parent = widget
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, Constants.UI.PADDING),
		PaddingBottom = UDim.new(0, Constants.UI.PADDING),
		PaddingLeft = UDim.new(0, Constants.UI.PADDING),
		PaddingRight = UDim.new(0, Constants.UI.PADDING),
		Parent = mainFrame
	})

	Components.ListLayout({
		Parent = mainFrame
	})

	-- Header container (for title + settings button)
	local headerContainer = Create.new("Frame", {
		Name = "HeaderContainer",
		Size = UDim2.new(1, 0, 0, Constants.UI.HEADER_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = mainFrame
	})

	-- Header title
	local header = Components.TextLabel({
		Name = "Header",
		Size = UDim2.new(1, -70, 1, 0),
		Text = Constants.ICONS.LUX .. " " .. Constants.PLUGIN_NAME,
		Font = Constants.UI.FONT_HEADER,
		TextSize = Constants.UI.FONT_SIZE_HEADER,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = headerContainer
	})

	-- Reset Context button (in header, always visible)
	local headerResetButton = Create.new("TextButton", {
		Name = "HeaderResetButton",
		Size = UDim2.new(0, 30, 0, 30),
		Position = UDim2.new(1, -64, 0.5, -15),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		Text = Constants.ICONS.RESET,
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		Parent = headerContainer
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 6),
		Parent = headerResetButton
	})

	-- Settings button (gear icon)
	local settingsButton = Create.new("TextButton", {
		Name = "SettingsButton",
		Size = UDim2.new(0, 30, 0, 30),
		Position = UDim2.new(1, -30, 0.5, -15),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		Text = Constants.ICONS.SETTINGS,
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		Parent = headerContainer
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 6),
		Parent = settingsButton
	})

	-- Status Panel
	local statusPanel = Components.RoundedPanel({
		Name = "StatusPanel",
		Size = UDim2.new(1, 0, 0, 120),
		LayoutOrder = 2,
		Parent = mainFrame
	}, 12)

	local statusLabel = Components.TextLabel({
		Name = "StatusLabel",
		Size = UDim2.new(1, 0, 1, 0),
		Text = "Ready to scan...",
		RichText = true,
		Parent = statusPanel
	})

	-- Button Container (Rescan + Reset Context)
	local buttonContainer = Create.new("Frame", {
		Name = "ButtonContainer",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = mainFrame
	})

	Components.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		Parent = buttonContainer
	})

	-- Rescan Button
	local rescanButton = Components.Button({
		Name = "RescanButton",
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		Text = Constants.ICONS.REFRESH .. " Rescan",
		TextColor3 = Constants.COLORS.textSecondary,
		TextSize = Constants.UI.FONT_SIZE_SMALL,
		LayoutOrder = 1,
		Parent = buttonContainer
	})

	-- Reset Context Button
	local resetContextButton = Components.Button({
		Name = "ResetContextButton",
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = Constants.COLORS.backgroundLight,
		Text = Constants.ICONS.RESET .. " Reset",
		TextColor3 = Constants.COLORS.textSecondary,
		TextSize = Constants.UI.FONT_SIZE_SMALL,
		LayoutOrder = 2,
		Parent = buttonContainer
	})

	-- Chat Container (hidden initially)
	local chatContainer = Create.new("Frame", {
		Name = "ChatContainer",
		Size = UDim2.new(1, 0, 1, -200),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Visible = false,
		Parent = mainFrame
	})

	Components.ListLayout({
		Parent = chatContainer
	})

	-- Chat history (scrolling) with improved scrollbar styling
	local chatHistoryFrame = Components.ScrollingFrame({
		Name = "ChatHistory",
		Size = UDim2.new(1, 0, 1, -70),
		LayoutOrder = 1,
		ScrollBarThickness = 4, -- Thinner scrollbar
		ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90), -- Subtle color
		ScrollBarImageTransparency = 0.3,
		TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		Parent = chatContainer
	}, 8)

	local chatLayout2 = Components.ListLayout({
		Padding = UDim.new(0, 8),
		Parent = chatHistoryFrame
	})

	-- Input container
	local inputContainer = Components.RoundedPanel({
		Name = "InputContainer",
		Size = UDim2.new(1, 0, 0, 60),
		LayoutOrder = 2,
		Parent = chatContainer
	}, 8)

	Components.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		Parent = inputContainer
	})

	-- Text input
	local textInput = Components.TextInput({
		Name = "TextInput",
		Size = UDim2.new(1, -60, 1, 0),
		PlaceholderText = "Ask about your code...",
		MultiLine = false,
		LayoutOrder = 1,
		Parent = inputContainer
	})

	-- Send button
	local sendButton = Components.Button({
		Name = "SendButton",
		Size = UDim2.new(0, 50, 1, 0),
		Text = "Send",
		Font = Enum.Font.GothamBold,
		TextSize = Constants.UI.FONT_SIZE_SMALL,
		LayoutOrder = 2,
		Parent = inputContainer
	})

	-- Spacer before token bar (to push it down and avoid overlap with approval buttons)
	local spacer = Create.new("Frame", {
		Name = "Spacer",
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		Parent = mainFrame
	})

	-- Token usage status bar (bottom of screen)
	local tokenStatusBar = Create.new("Frame", {
		Name = "TokenStatusBar",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = Constants.COLORS.backgroundDark,
		BorderSizePixel = 0,
		LayoutOrder = 7,
		Parent = mainFrame
	})

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, 4),
		Parent = tokenStatusBar
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = tokenStatusBar
	})

	local tokenStatusLabel = Create.new("TextLabel", {
		Name = "TokenStatusLabel",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = Constants.ICONS.COST .. " Session: $0.0000",
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_MONO,
		TextSize = Constants.UI.FONT_SIZE_SMALL - 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = tokenStatusBar
	})

	-- Store UI references in state
	state.ui = {
		mainFrame = mainFrame,
		statusLabel = statusLabel,
		statusPanel = statusPanel,
		rescanButton = rescanButton,
		resetContextButton = resetContextButton,
		headerResetButton = headerResetButton,
		settingsButton = settingsButton,
		chatContainer = chatContainer,
		chatHistory = chatHistoryFrame,
		chatLayout = chatLayout2,
		textInput = textInput,
		sendButton = sendButton,
		tokenStatusBar = tokenStatusBar,
		tokenStatusLabel = tokenStatusLabel
	}

	-- Add hover effects to all interactive buttons
	addHoverEffect(settingsButton, Constants.COLORS.backgroundLight)
	addHoverEffect(headerResetButton, Constants.COLORS.backgroundLight)
	addHoverEffect(rescanButton, Constants.COLORS.backgroundLight)
	addHoverEffect(resetContextButton, Constants.COLORS.backgroundLight)
	addHoverEffect(sendButton, Constants.COLORS.accentPrimary)

	return {
		rescanButton = rescanButton,
		resetContextButton = resetContextButton,
		headerResetButton = headerResetButton,
		settingsButton = settingsButton,
		sendButton = sendButton,
		textInput = textInput
	}
end

--[[
    Create the main UI structure with automatic mode selection
    Uses Command Center (three-pane) when enabled in config.
    The PaneContainer handles responsive collapsing for narrow widths.

    @param widget DockWidgetPluginGui - The plugin widget container
    @param state table - State table to store UI references
    @return table - Button/input references for event binding
]]
function Builder.createUI(widget, state)
	local cc = Constants.COMMAND_CENTER

	-- Use Command Center if enabled in config
	if cc and cc.enabled then
		-- Lazy-load Command Center builder
		if not CommandCenterBuilder then
			CommandCenterBuilder = require(script.Parent.CommandCenterBuilder)
		end

		state.commandCenterEnabled = true
		return CommandCenterBuilder.createUI(widget, state)
	end

	-- Fall back to classic single-pane layout
	state.commandCenterEnabled = false
	return Builder.createClassicUI(widget, state)
end

--[[
    Check if Command Center mode is enabled for the given state
    @param state table
    @return boolean
]]
function Builder.isCommandCenterEnabled(state)
	return state and state.commandCenterEnabled == true
end

return Builder
