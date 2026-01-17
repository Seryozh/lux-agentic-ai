--[[
    CenterPane.lua - "Stream" Pane
    The main chat interface - wraps existing ChatRenderer functionality

    This pane contains:
    - Chat history (ScrollingFrame)
    - Tool activity cards (via ChatRenderer)
]]

local Constants = require(script.Parent.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Parent.Create)
local Components = require(script.Parent.Parent.Components)

local CenterPane = {}

--[[
    Populate the center pane with chat interface
    @param paneFrame Frame
    @param state table
    @return ScrollingFrame - The chat history frame for ChatRenderer
]]
function CenterPane.populate(paneFrame, state)
    -- Clear any existing layout (pane already has padding from PaneContainer)
    for _, child in ipairs(paneFrame:GetChildren()) do
        if child:IsA("UIListLayout") then
            child:Destroy()
        end
    end

    -- TERMINAL MODE: No title, maximize screen real estate
    -- Chat history ScrollingFrame - MAXIMIZED for terminal density
    local chatHistory = Create.new("ScrollingFrame", {
        Name = "ChatHistory",
        Size = UDim2.new(1, 0, 1, 0),  -- FULL HEIGHT (no title in terminal mode)
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(24, 24, 24),  -- #181818 Terminal Black
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90),
        ScrollBarImageTransparency = 0.3,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
        BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
        MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
        Parent = paneFrame
    })

    -- Minimal padding for terminal density
    Create.new("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        Parent = chatHistory
    })

    -- Layout for chat messages with tight spacing
    local chatLayout = Components.ListLayout({
        Padding = UDim.new(0, 4),  -- Dense terminal spacing
        Parent = chatHistory
    })

    -- Store reference in state for ChatRenderer compatibility
    if state then
        state.ui = state.ui or {}
        state.ui.chatHistory = chatHistory
        state.ui.chatLayout = chatLayout
        print("[Lux DEBUG] CenterPane.populate() - chatHistory stored in state.ui:", chatHistory)
    else
        warn("[Lux] CenterPane.populate() called with nil state!")
    end

    print("[Lux DEBUG] CenterPane.populate() returning chatHistory:", chatHistory)
    return chatHistory
end

--[[
    Scroll to bottom of chat
    @param chatHistory ScrollingFrame
]]
function CenterPane.scrollToBottom(chatHistory)
    if not chatHistory then return end

    task.defer(function()
        chatHistory.CanvasPosition = Vector2.new(
            0,
            math.max(0, chatHistory.AbsoluteCanvasSize.Y - chatHistory.AbsoluteSize.Y)
        )
    end)
end

--[[
    Show welcome message when chat is empty
    @param chatHistory ScrollingFrame
]]
function CenterPane.showWelcome(chatHistory)
    -- Check if already has messages
    for _, child in ipairs(chatHistory:GetChildren()) do
        if child:IsA("Frame") then
            return -- Already has content
        end
    end

    local welcomeFrame = Create.new("Frame", {
        Name = "WelcomeMessage",
        Size = UDim2.new(1, 0, 0, 80),
        BackgroundColor3 = Constants.COLORS.backgroundLight,
        BorderSizePixel = 0,
        LayoutOrder = 0,
        Parent = chatHistory
    })

    Create.new("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = welcomeFrame
    })

    Create.new("UIPadding", {
        PaddingTop = UDim.new(0, 12),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        Parent = welcomeFrame
    })

    Create.new("TextLabel", {
        Name = "WelcomeText",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = Constants.ICONS.LUX .. " Welcome to Lux!\n\nAsk me anything about your project.\nI can read, edit, and create scripts for you.",
        TextColor3 = Constants.COLORS.textSecondary,
        Font = Constants.UI.FONT_NORMAL,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = welcomeFrame
    })
end

--[[
    Clear welcome message when first real message is added
    @param chatHistory ScrollingFrame
]]
function CenterPane.clearWelcome(chatHistory)
    local welcome = chatHistory:FindFirstChild("WelcomeMessage")
    if welcome then
        welcome:Destroy()
    end
end

return CenterPane
