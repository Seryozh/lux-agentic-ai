--[[
    UI/InputApproval.lua
    Inline approval prompt with Modal Overlay for detailed review
    Enhanced with explanations and better UX
]]

local Constants = require(script.Parent.Parent.Constants)
local Create = require(script.Parent.Create)
local Utils = require(script.Parent.Parent.Utils)

local InputApproval = {}

-- Operation type icons and labels
local OPERATION_ICONS = {
	edit_script = "??",
	patch_script = "??",
	create_script = "?",
	create_instance = "??",
	set_instance_properties = "??",
	delete_instance = "???"
}

local OPERATION_LABELS = {
	edit_script = "Edit Script",
	patch_script = "Patch Script",
	create_script = "Create Script",
	create_instance = "Create Instance",
	set_instance_properties = "Modify Properties",
	delete_instance = "Delete Instance"
}

-- Operations that should show "Review Changes" button (code-related)
local REVIEWABLE_OPERATIONS = {
	edit_script = true,
	patch_script = true,
	create_script = true,
}

--[[
    Get a human-readable explanation for an operation
    @param operation table - The operation object
    @return string - Explanation text
]]
local function getOperationExplanation(operation)
	local opType = operation.type
	local data = operation.data or {}

	if opType == "edit_script" then
		return data.explanation or "Rewriting the entire script with updated code"

	elseif opType == "patch_script" then
		local searchPreview = (data.search_content or ""):sub(1, 40):gsub("\n", " ")
		if #(data.search_content or "") > 40 then searchPreview = searchPreview .. "..." end
		return string.format("Finding and replacing code: \"%s\"", searchPreview)

	elseif opType == "create_script" then
		return data.purpose or "Creating a new script"

	elseif opType == "create_instance" then
		local propsCount = 0
		if data.properties then
			for _ in pairs(data.properties) do propsCount = propsCount + 1 end
		end
		local propsText = propsCount > 0 and string.format(" with %d properties", propsCount) or ""
		return string.format("Creating a new %s%s", data.className or "Instance", propsText)

	elseif opType == "set_instance_properties" then
		local propsList = {}
		if data.newProperties then
			for propName, _ in pairs(data.newProperties) do
				table.insert(propsList, propName)
			end
		end
		if #propsList > 0 then
			local propsStr = table.concat(propsList, ", ")
			if #propsStr > 50 then propsStr = propsStr:sub(1, 47) .. "..." end
			return string.format("Changing: %s", propsStr)
		end
		return "Modifying instance properties"

	elseif opType == "delete_instance" then
		local info = data.instanceInfo or {}
		local details = {}
		if info.descendants and info.descendants > 0 then
			table.insert(details, string.format("%d descendants", info.descendants))
		end
		if info.hasScripts then
			table.insert(details, "contains scripts")
		end
		if #details > 0 then
			return string.format("?? Warning: %s", table.concat(details, ", "))
		end
		return string.format("Removing %s from the game", info.className or "instance")
	end

	return "Requesting permission to make changes"
end

--[[
    Add hover effect to a button
    @param button TextButton
    @param normalColor Color3
    @param hoverColor Color3 (optional, defaults to brighter version)
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
    Create a line of code for the diff view
    @param lineNum number
    @param content string
    @param type string "context"|"add"|"remove"
    @param parent Instance
    @return Frame
]]
local function createDiffLine(lineNum, content, type, parent)
	-- Sleeker colors
	local bgColor = Color3.fromRGB(25, 25, 28) -- Default dark code bg
	local textColor = Color3.fromRGB(220, 220, 220)
	local prefix = " "
	local gutterColor = Color3.fromRGB(35, 35, 40)

	if type == "add" then
		bgColor = Color3.fromRGB(35, 65, 35) -- Softer dark green
		textColor = Color3.fromRGB(200, 255, 200)
		prefix = "+"
	elseif type == "remove" then
		bgColor = Color3.fromRGB(65, 35, 35) -- Softer dark red
		textColor = Color3.fromRGB(255, 200, 200)
		prefix = "-"
	end

	local lineFrame = Create.new("Frame", {
		BackgroundTransparency = 0,
		BackgroundColor3 = bgColor,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 20), -- Slightly taller for readability
		Parent = parent
	})

	-- Gutter (Line Number)
	local gutter = Create.new("Frame", {
		Size = UDim2.new(0, 40, 1, 0),
		BackgroundColor3 = gutterColor,
		BorderSizePixel = 0,
		Parent = lineFrame
	})

	Create.new("TextLabel", {
		Text = tostring(lineNum),
		Size = UDim2.new(1, -8, 1, 0), -- Padding right
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(100, 100, 100),
		Font = Enum.Font.Code,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = gutter
	})

	-- Content
	Create.new("TextLabel", {
		Text = content, -- No prefix in text, we use color/gutter
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.new(0, 50, 0, 0), -- 40 gutter + 10 padding
		BackgroundTransparency = 1,
		TextColor3 = textColor,
		Font = Enum.Font.Code,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = lineFrame
	})

	-- Add +/- marker in gutter
	if prefix ~= " " then
		Create.new("TextLabel", {
			Text = prefix,
			Size = UDim2.new(0, 10, 1, 0),
			Position = UDim2.new(0, 2, 0, 0),
			BackgroundTransparency = 1,
			TextColor3 = textColor,
			Font = Enum.Font.Code,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = gutter
		})
	end

	return lineFrame
end

--[[
    Create diff viewer component
    @param oldSource string
    @param newSource string
    @param parent Instance
]]
local function createDiffViewer(oldSource, newSource, parent)
	-- Container with border
	local container = Create.new("Frame", {
		Size = UDim2.new(1, 0, 1, 0), -- Fill available space
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(20, 20, 22),
		BorderSizePixel = 1,
		BorderColor3 = Color3.fromRGB(60, 60, 70),
		Parent = parent
	})

	local scrollingFrame = Create.new("ScrollingFrame", {
		Size = UDim2.new(1, -2, 1, -2),
		Position = UDim2.new(0, 1, 0, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90),
		Parent = container
	})

	local layout = Create.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scrollingFrame
	})

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
	end)

	local diffs = Utils.generateDiff(oldSource, newSource)

	local MAX_LINES = 2000 -- Increased for modal
	if #diffs > MAX_LINES then
		Create.new("TextLabel", {
			Text = string.format("... Showing first %d lines of changes ...", MAX_LINES),
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			TextColor3 = Constants.COLORS.textMuted,
			Parent = scrollingFrame
		})
	end

	for i = 1, math.min(#diffs, MAX_LINES) do
		local line = diffs[i]
		createDiffLine(line.lineNum, line.content, line.type, scrollingFrame)
	end
end

--[[
    Create patch preview component (search/replace)
    @param searchContent string
    @param replaceContent string
    @param parent Instance
]]
local function createPatchPreview(searchContent, replaceContent, parent)
	-- Container with border
	local container = Create.new("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(20, 20, 22),
		BorderSizePixel = 1,
		BorderColor3 = Color3.fromRGB(60, 60, 70),
		Parent = parent
	})

	local scrollingFrame = Create.new("ScrollingFrame", {
		Size = UDim2.new(1, -2, 1, -2),
		Position = UDim2.new(0, 1, 0, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90),
		Parent = container
	})

	local layout = Create.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scrollingFrame
	})

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
	end)

	local lineCount = 0

	-- 1. Search Content (Removed - Red)
	local searchLines = Utils.splitLines(searchContent)
	for i, line in ipairs(searchLines) do
		-- Try to parse line number from context if possible (not trivial here without file access)
		-- So we just use relative line numbers 1..N
		lineCount = lineCount + 1
		createDiffLine(lineCount, line, "remove", scrollingFrame)
	end

	-- Separator
	if #searchLines > 0 and #replaceContent > 0 then
		local sep = Create.new("Frame", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundColor3 = Color3.fromRGB(30, 30, 35),
			BorderSizePixel = 0,
			Parent = scrollingFrame
		})
		Create.new("TextLabel", {
			Text = "? BECOMES ?",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			TextColor3 = Color3.fromRGB(100, 100, 100),
			Font = Enum.Font.Code,
			TextSize = 12,
			Parent = sep
		})
	end

	-- 2. Replace Content (Added - Green)
	local replaceLines = Utils.splitLines(replaceContent)
	for i, line in ipairs(replaceLines) do
		lineCount = lineCount + 1
		createDiffLine(lineCount, line, "add", scrollingFrame)
	end
end

--[[
    Create code preview component (full source)
    @param source string
    @param parent Instance
]]
local function createCodePreview(source, parent)
	-- Container with border
	local container = Create.new("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(20, 20, 22),
		BorderSizePixel = 1,
		BorderColor3 = Color3.fromRGB(60, 60, 70),
		Parent = parent
	})

	local scrollingFrame = Create.new("ScrollingFrame", {
		Size = UDim2.new(1, -2, 1, -2),
		Position = UDim2.new(0, 1, 0, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90),
		Parent = container
	})

	local layout = Create.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scrollingFrame
	})

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
	end)

	local lines = Utils.splitLines(source)
	local MAX_LINES = 2000

	for i = 1, math.min(#lines, MAX_LINES) do
		createDiffLine(i, lines[i], "context", scrollingFrame)
	end
end

--[[
    Find the main frame (root) to attach modal to
]]
local function findMainFrame(inputContainer)
	local current = inputContainer
	while current and current.Parent do
		if current.Name == "MainFrame" then
			return current
		end
		current = current.Parent
	end
	return inputContainer.Parent -- Fallback
end

--[[
    Show the full screen review modal
]]
local function showReviewModal(parent, operation, onApprove, onDeny, onClose)
	-- Fix: If parent is MainFrame, use its parent (Widget) to avoid UIListLayout issues
	local targetParent = parent
	if parent.Name == "MainFrame" and parent.Parent then
		targetParent = parent.Parent
	end

	local modal = Create.new("Frame", {
		Name = "ReviewModal",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 1, 0), -- Start off-screen (bottom)
		BackgroundColor3 = Color3.fromRGB(25, 25, 30),
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = targetParent
	})

	-- Animate in
	local tweenService = game:GetService("TweenService")
	tweenService:Create(modal, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0)
	}):Play()

	-- 1. Header (Fixed Top)
	local header = Create.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Color3.fromRGB(35, 35, 40),
		BorderSizePixel = 0,
		ZIndex = 11, -- Fix: Ensure on top of modal
		Parent = modal
	})

	local icon = OPERATION_ICONS[operation.type] or "??"
	local label = OPERATION_LABELS[operation.type] or operation.type
	local titleText = string.format("%s %s", icon, label)

	Create.new("TextLabel", {
		Text = titleText,
		Size = UDim2.new(0.5, -20, 1, 0),
		Position = UDim2.new(0, 20, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_HEADER,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header
	})

	Create.new("TextLabel", {
		Text = operation.path or operation.data.path or "",
		Size = UDim2.new(0.5, -20, 1, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header
	})

	-- 2. Footer (Fixed Bottom)
	local footer = Create.new("Frame", {
		Name = "Footer",
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.new(0, 0, 1, -60),
		BackgroundColor3 = Color3.fromRGB(35, 35, 40),
		BorderSizePixel = 0,
		ZIndex = 11, -- Fix: Ensure on top of modal
		Parent = modal
	})

	local buttonContainer = Create.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 320, 0, 40),
		BackgroundTransparency = 1,
		Parent = footer
	})

	Create.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 20),
		Parent = buttonContainer
	})

	-- Deny Button (matching inline button colors)
	local denyBtn = Create.new("TextButton", {
		Text = "? Deny Changes",
		Size = UDim2.new(0, 150, 1, 0),
		BackgroundColor3 = Constants.COLORS.accentError,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Constants.UI.FONT_HEADER,
		TextSize = 15,
		Parent = buttonContainer
	})
	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = denyBtn })
	addHoverEffect(denyBtn, Constants.COLORS.accentError)

	denyBtn.MouseButton1Click:Connect(function()
		onDeny()
		tweenService:Create(modal, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0, 0, 1, 0)
		}):Play()
		task.wait(0.2)
		onClose()
		modal:Destroy()
	end)

	-- Approve Button (matching inline button colors)
	local approveBtn = Create.new("TextButton", {
		Text = "? Approve Changes",
		Size = UDim2.new(0, 150, 1, 0),
		BackgroundColor3 = Constants.COLORS.accentSuccess,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Constants.UI.FONT_HEADER,
		TextSize = 15,
		Parent = buttonContainer
	})
	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = approveBtn })
	addHoverEffect(approveBtn, Constants.COLORS.accentSuccess)

	approveBtn.MouseButton1Click:Connect(function()
		onApprove()
		tweenService:Create(modal, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0, 0, 1, 0)
		}):Play()
		task.wait(0.2)
		onClose()
		modal:Destroy()
	end)

	-- 3. Content Body (Fills middle)
	local body = Create.new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -40, 1, -130), -- Total - Header(50) - Footer(60) - Padding(20)
		Position = UDim2.new(0, 20, 0, 60), -- Top 60 (Header + Pad)
		BackgroundTransparency = 1,
		ZIndex = 11, -- Fix: Ensure on top of modal
		Parent = modal
	})

	-- Description (Top of Body)
	local descText = operation.description or operation.data.explanation or operation.data.purpose or "No description provided."
	local description = Create.new("TextLabel", {
		Text = descText,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = body
	})

	-- Preview Frame (Fills rest of Body)
	local previewFrame = Create.new("Frame", {
		Name = "PreviewFrame",
		BackgroundTransparency = 1,
		Parent = body
	})

	-- Manual layout update
	local function updateLayout()
		local descHeight = description.AbsoluteSize.Y
		previewFrame.Position = UDim2.new(0, 0, 0, descHeight + 10)
		previewFrame.Size = UDim2.new(1, 0, 1, -(descHeight + 10))
	end

	description:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
	updateLayout() -- Initial calculation

	if operation.type == "edit_script" then
		createDiffViewer(operation.data.oldSource, operation.data.newSource, previewFrame)
	elseif operation.type == "patch_script" then
		createPatchPreview(operation.data.search_content, operation.data.replace_content, previewFrame)
	elseif operation.type == "create_script" then
		createCodePreview(operation.data.source, previewFrame)
	elseif operation.type == "set_instance_properties" then
		local diffText = Utils.formatPropertyDiff(operation.data.oldProperties, operation.data.newProperties)
		createCodePreview(diffText, previewFrame)
	else
		createCodePreview("No preview available for this operation.", previewFrame)
	end
end

--[[
    Show inline approval prompt in the input area (Expanded with all buttons)
    @param inputContainer Frame - The input container to transform
    @param operation table - Operation details { type, path, description, data }
    @param onApprove function - Callback when user approves
    @param onDeny function - Callback when user denies
    @return Frame - The approval prompt frame (to be destroyed later)
]]
function InputApproval.show(inputContainer, operation, onApprove, onDeny)
	-- Hide existing input elements
	local textInput = inputContainer:FindFirstChild("TextInput")
	local sendButton = inputContainer:FindFirstChild("SendButton")

	if textInput then textInput.Visible = false end
	if sendButton then sendButton.Visible = false end

	-- Check if this operation should show Review Changes button
	local showReviewButton = REVIEWABLE_OPERATIONS[operation.type] or false

	-- Expand container to fit 3 rows (title, explanation, buttons)
	local originalHeight = inputContainer.Size.Y.Offset
	inputContainer:SetAttribute("OriginalHeight", originalHeight)
	inputContainer.Size = UDim2.new(1, 0, 0, 110) -- Slightly taller for explanation

	-- Create approval prompt frame
	local approvalFrame = Create.new("Frame", {
		Name = "ApprovalPrompt",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(30, 30, 35),
		Parent = inputContainer
	})

	-- Row 1: Icon + Title + Path
	local icon = OPERATION_ICONS[operation.type] or "??"
	local label = OPERATION_LABELS[operation.type] or operation.type
	local targetPath = operation.path or (operation.data and operation.data.path) or ""
	local summary = string.format("%s %s: %s", icon, label, targetPath)

	Create.new("TextLabel", {
		Name = "TitleLabel",
		Text = summary,
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0, 10, 0, 6),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.textPrimary,
		Font = Constants.UI.FONT_HEADER,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = approvalFrame
	})

	-- Row 2: Explanation text (new!)
	local explanationText = getOperationExplanation(operation)
	Create.new("TextLabel", {
		Name = "ExplanationLabel",
		Text = explanationText,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 28),
		BackgroundTransparency = 1,
		TextColor3 = Constants.COLORS.textSecondary,
		Font = Constants.UI.FONT_NORMAL,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = approvalFrame
	})

	-- Row 3: Buttons
	local buttonRow = Create.new("Frame", {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.new(0, 10, 0, 55),
		BackgroundTransparency = 1,
		Parent = approvalFrame
	})

	-- Calculate button sizes based on whether Review is shown
	local reviewWidth, approveWidth, denyWidth, approvePos, denyPos

	if showReviewButton then
		-- 3 buttons: Review (50%), Approve (25%), Deny (25%)
		reviewWidth = UDim2.new(0.5, -5, 1, 0)
		approveWidth = UDim2.new(0.25, -5, 1, 0)
		denyWidth = UDim2.new(0.25, -5, 1, 0)
		approvePos = UDim2.new(0.5, 5, 0, 0)
		denyPos = UDim2.new(0.75, 5, 0, 0)
	else
		-- 2 buttons only: Approve (50%), Deny (50%)
		approveWidth = UDim2.new(0.5, -5, 1, 0)
		denyWidth = UDim2.new(0.5, -5, 1, 0)
		approvePos = UDim2.new(0, 0, 0, 0)
		denyPos = UDim2.new(0.5, 5, 0, 0)
	end

	-- Review Button (only for code operations)
	if showReviewButton then
		local reviewBtn = Create.new("TextButton", {
			Text = "?? Review Code",
			Size = reviewWidth,
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = Constants.COLORS.accentPrimary,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Constants.UI.FONT_HEADER,
			TextSize = 13,
			Parent = buttonRow
		})
		Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = reviewBtn })
		addHoverEffect(reviewBtn, Constants.COLORS.accentPrimary)

		reviewBtn.MouseButton1Click:Connect(function()
			local mainFrame = findMainFrame(inputContainer)
			if mainFrame then
				showReviewModal(mainFrame, operation, onApprove, onDeny, function()
					-- Modal closed, nothing to do here (Main handles callback)
				end)
			end
		end)
	end

	-- Approve Button (Green)
	local approveBtn = Create.new("TextButton", {
		Text = "? Approve",
		Size = approveWidth,
		Position = approvePos,
		BackgroundColor3 = Constants.COLORS.accentSuccess,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Constants.UI.FONT_HEADER,
		TextSize = 13,
		Parent = buttonRow
	})
	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = approveBtn })
	addHoverEffect(approveBtn, Constants.COLORS.accentSuccess)
	approveBtn.MouseButton1Click:Connect(function() if onApprove then onApprove() end end)

	-- Deny Button (Red)
	local denyBtn = Create.new("TextButton", {
		Text = "? Deny",
		Size = denyWidth,
		Position = denyPos,
		BackgroundColor3 = Constants.COLORS.accentError,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Constants.UI.FONT_HEADER,
		TextSize = 13,
		Parent = buttonRow
	})
	Create.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = denyBtn })
	addHoverEffect(denyBtn, Constants.COLORS.accentError)
	denyBtn.MouseButton1Click:Connect(function() if onDeny then onDeny() end end)

	return approvalFrame
end

--[[
    Hide approval prompt and restore normal input
    @param inputContainer Frame - The input container
]]
function InputApproval.hide(inputContainer)
	-- Restore size
	local originalHeight = inputContainer:GetAttribute("OriginalHeight")
	if originalHeight then
		inputContainer.Size = UDim2.new(1, 0, 0, originalHeight)
	end

	-- Remove approval prompt
	local approvalPrompt = inputContainer:FindFirstChild("ApprovalPrompt")
	if approvalPrompt then
		approvalPrompt:Destroy()
	end

	-- Restore input elements
	local textInput = inputContainer:FindFirstChild("TextInput")
	local sendButton = inputContainer:FindFirstChild("SendButton")

	if textInput then textInput.Visible = true end
	if sendButton then sendButton.Visible = true end
end

return InputApproval
