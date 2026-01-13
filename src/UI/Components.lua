--[[
    UI/Components.lua
    Reusable UI component factories to reduce boilerplate
]]

local Constants = require(script.Parent.Parent.Constants)
local Create = require(script.Parent.Create)

local Components = {}

--[[
    Create a rounded panel (Frame with UICorner and UIPadding)
    @param props table - Properties for the frame
    @param padding number - Padding amount (default 12)
    @param cornerRadius number - Corner radius (default Constants.UI.CORNER_RADIUS)
    @return Frame
]]
function Components.RoundedPanel(props, padding, cornerRadius)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or Constants.COLORS.backgroundLight
	props.BorderSizePixel = props.BorderSizePixel or 0

	local frame = Create.new("Frame", props)

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, cornerRadius or Constants.UI.CORNER_RADIUS),
		Parent = frame
	})

	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, padding or 12),
		PaddingBottom = UDim.new(0, padding or 12),
		PaddingLeft = UDim.new(0, padding or 12),
		PaddingRight = UDim.new(0, padding or 12),
		Parent = frame
	})

	return frame
end

--[[
    Create a button (TextButton with rounded corners)
    @param props table - Properties for the button
    @param cornerRadius number - Corner radius (default Constants.UI.CORNER_RADIUS)
    @return TextButton
]]
function Components.Button(props, cornerRadius)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or Constants.COLORS.accentPrimary
	props.BorderSizePixel = props.BorderSizePixel or 0
	props.Font = props.Font or Constants.UI.FONT_NORMAL
	props.TextSize = props.TextSize or Constants.UI.FONT_SIZE_NORMAL
	props.TextColor3 = props.TextColor3 or Constants.COLORS.textPrimary

	local button = Create.new("TextButton", props)

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, cornerRadius or Constants.UI.CORNER_RADIUS),
		Parent = button
	})

	return button
end

--[[
    Create a text label with default styling
    @param props table - Properties for the label
    @return TextLabel
]]
function Components.TextLabel(props)
	props = props or {}
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Constants.UI.FONT_NORMAL
	props.TextSize = props.TextSize or Constants.UI.FONT_SIZE_NORMAL
	props.TextColor3 = props.TextColor3 or Constants.COLORS.textPrimary
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Top
	props.TextWrapped = props.TextWrapped or true

	return Create.new("TextLabel", props)
end

--[[
    Create a scrolling frame with auto-sizing canvas
    @param props table - Properties for the scrolling frame
    @param padding number - Internal padding (default 8)
    @param cornerRadius number - Corner radius (default Constants.UI.CORNER_RADIUS)
    @return ScrollingFrame
]]
function Components.ScrollingFrame(props, padding, cornerRadius)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or Constants.COLORS.backgroundLight
	props.BorderSizePixel = props.BorderSizePixel or 0
	props.ScrollBarThickness = props.ScrollBarThickness or 6
	props.AutomaticCanvasSize = props.AutomaticCanvasSize or Enum.AutomaticSize.Y
	props.CanvasSize = props.CanvasSize or UDim2.new(0, 0, 0, 0)

	local frame = Create.new("ScrollingFrame", props)

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, cornerRadius or Constants.UI.CORNER_RADIUS),
		Parent = frame
	})

	local paddingValue = padding or 8
	Create.new("UIPadding", {
		PaddingTop = UDim.new(0, paddingValue),
		PaddingBottom = UDim.new(0, paddingValue),
		PaddingLeft = UDim.new(0, paddingValue),
		PaddingRight = UDim.new(0, paddingValue),
		Parent = frame
	})

	return frame
end

--[[
    Create a UIListLayout with standard settings
    @param props table - Properties for the layout
    @return UIListLayout
]]
function Components.ListLayout(props)
	props = props or {}
	props.Padding = props.Padding or UDim.new(0, Constants.UI.ELEMENT_GAP)
	props.SortOrder = props.SortOrder or Enum.SortOrder.LayoutOrder

	return Create.new("UIListLayout", props)
end

--[[
    Create a text input field with rounded corners
    @param props table - Properties for the input
    @param cornerRadius number - Corner radius (default 6)
    @return TextBox
]]
function Components.TextInput(props, cornerRadius)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or Constants.COLORS.backgroundDark
	props.BorderSizePixel = props.BorderSizePixel or 0
	props.Font = props.Font or Constants.UI.FONT_NORMAL
	props.TextSize = props.TextSize or Constants.UI.FONT_SIZE_NORMAL
	props.TextColor3 = props.TextColor3 or Constants.COLORS.textPrimary
	props.PlaceholderColor3 = props.PlaceholderColor3 or Constants.COLORS.textMuted
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.ClearTextOnFocus = props.ClearTextOnFocus == nil and false or props.ClearTextOnFocus

	local textbox = Create.new("TextBox", props)

	Create.new("UICorner", {
		CornerRadius = UDim.new(0, cornerRadius or 6),
		Parent = textbox
	})

	Create.new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		Parent = textbox
	})

	return textbox
end

return Components
