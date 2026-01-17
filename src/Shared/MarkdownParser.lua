--[[
    MarkdownParser.lua
    Simplified markdown to Roblox RichText converter

    Supports:
    - **bold** -> <b>bold</b>
    - `code` -> <font face="Code">code</font>
    - Bullet lists -> bullet item
    - Code blocks collapsed by default (v2.1)
]]

local MarkdownParser = {}

-- Hide code blocks configuration
MarkdownParser.hideCodeBlocks = true

--[[
    Extract code blocks from text
    @param text string - Text containing code blocks
    @return string - Text with code blocks replaced by placeholders
    @return table - Array of extracted code blocks
]]
function MarkdownParser.extractCodeBlocks(text)
	if not text then return "", {} end

	local codeBlocks = {}
	local placeholder = "[CODE_BLOCK_%d]"
	local index = 0

	-- Extract fenced code blocks (```lua ... ```)
	text = text:gsub("```(%w*)\n?(.-)\n?```", function(lang, code)
		index = index + 1
		table.insert(codeBlocks, {
			language = lang ~= "" and lang or "lua",
			code = code,
			lines = select(2, code:gsub("\n", "\n")) + 1
		})
		return string.format(placeholder, index)
	end)

	return text, codeBlocks
end

--[[
    Parse markdown text into Roblox RichText
    @param text string - Markdown text
    @param options table|nil - { hideCodeBlocks: boolean }
    @return string - RichText formatted string
    @return table|nil - Extracted code blocks if hideCodeBlocks enabled
]]
function MarkdownParser.parse(text, options)
	if not text then return "" end

	options = options or {}
	local hideCode = options.hideCodeBlocks
	if hideCode == nil then hideCode = MarkdownParser.hideCodeBlocks end

	local codeBlocks = nil

	-- 1. Extract code blocks if hiding them
	if hideCode then
		text, codeBlocks = MarkdownParser.extractCodeBlocks(text)
	end

	-- 2. Escape any HTML-like brackets that might break RichText
	text = text:gsub("<", "&lt;"):gsub(">", "&gt;")

	-- 3. Code blocks (``` ... ```) - if not hiding, convert to compact indicator
	if not hideCode then
		text = text:gsub("```%w*\n?(.-)\n?```", function(code)
			local lineCount = select(2, code:gsub("\n", "\n")) + 1
			if lineCount > 5 then
				-- Truncate long code blocks
				local preview = code:match("^([^\n]*)")
				return '<font face="Code" color="rgb(140,140,150)">' .. preview .. '... (' .. lineCount .. ' lines)</font>'
			end
			return '<font face="Code" color="rgb(140,140,150)">' .. code .. '</font>'
		end)
	else
		-- Replace code block placeholders with compact indicators
		text = text:gsub("%[CODE_BLOCK_(%d+)%]", function(idx)
			local block = codeBlocks[tonumber(idx)]
			if block then
				return '<font color="rgb(100,130,170)">[' .. block.lines .. ' lines of ' .. block.language .. ' code]</font>'
			end
			return "[code]"
		end)
	end

	-- 4. Inline code (`code`) - convert to monospace (keep inline code visible)
	text = text:gsub("`([^`\n]+)`", '<font face="Code" color="rgb(140,140,150)">%1</font>')

	-- 5. Bold (**text**)
	text = text:gsub("%*%*([^%*]+)%*%*", "<b>%1</b>")

	-- 6. Process line by line for bullets and headers
	local lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		-- Headers (# ## ###)
		local h1 = line:match("^#%s+(.+)$")
		if h1 then
			line = "<b>" .. h1 .. "</b>"
		else
			local h2 = line:match("^##%s+(.+)$")
			if h2 then
				line = "<b>" .. h2 .. "</b>"
			else
				local h3 = line:match("^###%s+(.+)$")
				if h3 then
					line = "<b>" .. h3 .. "</b>"
				end
			end
		end

		-- Bullet lists (- item or * item)
		local bullet = line:match("^%s*[%-*]%s+(.+)$")
		if bullet then
			line = "• " .. bullet
		end

		-- Numbered lists (1. item)
		local num, content = line:match("^%s*(%d+)%.%s+(.+)$")
		if num and content then
			line = num .. ". " .. content
		end

		table.insert(lines, line)
	end

	text = table.concat(lines, "\n")
	-- Remove trailing newline
	text = text:gsub("\n$", "")

	if hideCode and codeBlocks and #codeBlocks > 0 then
		return text, codeBlocks
	end
	return text
end

--[[
    Strip all markdown formatting (return plain text)
    @param text string
    @return string
]]
function MarkdownParser.stripMarkdown(text)
	if not text then return "" end

	text = text:gsub("```%w*\n?.-\n?```", "%1")
	text = text:gsub("`([^`]+)`", "%1")
	text = text:gsub("%*%*([^%*]+)%*%*", "%1")
	text = text:gsub("^#+ ", "")
	text = text:gsub("\n#+ ", "\n")

	return text
end

--[[
    Sanitize text for RichText rendering
    Escapes brackets [ and ] to prevent conflicts with internal placeholders
    @param text string
    @return string - Sanitized text safe for RichText
]]
function MarkdownParser.SanitizeRichText(text)
	if not text then return "" end

	-- Escape square brackets to prevent placeholder conflicts
	text = text:gsub("%[", "&#91;"):gsub("%]", "&#93;")

	return text
end

return MarkdownParser
