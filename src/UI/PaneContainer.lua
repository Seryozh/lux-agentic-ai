--[[
    PaneContainer.lua
    Three-pane horizontal container with collapse/expand functionality

    Creates a horizontal layout with left (Brain), center (Stream), and right (Mission) panes.
    Supports responsive collapse to icons when widget is narrow.
]]

local TweenService = game:GetService("TweenService")
local Constants = require(script.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Create)

local PaneContainer = {}

-- Animation settings
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Pane icons for collapsed state
local PANE_ICONS = {
    left = "🧠",    -- Brain
    center = "💬",  -- Stream
    right = "🎯"    -- Mission
}

local PANE_TITLES = {
    left = "Brain",
    center = "Stream",
    right = "Mission"
}

--[[
    Create the three-pane container
    @param parent Frame - Parent container
    @param config table - Configuration options
    @return table - Container reference with pane frames
]]
function PaneContainer.create(parent, config)
    config = config or {}
    local cc = Constants.COMMAND_CENTER

    -- Main container for all three panes
    local container = Create.new("Frame", {
        Name = "PaneContainer",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = parent
    })

    -- Store pane references and state
    local panes = {
        container = container,
        frames = {},
        collapsed = {
            left = false,
            center = false,
            right = false
        },
        originalWidths = {
            left = cc.paneWidths.left,
            center = cc.paneWidths.center,
            right = cc.paneWidths.right
        }
    }

    -- Create each pane
    local paneOrder = { "left", "center", "right" }
    for i, paneId in ipairs(paneOrder) do
        local width = cc.paneWidths[paneId]

        -- Pane wrapper (handles sizing and collapse)
        local paneWrapper = Create.new("Frame", {
            Name = paneId:sub(1,1):upper() .. paneId:sub(2) .. "PaneWrapper",
            Size = UDim2.new(width, -cc.paneGap, 1, 0),
            Position = UDim2.new(
                (i == 1) and 0 or (paneOrder[1] == "left" and cc.paneWidths.left or 0) +
                    (i == 3 and (cc.paneWidths.left + cc.paneWidths.center) or (i == 2 and cc.paneWidths.left or 0)),
                (i > 1) and cc.paneGap or 0,
                0, 0
            ),
            BackgroundTransparency = 1,
            ClipsDescendants = true,
            Parent = container
        })

        -- Actual pane content frame
        local paneFrame = Create.new("Frame", {
            Name = paneId:sub(1,1):upper() .. paneId:sub(2) .. "Pane",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = cc.colors.paneBackground,
            BorderSizePixel = 0,
            Parent = paneWrapper
        })

        Create.new("UICorner", {
            CornerRadius = UDim.new(0, 6),
            Parent = paneFrame
        })

        Create.new("UIStroke", {
            Color = cc.colors.paneBorder,
            Thickness = 1,
            Parent = paneFrame
        })

        Create.new("UIPadding", {
            PaddingTop = UDim.new(0, 8),
            PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
            Parent = paneFrame
        })

        -- Collapsed indicator (icon button, hidden by default)
        local collapsedIndicator = Create.new("TextButton", {
            Name = "CollapsedIndicator",
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundColor3 = cc.colors.collapsedPane,
            BorderSizePixel = 0,
            Text = PANE_ICONS[paneId],
            TextSize = 18,
            Font = Enum.Font.GothamBold,
            TextColor3 = Constants.COLORS.textSecondary,
            Visible = false,
            Parent = paneWrapper
        })

        Create.new("UICorner", {
            CornerRadius = UDim.new(0, 6),
            Parent = collapsedIndicator
        })

        -- Tooltip for collapsed indicator
        collapsedIndicator.MouseEnter:Connect(function()
            collapsedIndicator.BackgroundColor3 = Constants.COLORS.backgroundHover
        end)
        collapsedIndicator.MouseLeave:Connect(function()
            collapsedIndicator.BackgroundColor3 = cc.colors.collapsedPane
        end)

        -- Click to expand
        collapsedIndicator.MouseButton1Click:Connect(function()
            PaneContainer.expandPane(panes, paneId)
        end)

        panes.frames[paneId] = {
            wrapper = paneWrapper,
            content = paneFrame,
            collapsed = collapsedIndicator
        }
    end

    -- Position panes using absolute positioning for precise control
    PaneContainer._repositionPanes(panes)

    return panes
end

--[[
    Reposition all panes based on current collapse states
    @param panes table - Pane container reference
]]
function PaneContainer._repositionPanes(panes)
    local cc = Constants.COMMAND_CENTER
    local paneOrder = { "left", "center", "right" }

    -- Count collapsed panes and calculate widths
    local collapsedCount = 0
    for _, id in ipairs(paneOrder) do
        if panes.collapsed[id] then
            collapsedCount = collapsedCount + 1
        end
    end

    -- Calculate scale width for collapsed panes (use offset for fixed width)
    local collapsedWidth = cc.collapsedPaneWidth
    local gap = cc.paneGap

    -- Calculate widths for each pane
    local widths = {}
    local expandedTotal = 0
    for _, id in ipairs(paneOrder) do
        if not panes.collapsed[id] then
            expandedTotal = expandedTotal + panes.originalWidths[id]
        end
    end

    -- Distribute remaining space to expanded panes
    -- Use scale=1 minus offset for collapsed panes
    local totalCollapsedOffset = collapsedCount * (collapsedWidth + gap)

    for _, id in ipairs(paneOrder) do
        if panes.collapsed[id] then
            widths[id] = { scale = 0, offset = collapsedWidth }
        else
            local proportion = panes.originalWidths[id] / expandedTotal
            widths[id] = { scale = proportion, offset = -totalCollapsedOffset * proportion - gap }
        end
    end

    -- Position panes
    local currentScaleX = 0
    local currentOffsetX = 0

    for _, paneId in ipairs(paneOrder) do
        local frame = panes.frames[paneId]
        local w = widths[paneId]

        local targetPos = UDim2.new(currentScaleX, currentOffsetX, 0, 0)
        local targetSize = UDim2.new(w.scale, w.offset, 1, 0)

        TweenService:Create(frame.wrapper, TWEEN_INFO, {
            Size = targetSize,
            Position = targetPos
        }):Play()

        currentScaleX = currentScaleX + w.scale
        currentOffsetX = currentOffsetX + w.offset + gap
    end
end

--[[
    Collapse a pane to icon-only mode
    @param panes table - Pane container reference
    @param paneId string - "left", "center", or "right"
]]
function PaneContainer.collapsePane(panes, paneId)
    if panes.collapsed[paneId] then return end
    if paneId == "center" then return end -- Center pane should never collapse

    panes.collapsed[paneId] = true
    local frame = panes.frames[paneId]

    -- Hide content, show collapsed indicator
    TweenService:Create(frame.content, TWEEN_INFO, {
        BackgroundTransparency = 1
    }):Play()

    task.delay(0.1, function()
        frame.content.Visible = false
        frame.collapsed.Visible = true
    end)

    PaneContainer._repositionPanes(panes)
end

--[[
    Expand a collapsed pane
    @param panes table - Pane container reference
    @param paneId string - "left", "center", or "right"
]]
function PaneContainer.expandPane(panes, paneId)
    if not panes.collapsed[paneId] then return end

    panes.collapsed[paneId] = false
    local frame = panes.frames[paneId]

    -- Show content, hide collapsed indicator
    frame.collapsed.Visible = false
    frame.content.Visible = true

    TweenService:Create(frame.content, TWEEN_INFO, {
        BackgroundTransparency = 0
    }):Play()

    PaneContainer._repositionPanes(panes)
end

--[[
    Get the content frame for a specific pane
    @param panes table - Pane container reference
    @param paneId string - "left", "center", or "right"
    @return Frame - The content frame to populate
]]
function PaneContainer.getPaneFrame(panes, paneId)
    if panes.frames[paneId] then
        return panes.frames[paneId].content
    end
    return nil
end

--[[
    Check if a pane is collapsed
    @param panes table - Pane container reference
    @param paneId string - "left", "center", or "right"
    @return boolean
]]
function PaneContainer.isPaneCollapsed(panes, paneId)
    return panes.collapsed[paneId] or false
end

--[[
    Handle responsive layout based on widget width
    @param panes table - Pane container reference
    @param width number - Current widget width
]]
function PaneContainer.handleResize(panes, width)
    local cc = Constants.COMMAND_CENTER

    if width < cc.minWidgetWidth then
        -- Collapse side panes
        PaneContainer.collapsePane(panes, "left")
        PaneContainer.collapsePane(panes, "right")
    else
        -- Expand side panes
        PaneContainer.expandPane(panes, "left")
        PaneContainer.expandPane(panes, "right")
    end
end

return PaneContainer
