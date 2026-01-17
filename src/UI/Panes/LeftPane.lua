--[[
    LeftPane.lua - "Context Map" (World State Visualization)

    Displays the project structure with trauma overlay.
    Always shows root folders even if empty.
    Trauma highlights from DecisionMemory appear as red strokes.
]]

local Constants = require(script.Parent.Parent.Parent.Shared.Constants)
local Create = require(script.Parent.Parent.Create)
local Utils = require(script.Parent.Parent.Parent.Shared.Utils)
local SessionManager = require(script.Parent.Parent.Parent.Coordination.SessionManager)
local IndexManager = require(script.Parent.Parent.Parent.Shared.IndexManager)
local DecisionMemory = require(script.Parent.Parent.Parent.Memory.DecisionMemory)

local LeftPane = {}

-- Store file tree labels for reactive trauma highlighting
local fileTreeLabels = {}

-- Guard flag to prevent race condition during async scan
local scanComplete = false

--[[
    Create the Left Pane with Context Map
    @param parent Frame
    @return Frame - The pane container
    @return Janitor - Cleanup manager
]]
function LeftPane.create(parent)
    local janitor = Utils.Janitor.new()

    -- Main container
    local paneFrame = Create.new("Frame", {
        Name = "LeftPane",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Constants.COMMAND_CENTER.colors.paneBackground,
        BorderSizePixel = 0,
        Parent = parent
    })

    janitor:Add(paneFrame, "Destroy")

    -- Scrolling container for file tree
    local scrollingFrame = Create.new("ScrollingFrame", {
        Name = "FileTree",
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
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = scrollingFrame
    })

    Create.new("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scrollingFrame
    })

    -- Header
    local header = Create.new("TextLabel", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "🗺️ CONTEXT MAP",
        TextColor3 = Constants.COLORS.textPrimary,
        Font = Enum.Font.GothamBold,
        TextSize = Constants.UI.FONT_SIZE_SUBHEADER,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 0,
        Parent = scrollingFrame
    })

    --[[
        Create a file tree item
        @param path string - Full path
        @param isFolder boolean
        @param depth number - Indentation level
        @param layoutOrder number
        @return Frame - The item frame with label and optional stroke
    ]]
    local function createFileItem(path, isFolder, depth, layoutOrder)
        local indentPx = depth * 16

        local itemFrame = Create.new("Frame", {
            Name = "Item_" .. layoutOrder,
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            LayoutOrder = layoutOrder,
            Parent = scrollingFrame
        })

        local icon = isFolder and Constants.ICONS.FOLDER or Constants.ICONS.SCRIPT
        local fileName = path:match("([^.]+)$") or path

        local label = Create.new("TextLabel", {
            Name = "Label",
            Size = UDim2.new(1, -indentPx, 1, 0),
            Position = UDim2.new(0, indentPx, 0, 0),
            BackgroundTransparency = 1,
            Text = icon .. " " .. fileName,
            TextColor3 = Constants.COLORS.textSecondary,
            Font = Constants.UI.FONT_CODE,
            TextSize = Constants.UI.FONT_SIZE_TINY,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = itemFrame
        })

        -- Create UIStroke for trauma highlighting (initially invisible)
        local traumaStroke = Create.new("UIStroke", {
            Name = "TraumaStroke",
            Color = Color3.fromRGB(255, 80, 80),  -- #FF5050 Red
            Thickness = 2,
            Transparency = 1,  -- Hidden by default
            Enabled = false,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Parent = label
        })

        -- Store reference for reactive updates
        fileTreeLabels[path] = {
            label = label,
            stroke = traumaStroke,
            isFolder = isFolder
        }

        return itemFrame
    end

    --[[
        Build the file tree from IndexManager scan results
        ALWAYS shows root folders even if empty
    ]]
    local function buildFileTree()
        -- Clear existing tree
        for _, child in ipairs(scrollingFrame:GetChildren()) do
            if child:IsA("Frame") and child.Name:find("Item_") then
                child:Destroy()
            end
        end
        fileTreeLabels = {}
        scanComplete = false

        -- Scan project structure
        local scanResults = IndexManager.scanScriptsAsync()

        -- FALLBACK: If scan fails, show error but continue
        if not scanResults or not scanResults.items then
            createFileItem("⚠️ Scan Failed", false, 0, 1)
            scanComplete = true
            return
        end

        -- Build location map
        local locations = {}
        for _, item in ipairs(scanResults.items) do
            local path = item.path or ""
            local location = path:match("^([^.]+)") or "Unknown"

            if not locations[location] then
                locations[location] = {}
            end
            table.insert(locations[location], item)
        end

        -- ENFORCE: Always show root folders from SCAN_LOCATIONS
        local rootFolders = Constants.INDEXING and Constants.INDEXING.SCAN_LOCATIONS or Constants.SCAN_LOCATIONS
        for _, rootName in ipairs(rootFolders) do
            if not locations[rootName] then
                locations[rootName] = {}  -- Empty array but shows folder
            end
        end

        -- Render tree (grouped by location)
        local order = 1
        for location, items in pairs(locations) do
            -- Folder header
            createFileItem(location, true, 0, order)
            order = order + 1

            -- Items in this location
            for _, item in ipairs(items) do
                local itemName = item.path or "Unknown"
                createFileItem(itemName, false, 1, order)
                order = order + 1
            end
        end

        -- Mark scan as complete
        scanComplete = true
    end

    --[[
        Update trauma indicators (reactive)
        Called on every SessionManager.OnUpdate pulse
    ]]
    local function updateTraumaIndicators()
        -- Guard: Don't update until scan completes
        if not scanComplete then
            return
        end

        -- Get flagged scripts from DecisionMemory
        local flaggedScripts = DecisionMemory.getFlaggedScripts and DecisionMemory.getFlaggedScripts() or {}

        -- Convert to lookup table for fast checking
        local flaggedLookup = {}
        for _, flagged in ipairs(flaggedScripts) do
            local path = type(flagged) == "table" and flagged.path or flagged
            if path then
                flaggedLookup[path] = true
            end
        end

        -- Update all file tree labels
        for path, item in pairs(fileTreeLabels) do
            if not item.isFolder then
                local isFlagged = flaggedLookup[path] == true

                if isFlagged then
                    -- Enable trauma stroke (red highlight)
                    item.stroke.Enabled = true
                    item.stroke.Transparency = 0.5
                    item.label.TextColor3 = Color3.fromRGB(255, 180, 180)
                else
                    -- Disable trauma stroke (normal)
                    item.stroke.Enabled = false
                    item.stroke.Transparency = 1
                    item.label.TextColor3 = Constants.COLORS.textSecondary
                end
            end
        end
    end

    -- Build file tree ONCE on initialization
    buildFileTree()

    -- Subscribe to SessionManager for reactive trauma updates
    if SessionManager.OnUpdate then
        local updateConnection = SessionManager.OnUpdate:Connect(function()
            updateTraumaIndicators()
        end)
        janitor:Add(updateConnection, "Disconnect")
    end

    -- Initial trauma check
    updateTraumaIndicators()

    return paneFrame, janitor
end

return LeftPane
