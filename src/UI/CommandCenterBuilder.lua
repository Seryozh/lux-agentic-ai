--[[
    CommandCenterBuilder.lua
    Main three-pane Command Center layout builder

    Creates the professional dashboard layout:
    - Header bar (title + settings)
    - Three-pane container (Brain | Stream | Mission)
    - Full-width input area
    - Status bar (circuit breaker + tokens)
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Create)
local Components = require(script.Parent.Components)
local PaneContainer = require(script.Parent.PaneContainer)

-- Lazy-load pane modules to avoid circular dependencies
local LeftPane, CenterPane, RightPane

local CommandCenterBuilder = {}

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
    Create the header bar
    @param parent Frame
    @return table - { container, settingsButton, resetButton }
]]
local function createHeaderBar(parent)
    local cc = Constants.COMMAND_CENTER

    local headerBar = Create.new("Frame", {
        Name = "HeaderBar",
        Size = UDim2.new(1, 0, 0, cc.headerHeight),
        BackgroundColor3 = Constants.COLORS.backgroundDark,
        BorderSizePixel = 0,
        LayoutOrder = 1,
        Parent = parent
    })

    Create.new("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = headerBar
    })

    Create.new("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 8),
        Parent = headerBar
    })

    -- Title
    local title = Create.new("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -80, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = Constants.ICONS.LUX .. " " .. Constants.PLUGIN_NAME,
        TextColor3 = Constants.COLORS.textPrimary,
        Font = Constants.UI.FONT_HEADER,
        TextSize = Constants.UI.FONT_SIZE_HEADER,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = headerBar
    })

    -- Button container
    local buttonContainer = Create.new("Frame", {
        Name = "HeaderButtons",
        Size = UDim2.new(0, 70, 1, 0),
        Position = UDim2.new(1, -70, 0, 0),
        BackgroundTransparency = 1,
        Parent = headerBar
    })

    Components.ListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 4),
        Parent = buttonContainer
    })

    -- Reset button
    local resetButton = Create.new("TextButton", {
        Name = "ResetButton",
        Size = UDim2.new(0, 24, 0, 20),
        BackgroundColor3 = Constants.COLORS.backgroundLight,
        Text = Constants.ICONS.RESET,
        TextColor3 = Constants.COLORS.textSecondary,
        Font = Enum.Font.GothamBold,
        TextSize = Constants.UI.FONT_SIZE_SMALL,
        LayoutOrder = 1,
        Parent = buttonContainer
    })

    Create.new("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = resetButton
    })

    -- Settings button
    local settingsButton = Create.new("TextButton", {
        Name = "SettingsButton",
        Size = UDim2.new(0, 24, 0, 20),
        BackgroundColor3 = Constants.COLORS.backgroundLight,
        Text = Constants.ICONS.SETTINGS,
        TextColor3 = Constants.COLORS.textSecondary,
        Font = Enum.Font.GothamBold,
        TextSize = Constants.UI.FONT_SIZE_SMALL,
        LayoutOrder = 2,
        Parent = buttonContainer
    })

    Create.new("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = settingsButton
    })

    addHoverEffect(resetButton, Constants.COLORS.backgroundLight)
    addHoverEffect(settingsButton, Constants.COLORS.backgroundLight)

    return {
        container = headerBar,
        settingsButton = settingsButton,
        resetButton = resetButton
    }
end

--[[
    Create the input area (full width at bottom)
    @param parent Frame
    @return table - { container, textInput, sendButton }
]]
local function createInputArea(parent)
    local cc = Constants.COMMAND_CENTER

    local inputContainer = Create.new("Frame", {
        Name = "InputArea",
        Size = UDim2.new(1, 0, 0, cc.inputHeight),
        BackgroundColor3 = Constants.COLORS.backgroundLight,
        BorderSizePixel = 0,
        LayoutOrder = 3,
        Parent = parent
    })

    Create.new("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = inputContainer
    })

    Create.new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 8),
        Parent = inputContainer
    })

    Components.ListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = inputContainer
    })

    -- Text input
    local textInput = Components.TextInput({
        Name = "TextInput",
        Size = UDim2.new(1, -65, 1, 0),
        PlaceholderText = "Ask about your code...",
        MultiLine = false,
        LayoutOrder = 1,
        Parent = inputContainer
    })

    -- Send button
    local sendButton = Components.Button({
        Name = "SendButton",
        Size = UDim2.new(0, 55, 1, 0),
        Text = "Send",
        Font = Enum.Font.GothamBold,
        TextSize = Constants.UI.FONT_SIZE_SMALL,
        LayoutOrder = 2,
        Parent = inputContainer
    })

    addHoverEffect(sendButton, Constants.COLORS.accentPrimary)

    return {
        container = inputContainer,
        textInput = textInput,
        sendButton = sendButton
    }
end

--[[
    Create the status bar (bottom)
    @param parent Frame
    @return table - { container, circuitStatus, tokenLabel }
]]
local function createStatusBar(parent)
    local cc = Constants.COMMAND_CENTER

    local statusBar = Create.new("Frame", {
        Name = "StatusBar",
        Size = UDim2.new(1, 0, 0, cc.statusBarHeight),
        BackgroundColor3 = Constants.COLORS.backgroundDark,
        BorderSizePixel = 0,
        LayoutOrder = 4,
        Parent = parent
    })

    Create.new("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = statusBar
    })

    Create.new("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = statusBar
    })

    Components.ListLayout({
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 16),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = statusBar
    })

    -- Circuit breaker status indicator
    local circuitStatus = Create.new("TextLabel", {
        Name = "CircuitStatus",
        Size = UDim2.new(0, 80, 1, 0),
        BackgroundTransparency = 1,
        Text = "✓ OK",
        TextColor3 = Constants.COLORS.accentSuccess,
        Font = Constants.UI.FONT_MONO,
        TextSize = Constants.UI.FONT_SIZE_TINY,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        Parent = statusBar
    })

    -- Token usage label
    local tokenLabel = Create.new("TextLabel", {
        Name = "TokenStatusLabel",
        Size = UDim2.new(1, -90, 1, 0),
        BackgroundTransparency = 1,
        Text = Constants.ICONS.COST .. " $0.00",
        TextColor3 = Constants.COLORS.textSecondary,
        Font = Constants.UI.FONT_MONO,
        TextSize = Constants.UI.FONT_SIZE_TINY,
        TextXAlignment = Enum.TextXAlignment.Right,
        LayoutOrder = 2,
        Parent = statusBar
    })

    return {
        container = statusBar,
        circuitStatus = circuitStatus,
        tokenLabel = tokenLabel
    }
end

--[[
    Create the main Command Center UI
    @param widget DockWidgetPluginGui
    @param state table - Plugin state
    @return table - Button/input references for event binding
]]
function CommandCenterBuilder.createUI(widget, state)
    local cc = Constants.COMMAND_CENTER
    local padding = 8
    local gap = 6

    -- Lazy-load pane modules
    LeftPane = LeftPane or require(script.Parent.Panes.LeftPane)
    CenterPane = CenterPane or require(script.Parent.Panes.CenterPane)
    RightPane = RightPane or require(script.Parent.Panes.RightPane)

    -- Main container (no UIListLayout - use absolute positioning)
    local mainFrame = Create.new("Frame", {
        Name = "MainFrame",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Constants.COLORS.background,
        BorderSizePixel = 0,
        Parent = widget
    })

    -- Header at top
    local header = createHeaderBar(mainFrame)
    header.container.Position = UDim2.new(0, padding, 0, padding)
    header.container.Size = UDim2.new(1, -padding * 2, 0, cc.headerHeight)

    -- Status bar at bottom
    local statusBar = createStatusBar(mainFrame)
    statusBar.container.Position = UDim2.new(0, padding, 1, -padding - cc.statusBarHeight)
    statusBar.container.Size = UDim2.new(1, -padding * 2, 0, cc.statusBarHeight)

    -- Input area above status bar
    local inputArea = createInputArea(mainFrame)
    inputArea.container.Position = UDim2.new(0, padding, 1, -padding - cc.statusBarHeight - gap - cc.inputHeight)
    inputArea.container.Size = UDim2.new(1, -padding * 2, 0, cc.inputHeight)

    -- Pane container takes remaining middle space
    local topOffset = padding + cc.headerHeight + gap
    local bottomOffset = padding + cc.statusBarHeight + gap + cc.inputHeight + gap
    local paneWrapper = Create.new("Frame", {
        Name = "PaneWrapper",
        Position = UDim2.new(0, padding, 0, topOffset),
        Size = UDim2.new(1, -padding * 2, 1, -topOffset - bottomOffset),
        BackgroundTransparency = 1,
        Parent = mainFrame
    })

    local panes = PaneContainer.create(paneWrapper)

    -- Populate panes
    local leftFrame = PaneContainer.getPaneFrame(panes, "left")
    local centerFrame = PaneContainer.getPaneFrame(panes, "center")
    local rightFrame = PaneContainer.getPaneFrame(panes, "right")

    -- Create reactive panes (new API returns frame, janitor)
    local leftPaneUI, leftPaneJanitor = LeftPane.create(leftFrame)
    local chatHistory = CenterPane.populate(centerFrame, state)
    print("[Lux DEBUG] CommandCenterBuilder - chatHistory returned:", chatHistory)
    local rightPaneUI, rightPaneJanitor = RightPane.create(rightFrame)

    -- Store UI references in state
    print("[Lux DEBUG] CommandCenterBuilder - Building state.ui table")
    state.ui = {
        mainFrame = mainFrame,
        paneContainer = panes,
        leftPane = leftFrame,
        centerPane = centerFrame,
        rightPane = rightFrame,
        chatHistory = chatHistory,
        chatContainer = centerFrame, -- For compatibility with existing ChatRenderer
        textInput = inputArea.textInput,
        sendButton = inputArea.sendButton,
        settingsButton = header.settingsButton,
        headerResetButton = header.resetButton,
        tokenStatusBar = statusBar.container,
        tokenStatusLabel = statusBar.tokenLabel,
        circuitStatus = statusBar.circuitStatus,
        -- Pane janitors for cleanup
        leftPaneJanitor = leftPaneJanitor,
        rightPaneJanitor = rightPaneJanitor,
        -- Compatibility with classic UI
        statusLabel = nil,
        statusPanel = nil,
        rescanButton = nil,
        resetContextButton = nil,
    }

    print("[Lux DEBUG] CommandCenterBuilder - state.ui.chatHistory final value:", state.ui.chatHistory)

    -- Handle responsive layout
    mainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        local width = mainFrame.AbsoluteSize.X
        PaneContainer.handleResize(panes, width)
    end)

    -- Initial resize check
    task.defer(function()
        local width = mainFrame.AbsoluteSize.X
        PaneContainer.handleResize(panes, width)
    end)

    return {
        settingsButton = header.settingsButton,
        headerResetButton = header.resetButton,
        sendButton = inputArea.sendButton,
        textInput = inputArea.textInput,
        -- Compatibility fields
        rescanButton = nil,
        resetContextButton = nil
    }
end

--[[
    Update circuit breaker status display
    @param state table - Plugin state
    @param circuitStatus table - From CircuitBreaker.getStatus()
]]
function CommandCenterBuilder.updateCircuitStatus(state, circuitStatus)
    if not state.ui or not state.ui.circuitStatus then return end

    local label = state.ui.circuitStatus
    if circuitStatus.mode == "closed" then
        label.Text = "✓ OK"
        label.TextColor3 = Constants.COLORS.accentSuccess
    elseif circuitStatus.mode == "half-open" then
        label.Text = "~ Testing"
        label.TextColor3 = Constants.COLORS.accentWarning
    else -- open
        label.Text = "! Paused"
        label.TextColor3 = Constants.COLORS.accentError
    end
end

return CommandCenterBuilder
