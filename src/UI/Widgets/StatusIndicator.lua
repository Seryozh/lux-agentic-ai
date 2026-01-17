--[[
    StatusIndicator.lua
    Circuit breaker and system health status indicator widget

    Shows:
    - Circuit breaker status (closed/half-open/open)
    - Heartbeat pulse animation (green when healthy, red when circuit open)
    - Token usage counter
    - Reactive updates via SessionManager.OnUpdate
]]

local Constants = require(script.Parent.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Parent.Create)
local Utils = require(script.Parent.Parent.Parent.Shared.Utils)
local SessionManager = require(script.Parent.Parent.Parent.Coordination.SessionManager)
local CircuitBreaker = require(script.Parent.Parent.Parent.Safety.CircuitBreaker)

local TweenService = game:GetService("TweenService")

local StatusIndicator = {}

-- Status configurations
local STATUS_CONFIG = {
    closed = {
        text = "System OK",
        color = Color3.fromRGB(76, 199, 30),  -- #4CC71E Green
        icon = "●",
        shouldPulse = true
    },
    ["half-open"] = {
        text = "Testing...",
        color = Constants.COLORS.accentWarning,
        icon = "◐",
        shouldPulse = false
    },
    open = {
        text = "Circuit Open",
        color = Color3.fromRGB(199, 30, 30),  -- #C71E1E Red
        icon = "●",
        shouldPulse = false  -- Flatline
    }
}

--[[
    Create the status indicator widget with reactive heartbeat
    @param parent Frame
    @return Frame - Container
    @return Janitor - Cleanup manager
]]
function StatusIndicator.create(parent)
    local janitor = Utils.Janitor.new()

    local container = Create.new("Frame", {
        Name = "StatusIndicator",
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundColor3 = Color3.fromRGB(37, 37, 38),  -- #252526
        BorderSizePixel = 0,
        ZIndex = Constants.UI.ZINDEX.WIDGETS,
        Parent = parent
    })

    janitor:Add(container, "Destroy")

    Create.new("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = container
    })

    -- Status dot (left side)
    local dot = Create.new("TextLabel", {
        Name = "StatusDot",
        Size = UDim2.new(0, 12, 0, 12),
        Position = UDim2.new(0, 0, 0.5, -6),
        BackgroundTransparency = 1,
        Text = "●",
        TextColor3 = Color3.fromRGB(76, 199, 30),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Parent = container
    })

    -- Status text
    local label = Create.new("TextLabel", {
        Name = "StatusLabel",
        Size = UDim2.new(0, 100, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
        BackgroundTransparency = 1,
        Text = "System OK",
        TextColor3 = Color3.fromRGB(76, 199, 30),
        Font = Constants.UI.FONT_MONO,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container
    })

    -- Token counter (right side)
    local tokenLabel = Create.new("TextLabel", {
        Name = "TokenCounter",
        Size = UDim2.new(0, 80, 1, 0),
        Position = UDim2.new(1, -80, 0, 0),
        BackgroundTransparency = 1,
        Text = "$0.00",
        TextColor3 = Constants.COLORS.textSecondary,
        Font = Constants.UI.FONT_MONO,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = container
    })

    -- Track current pulse animation
    local currentPulseTween = nil

    --[[
        Start heartbeat pulse animation
    ]]
    local function startPulse()
        if currentPulseTween then
            currentPulseTween:Cancel()
        end

        -- Pulse: Transparency 0.5 -> 0.0 (fade in)
        local tweenInfo = TweenInfo.new(
            1.0,  -- Duration: 1 second
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            -1,  -- Repeat infinitely
            true  -- Reverse
        )

        currentPulseTween = TweenService:Create(dot, tweenInfo, {
            TextTransparency = 0.5
        })
        currentPulseTween:Play()

        -- Safe cleanup wrapper for tween
        janitor:Add(function()
            if currentPulseTween and currentPulseTween.PlaybackState == Enum.PlaybackState.Playing then
                pcall(function() currentPulseTween:Cancel() end)
            end
        end)
    end

    --[[
        Stop heartbeat pulse (flatline)
    ]]
    local function stopPulse()
        if currentPulseTween then
            currentPulseTween:Cancel()
            currentPulseTween = nil
        end
        dot.TextTransparency = 0  -- Solid
    end

    --[[
        Update the status indicator from CircuitBreaker
    ]]
    local function updateStatus()
        local circuitStatus = CircuitBreaker.getStatus()
        if not circuitStatus then return end

        local mode = circuitStatus.mode or "closed"
        local config = STATUS_CONFIG[mode] or STATUS_CONFIG.closed

        -- Update dot color
        dot.TextColor3 = config.color

        -- Update label
        local text = config.text
        if mode ~= "closed" and circuitStatus.failures and circuitStatus.failures > 0 then
            text = text .. " (" .. circuitStatus.failures .. ")"
        end
        label.Text = text
        label.TextColor3 = config.color

        -- Control pulse animation
        if config.shouldPulse then
            startPulse()
        else
            stopPulse()
        end
    end

    --[[
        Update token usage (if ApiClient is available)
    ]]
    local function updateTokenUsage()
        local success, ApiClient = pcall(function()
            return require(script.Parent.Parent.Parent.Core.ApiClient)
        end)

        if success and ApiClient and ApiClient.getTokenUsage then
            local usage = ApiClient.getTokenUsage()
            if usage and usage.totalCost then
                tokenLabel.Text = string.format("$%.4f", usage.totalCost)
            end
        end
    end

    --[[
        Reactive update callback
    ]]
    local function onUpdate()
        updateStatus()
        updateTokenUsage()
    end

    -- Subscribe to SessionManager updates
    local updateConnection = SessionManager.OnUpdate:Connect(onUpdate)
    janitor:Add(updateConnection, "Disconnect")

    -- Initial render
    onUpdate()

    return container, janitor
end

--[[
    Create a minimal inline status for the status bar
    @param status table - Circuit breaker status
    @return string, Color3 - Text and color for display
]]
function StatusIndicator.formatInline(status)
    if not status then
        return "OK System", Color3.fromRGB(76, 199, 30)
    end

    local mode = status.mode or "closed"
    local config = STATUS_CONFIG[mode] or STATUS_CONFIG.closed

    local text = config.icon .. " " .. config.text
    if mode ~= "closed" and status.failures and status.failures > 0 then
        text = text .. " (" .. status.failures .. ")"
    end

    return text, config.color
end

return StatusIndicator
