--[[
    UI/Widgets/Header.lua
    Reactive header bar with Focus HUD

    The Focus HUD displays the top 3 most relevant items from WorkingMemory,
    showing what the AI is currently "paying attention to".

    Each focus card includes a relevance progress bar that updates reactively.
]]

local Constants = require(script.Parent.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Parent.Create)
local Utils = require(script.Parent.Parent.Parent.Shared.Utils)
local SessionManager = require(script.Parent.Parent.Parent.Coordination.SessionManager)
local WorkingMemory = require(script.Parent.Parent.Parent.Memory.WorkingMemory)

local Header = {}

--[[
    Create the header bar with Focus HUD
    @param parent Instance - Parent GUI element
    @return Frame - The header frame
    @return Janitor - Cleanup manager for this widget
]]
function Header.create(parent)
    local janitor = Utils.Janitor.new()

    -- Main header frame
    local headerFrame = Create.new("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = Color3.fromRGB(37, 37, 38),  -- #252526
        BorderSizePixel = 0,
        ZIndex = Constants.UI.ZINDEX.WIDGETS,
        Parent = parent
    })

    janitor:Add(headerFrame, "Destroy")

    -- Title section (left side)
    local titleLabel = Create.new("TextLabel", {
        Name = "Title",
        Size = UDim2.new(0, 150, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Text = "LUX AI",
        TextColor3 = Constants.COLORS.textPrimary,
        Font = Enum.Font.GothamBold,
        TextSize = Constants.UI.FONT_SIZE_HEADER,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = headerFrame
    })

    -- Focus HUD container (right side)
    local focusContainer = Create.new("Frame", {
        Name = "FocusHUD",
        Size = UDim2.new(1, -160, 1, -8),
        Position = UDim2.new(0, 160, 0, 4),
        BackgroundTransparency = 1,
        Parent = headerFrame
    })

    Create.new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = focusContainer
    })

    -- Store focus cards for clearing
    local focusCards = {}

    --[[
        Clear all existing focus cards
    ]]
    local function clearFocusCards()
        for _, card in ipairs(focusCards) do
            if card and card.Parent then
                card:Destroy()
            end
        end
        focusCards = {}
    end

    --[[
        Update the Focus HUD with latest working memory
    ]]
    local function updateFocusHUD()
        clearFocusCards()

        -- Get top 3 script reads from working memory
        local scriptReads = WorkingMemory.findByType("script_read")
        if not scriptReads or #scriptReads == 0 then
            return
        end

        -- Sort by relevance (descending)
        table.sort(scriptReads, function(a, b)
            return (a.relevance or 0) > (b.relevance or 0)
        end)

        -- Render top 3 items
        local maxCards = math.min(3, #scriptReads)
        for i = 1, maxCards do
            local item = scriptReads[i]
            local relevance = item.relevance or 0

            -- Extract file name from path
            local fileName = "Unknown"
            if item.metadata and item.metadata.path then
                fileName = item.metadata.path:match("([^.]+)$") or item.metadata.path
            end

            -- Focus card frame
            local card = Create.new("Frame", {
                Name = "FocusCard_" .. i,
                Size = UDim2.new(0, 120, 1, 0),
                BackgroundColor3 = Color3.fromRGB(45, 45, 48),
                BorderSizePixel = 0,
                LayoutOrder = i,
                Parent = focusContainer
            })

            Create.new("UICorner", {
                CornerRadius = UDim.new(0, 3),
                Parent = card
            })

            -- File name label
            Create.new("TextLabel", {
                Name = "FileName",
                Size = UDim2.new(1, -8, 1, -10),
                Position = UDim2.new(0, 4, 0, 2),
                BackgroundTransparency = 1,
                Text = fileName,
                TextColor3 = Constants.COLORS.textSecondary,
                Font = Constants.UI.FONT_CODE,
                TextSize = Constants.UI.FONT_SIZE_TINY,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = card
            })

            -- Relevance progress bar container
            local progressContainer = Create.new("Frame", {
                Name = "ProgressContainer",
                Size = UDim2.new(1, -8, 0, 2),
                Position = UDim2.new(0, 4, 1, -4),
                BackgroundColor3 = Color3.fromRGB(30, 30, 30),
                BorderSizePixel = 0,
                Parent = card
            })

            -- Relevance progress bar (fill)
            local progressBar = Create.new("Frame", {
                Name = "ProgressBar",
                Size = UDim2.new(relevance / 100, 0, 1, 0),
                BackgroundColor3 = Color3.fromRGB(0, 122, 204),  -- #007ACC
                BorderSizePixel = 0,
                Parent = progressContainer
            })

            table.insert(focusCards, card)
        end
    end

    -- Subscribe to SessionManager updates
    local updateConnection = SessionManager.OnUpdate:Connect(function()
        updateFocusHUD()
    end)
    janitor:Add(updateConnection, "Disconnect")

    -- Initial render
    updateFocusHUD()

    return headerFrame, janitor
end

return Header
