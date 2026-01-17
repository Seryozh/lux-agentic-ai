--[[
    RightPane.lua - "Mission" Pane (Reactive Flight Plan)

    The Flight Plan displays a vertical timeline of task tickets.
    Each ticket shows its status with a visual icon aligned to a central spine.

    Architecture:
    - Subscribe to SessionManager.OnUpdate
    - Fetch TaskPlanner.getCurrentPlan() on every pulse
    - Clear and rebuild the timeline (simple, effective for small plans)

    Visuals:
    - Vertical spine (2px width, #333333)
    - Status nodes aligned to spine:
      ○ Pending (Gray)
      ◉ Active (Blue #007ACC with pulse animation)
      ✓ Done (Green)
      ✕ Failed (Red with error text)
]]

local Constants = require(script.Parent.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Parent.Create)
local Utils = require(script.Parent.Parent.Parent.Shared.Utils)
local SessionManager = require(script.Parent.Parent.Parent.Coordination.SessionManager)
local TaskPlanner = require(script.Parent.Parent.Parent.Planning.TaskPlanner)

local TweenService = game:GetService("TweenService")

local RightPane = {}

-- Status configurations
local STATUS_CONFIG = {
    PENDING = {
        icon = "○",
        color = Color3.fromRGB(150, 150, 150),  -- Gray
        shouldPulse = false
    },
    RUNNING = {
        icon = "◉",
        color = Color3.fromRGB(0, 122, 204),  -- Blue #007ACC
        shouldPulse = true
    },
    DONE = {
        icon = "✓",
        color = Color3.fromRGB(76, 199, 30),  -- Green
        shouldPulse = false
    },
    FAILED = {
        icon = "✕",
        color = Color3.fromRGB(199, 30, 30),  -- Red
        shouldPulse = false
    },
    RETRYING = {
        icon = "◉",
        color = Color3.fromRGB(255, 191, 0),  -- Yellow
        shouldPulse = true
    }
}

--[[
    Create the Right Pane with reactive Flight Plan
    @param parent Frame
    @return Frame - The pane container
    @return Janitor - Cleanup manager
]]
function RightPane.create(parent)
    local janitor = Utils.Janitor.new()

    -- Main container
    local paneFrame = Create.new("Frame", {
        Name = "RightPane",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Constants.COMMAND_CENTER.colors.paneBackground,
        BorderSizePixel = 0,
        Parent = parent
    })

    janitor:Add(paneFrame, "Destroy")

    -- Scrolling container for timeline
    local scrollingFrame = Create.new("ScrollingFrame", {
        Name = "Timeline",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Constants.COLORS.textMuted,
        CanvasSize = UDim2.new(1, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = paneFrame
    })

    Create.new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 24),  -- Space for spine
        PaddingRight = UDim.new(0, 8),
        Parent = scrollingFrame
    })

    -- Header (centered for symmetry)
    local header = Create.new("TextLabel", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "🎯 FLIGHT PLAN",
        TextColor3 = Constants.COLORS.textPrimary,
        Font = Enum.Font.GothamBold,
        TextSize = Constants.UI.FONT_SIZE_SUBHEADER,
        TextXAlignment = Enum.TextXAlignment.Center,  -- CENTERED instead of Left
        Parent = scrollingFrame
    })

    -- The Spine (vertical line, 2px width)
    local spine = Create.new("Frame", {
        Name = "Spine",
        Size = UDim2.new(0, 2, 1, -28),  -- Full height minus header
        Position = UDim2.new(0, 8, 0, 28),  -- Left of content
        BackgroundColor3 = Color3.fromRGB(51, 51, 51),  -- #333333
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = scrollingFrame
    })

    -- Content container (tickets)
    local contentContainer = Create.new("Frame", {
        Name = "Content",
        Size = UDim2.new(1, -20, 0, 0),  -- Leave space for spine
        Position = UDim2.new(0, 20, 0, 28),  -- Offset from spine
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 2,
        Parent = scrollingFrame
    })

    Create.new("UIListLayout", {
        Padding = UDim.new(0, 12),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = contentContainer
    })

    -- Empty state
    local emptyLabel = Create.new("TextLabel", {
        Name = "EmptyState",
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        Text = "No active plan",
        TextColor3 = Constants.COLORS.textMuted,
        Font = Constants.UI.FONT_CODE,
        TextSize = Constants.UI.FONT_SIZE_SMALL,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 0,
        Parent = contentContainer
    })

    -- Track active pulse tweens for cleanup
    local activePulseTweens = {}

    -- Track last plan signature to prevent unnecessary rebuilds
    local lastPlanSignature = ""

    --[[
        Create a ticket node
        @param ticket table - { id, text, status, output }
        @param layoutOrder number
    ]]
    local function createTicketNode(ticket, layoutOrder)
        local status = ticket.status or "PENDING"
        local config = STATUS_CONFIG[status] or STATUS_CONFIG.PENDING

        -- Ticket container
        local ticketFrame = Create.new("Frame", {
            Name = "Ticket_" .. ticket.id,
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = layoutOrder,
            Parent = contentContainer
        })

        -- Node icon (aligned to spine)
        local nodeIcon = Create.new("TextLabel", {
            Name = "NodeIcon",
            Size = UDim2.new(0, 16, 0, 16),
            Position = UDim2.new(0, -28, 0, 0),  -- Align to spine
            BackgroundTransparency = 1,
            Text = config.icon,
            TextColor3 = config.color,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            ZIndex = 3,
            Parent = ticketFrame
        })

        -- Pulse animation for active tickets
        if config.shouldPulse then
            local tweenInfo = TweenInfo.new(
                1.0,
                Enum.EasingStyle.Sine,
                Enum.EasingDirection.InOut,
                -1,  -- Infinite
                true  -- Reverse
            )

            local pulseTween = TweenService:Create(nodeIcon, tweenInfo, {
                TextTransparency = 0.6
            })
            pulseTween:Play()

            table.insert(activePulseTweens, pulseTween)

            -- Safe cleanup wrapper for tween
            janitor:Add(function()
                if pulseTween and pulseTween.PlaybackState == Enum.PlaybackState.Playing then
                    pcall(function() pulseTween:Cancel() end)
                end
            end)
        end

        -- Ticket text
        local textLabel = Create.new("TextLabel", {
            Name = "TicketText",
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = ticket.text or "Unknown ticket",
            TextColor3 = config.color,
            Font = Constants.UI.FONT_CODE,
            TextSize = Constants.UI.FONT_SIZE_SMALL,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = ticketFrame
        })

        -- Strikethrough for completed
        if status == "DONE" then
            textLabel.TextTransparency = 0.4
        end

        -- Error output for failed tickets
        if status == "FAILED" and ticket.output then
            local errorLabel = Create.new("TextLabel", {
                Name = "ErrorText",
                Size = UDim2.new(1, 0, 0, 0),
                Position = UDim2.new(0, 0, 1, 4),
                BackgroundTransparency = 1,
                Text = "Error: " .. ticket.output,
                TextColor3 = Color3.fromRGB(255, 180, 180),
                Font = Constants.UI.FONT_CODE,
                TextSize = Constants.UI.FONT_SIZE_TINY,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = true,
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = ticketFrame
            })
        end

        return ticketFrame
    end

    --[[
        Update the flight plan (reactive rebuild)
        Called on every SessionManager.OnUpdate pulse
    ]]
    local function updateFlightPlan()
        -- Get current plan
        local plan = TaskPlanner.getCurrentPlan and TaskPlanner.getCurrentPlan() or nil

        -- Generate plan signature for change detection
        local currentSignature = ""
        if plan and plan.tickets and #plan.tickets > 0 then
            -- Build signature: ticketCount + status string
            local statusString = ""
            for _, ticket in ipairs(plan.tickets) do
                statusString = statusString .. (ticket.status or "PENDING") .. ","
            end
            currentSignature = #plan.tickets .. ":" .. statusString
        else
            currentSignature = "empty"
        end

        -- Skip rebuild if nothing changed
        if currentSignature == lastPlanSignature then
            return
        end
        lastPlanSignature = currentSignature

        -- Clear existing tickets
        for _, child in ipairs(contentContainer:GetChildren()) do
            if child:IsA("Frame") and child.Name:find("Ticket_") then
                child:Destroy()
            end
        end

        -- Cancel all active pulse tweens
        for _, tween in ipairs(activePulseTweens) do
            if tween then
                pcall(function() tween:Cancel() end)
            end
        end
        activePulseTweens = {}

        if not plan or not plan.tickets or #plan.tickets == 0 then
            emptyLabel.Visible = true
            spine.Size = UDim2.new(0, 2, 0, 40)  -- Minimal spine
            return
        end

        -- Hide empty state
        emptyLabel.Visible = false

        -- Render tickets
        local order = 1
        for _, ticket in ipairs(plan.tickets) do
            createTicketNode(ticket, order)
            order = order + 1
        end

        -- Extend spine to match content height
        spine.Size = UDim2.new(0, 2, 1, -28)
    end

    -- Subscribe to SessionManager for reactive plan updates
    local updateConnection = SessionManager.OnUpdate:Connect(function()
        updateFlightPlan()
    end)
    janitor:Add(updateConnection, "Disconnect")

    -- Initial render
    updateFlightPlan()

    return paneFrame, janitor
end

return RightPane
