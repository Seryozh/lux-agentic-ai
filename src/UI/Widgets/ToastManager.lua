--[[
    ToastManager.lua
    Temporary notification system for tool execution feedback

    Shows non-blocking toast notifications in the corner of the UI:
    - Tool execution status
    - Warnings and errors
    - Auto-dismiss after duration
]]

local TweenService = game:GetService("TweenService")
local Constants = require(script.Parent.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Parent.Create)

local ToastManager = {}

-- Internal state
local toastContainer = nil
local activeToasts = {}
local toastQueue = {}

-- Toast type configurations
local TOAST_CONFIG = {
    info = {
        icon = "ℹ️",
        color = Constants.COLORS.accentPrimary,
        bgColor = Color3.fromRGB(35, 40, 60)
    },
    success = {
        icon = "✅",
        color = Constants.COLORS.accentSuccess,
        bgColor = Color3.fromRGB(30, 50, 40)
    },
    warning = {
        icon = "⚠️",
        color = Constants.COLORS.accentWarning,
        bgColor = Color3.fromRGB(50, 45, 30)
    },
    error = {
        icon = "❌",
        color = Constants.COLORS.accentError,
        bgColor = Color3.fromRGB(50, 30, 30)
    },
    tool = {
        icon = "🔧",
        color = Constants.COLORS.textSecondary,
        bgColor = Color3.fromRGB(35, 38, 48)
    }
}

-- Animation settings
local SLIDE_IN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--[[
    Initialize the toast manager
    @param parent Frame - The main UI frame to attach toasts to
]]
function ToastManager.init(parent)
    if toastContainer then return end

    -- Create toast container (top-right corner)
    toastContainer = Create.new("Frame", {
        Name = "ToastContainer",
        Size = UDim2.new(0, 250, 1, -100),
        Position = UDim2.new(1, -260, 0, 50),
        BackgroundTransparency = 1,
        ZIndex = 100,
        Parent = parent
    })

    Create.new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Parent = toastContainer
    })
end

--[[
    Show a toast notification
    @param message string - The message to display
    @param toastType string - Type: "info", "success", "warning", "error", "tool"
    @param duration number - Seconds before auto-dismiss (default from config)
    @return Frame - The toast frame
]]
function ToastManager.show(message, toastType, duration)
    if not toastContainer then return nil end

    local cc = Constants.COMMAND_CENTER
    if not cc.toastEnabled then return nil end

    toastType = toastType or "info"
    duration = duration or cc.toastDuration or 3

    local config = TOAST_CONFIG[toastType] or TOAST_CONFIG.info

    -- Check if we're at max visible
    if #activeToasts >= (cc.toastMaxVisible or 3) then
        -- Queue the toast
        table.insert(toastQueue, { message = message, toastType = toastType, duration = duration })
        return nil
    end

    -- Create toast frame
    local toast = Create.new("Frame", {
        Name = "Toast",
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = config.bgColor,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = #activeToasts + 1,
        Parent = toastContainer
    })

    Create.new("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = toast
    })

    Create.new("UIStroke", {
        Color = config.color,
        Thickness = 1,
        Transparency = 0.7,
        Parent = toast
    })

    Create.new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = toast
    })

    -- Icon
    local icon = Create.new("TextLabel", {
        Name = "Icon",
        Size = UDim2.new(0, 20, 1, 0),
        BackgroundTransparency = 1,
        Text = config.icon,
        TextSize = 14,
        Parent = toast
    })

    -- Message
    local label = Create.new("TextLabel", {
        Name = "Message",
        Size = UDim2.new(1, -28, 1, 0),
        Position = UDim2.new(0, 24, 0, 0),
        BackgroundTransparency = 1,
        Text = message,
        TextColor3 = Constants.COLORS.textPrimary,
        Font = Constants.UI.FONT_NORMAL,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = toast
    })

    -- Progress bar for duration
    local progressBar = Create.new("Frame", {
        Name = "Progress",
        Size = UDim2.new(1, 0, 0, 2),
        Position = UDim2.new(0, 0, 1, -2),
        BackgroundColor3 = config.color,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Parent = toast
    })

    -- Track toast
    table.insert(activeToasts, toast)

    -- Slide-in animation
    toast.Position = UDim2.new(1, 50, 0, 0)
    TweenService:Create(toast, SLIDE_IN, {
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()

    -- Progress bar animation
    TweenService:Create(progressBar, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
        Size = UDim2.new(0, 0, 0, 2)
    }):Play()

    -- Auto-dismiss
    task.delay(duration, function()
        ToastManager.dismiss(toast)
    end)

    return toast
end

--[[
    Dismiss a toast
    @param toast Frame - The toast to dismiss
]]
function ToastManager.dismiss(toast)
    if not toast or not toast.Parent then return end

    -- Remove from active list
    for i, t in ipairs(activeToasts) do
        if t == toast then
            table.remove(activeToasts, i)
            break
        end
    end

    -- Slide-out animation
    TweenService:Create(toast, SLIDE_OUT, {
        Position = UDim2.new(1, 50, 0, 0),
        BackgroundTransparency = 1
    }):Play()

    task.delay(0.15, function()
        if toast.Parent then
            toast:Destroy()
        end

        -- Process queue
        if #toastQueue > 0 then
            local queued = table.remove(toastQueue, 1)
            ToastManager.show(queued.message, queued.toastType, queued.duration)
        end
    end)
end

--[[
    Clear all toasts
]]
function ToastManager.clear()
    for _, toast in ipairs(activeToasts) do
        if toast.Parent then
            toast:Destroy()
        end
    end
    activeToasts = {}
    toastQueue = {}
end

--[[
    Show a tool execution toast
    @param toolName string - Name of the tool
    @param intent string - What the tool is doing
]]
function ToastManager.showToolStart(toolName, intent)
    local message = intent or ("Executing " .. toolName .. "...")
    return ToastManager.show(message, "tool", 2)
end

--[[
    Show a tool result toast
    @param toolName string - Name of the tool
    @param success boolean - Whether the tool succeeded
    @param result string - Optional result message
]]
function ToastManager.showToolResult(toolName, success, result)
    local toastType = success and "success" or "error"
    local message = result or (toolName .. (success and " completed" or " failed"))
    return ToastManager.show(message, toastType, success and 2 or 4)
end

return ToastManager
