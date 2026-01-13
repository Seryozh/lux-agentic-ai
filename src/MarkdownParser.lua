--[[
    MarkdownParser.lua
    Simplified markdown to Roblox RichText converter
    
    Supports:
    - **bold** ? <b>bold</b>
    - `code` ? <font face="Code">code</font>
    - - Bullet lists ? • item
]]

local MarkdownParser = {}

--[[
    Parse markdown text into Roblox RichText
    @param text string - Markdown text
    @return string - RichText formatted string
]]
function MarkdownParser.parse(text)
	if not text then return "" end

	-- 1. Escape any HTML-like brackets that might break RichText
	text = text:gsub("<", "&lt;"):gsub(">", "&gt;")

	-- 2. Code blocks (``` ... ```) - convert to monospace, preserve newlines
	text = text:gsub("```%w*\n?(.-)\n?```", '<font face="Code" color="rgb(180,180,200)">%1</font>')

	-- 3. Inline code (`code`) - convert to monospace
	text = text:gsub("`([^`\n]+)`", '<font face="Code" color="rgb(180,180,200)">%1</font>')

	-- 4. Bold (**text**)
	text = text:gsub("%*%*([^%*]+)%*%*", "<b>%1</b>")

	-- 5. Process line by line for bullets and headers
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

return MarkdownParser
