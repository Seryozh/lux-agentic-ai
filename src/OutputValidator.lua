--[[
    OutputValidator.lua
    LLM output validation before tool execution

    Validates tool calls before they execute to catch:
    1. Hallucinated paths (paths that don't exist)
    2. Incomplete/placeholder content
    3. Empty required fields
    4. Obvious syntax errors
    5. Suspicious patterns

    This prevents wasted iterations on obviously invalid operations.
]]

local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)

local OutputValidator = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local CONFIG = {
	enabled = true,
	checkPaths = true,
	checkContent = true,
	checkSyntax = true,
	suggestSimilar = true,
	maxSuggestions = 3,
}

-- ============================================================================
-- REQUIRED FIELDS PER TOOL
-- ============================================================================

local REQUIRED_FIELDS = {
	patch_script = { "path", "search_content", "replace_content" },
	create_script = { "path", "source" },
	edit_script = { "path", "newSource" },  -- Fixed: was "source", actual field is "newSource"
	create_instance = { "className", "parent", "name" },
	set_instance_properties = { "path", "properties" },
	delete_instance = { "path" },
	get_script = { "path" },
	get_instance = { "path" },
	list_children = { "path" },
	search_scripts = { "query" },  -- Fixed: was "pattern", actual field is "query"
}

-- ============================================================================
-- PLACEHOLDER PATTERNS
-- ============================================================================

local PLACEHOLDER_PATTERNS = {
	{ pattern = "TODO", message = "Contains TODO marker", severity = "warning" },
	{ pattern = "FIXME", message = "Contains FIXME marker", severity = "warning" },
	{ pattern = "XXX", message = "Contains XXX marker", severity = "warning" },
	{ pattern = "HACK", message = "Contains HACK marker", severity = "warning" },
	{ pattern = "%.%.%.", message = "Contains ellipsis (possibly truncated)", severity = "warning" },
	{ pattern = "%-%-%s*your%s*code%s*here", message = "Contains placeholder comment", severity = "critical" },
	{ pattern = "%-%-%s*add%s*code%s*here", message = "Contains placeholder comment", severity = "critical" },
	{ pattern = "%-%-%s*implement", message = "Contains unimplemented marker", severity = "warning" },
	{ pattern = "INSERT%s*%w*%s*HERE", message = "Contains INSERT HERE placeholder", severity = "critical" },
	{ pattern = "REPLACE%s*THIS", message = "Contains REPLACE THIS placeholder", severity = "critical" },
	{ pattern = "<%s*%w+%s*>", message = "Contains template placeholder like <name>", severity = "warning" },
}

-- ============================================================================
-- MAIN VALIDATION
-- ============================================================================

--[[
    Validate a tool call before execution
    @param toolCall table - { name: string, args: table }
    @return table - { valid: boolean, issues: array, suggestions: array }
]]
function OutputValidator.validateToolCall(toolCall)
	if not CONFIG.enabled then
		return { valid = true, issues = {}, suggestions = {} }
	end

	local issues = {}
	local suggestions = {}

	local toolName = toolCall.name
	local args = toolCall.args or {}

	-- 1. Check required fields
	OutputValidator._checkRequiredFields(toolName, args, issues)

	-- 2. Check paths
	if CONFIG.checkPaths then
		OutputValidator._checkPaths(toolName, args, issues, suggestions)
	end

	-- 3. Check content for placeholders
	if CONFIG.checkContent then
		OutputValidator._checkContent(toolName, args, issues)
	end

	-- 4. Check syntax
	if CONFIG.checkSyntax then
		OutputValidator._checkSyntax(toolName, args, issues)
	end

	-- 5. Tool-specific validation
	OutputValidator._checkToolSpecific(toolName, args, issues)

	-- Determine overall validity
	local hasCritical = false
	for _, issue in ipairs(issues) do
		if issue.severity == "critical" then
			hasCritical = true
			break
		end
	end

	if Constants.DEBUG and #issues > 0 then
		print(string.format("[OutputValidator] %s: %d issues (%s)",
			toolName,
			#issues,
			hasCritical and "INVALID" or "warnings only"
			))
	end

	return {
		valid = not hasCritical,
		issues = issues,
		suggestions = suggestions
	}
end

-- ============================================================================
-- VALIDATION HELPERS
-- ============================================================================

function OutputValidator._checkRequiredFields(toolName, args, issues)
	local required = REQUIRED_FIELDS[toolName]
	if not required then return end

	for _, field in ipairs(required) do
		local value = args[field]
		if value == nil then
			table.insert(issues, {
				severity = "critical",
				field = field,
				message = string.format("Required field '%s' is missing", field)
			})
		elseif type(value) == "string" and value:match("^%s*$") then
			table.insert(issues, {
				severity = "critical",
				field = field,
				message = string.format("Required field '%s' is empty or whitespace", field)
			})
		end
	end
end

function OutputValidator._checkPaths(toolName, args, issues, suggestions)
	local path = args.path

	if not path then return end

	-- Determine if this is a create operation
	local isCreateOp = toolName == "create_instance" or toolName == "create_script"

	if not isCreateOp then
		-- For read/modify operations, path must exist
		local exists = Utils.getScriptByPath(path) ~= nil

		if not exists then
			table.insert(issues, {
				severity = "critical",
				field = "path",
				message = "Path doesn't exist: " .. path
			})

			-- Try to find similar paths
			if CONFIG.suggestSimilar then
				local similar = OutputValidator.findSimilarPaths(path)
				for i, suggestion in ipairs(similar) do
					if i <= CONFIG.maxSuggestions then
						table.insert(suggestions, "Did you mean: " .. suggestion)
					end
				end
			end
		end
	else
		-- For create operations, validate parent exists
		local parentPath = args.parent or path:match("(.+)%.[^.]+$")
		if parentPath then
			local parentExists = Utils.getScriptByPath(parentPath) ~= nil
			if not parentExists then
				table.insert(issues, {
					severity = "critical",
					field = "parent",
					message = "Parent path doesn't exist: " .. parentPath
				})
			end
		end
	end
end

function OutputValidator._checkContent(toolName, args, issues)
	-- Check source/content fields (includes newSource for edit_script)
	local contentFields = { "source", "newSource", "content", "replace_content" }

	for _, field in ipairs(contentFields) do
		local content = args[field]
		if content and type(content) == "string" then
			-- Check for placeholders
			local upperContent = content:upper()
			for _, check in ipairs(PLACEHOLDER_PATTERNS) do
				if upperContent:find(check.pattern:upper()) or content:find(check.pattern) then
					table.insert(issues, {
						severity = check.severity,
						field = field,
						message = check.message .. " - code may be incomplete"
					})
				end
			end

			-- Check for suspiciously short content (only for source)
			if field == "source" and #content < 10 then
				table.insert(issues, {
					severity = "warning",
					field = field,
					message = string.format("Script source is suspiciously short (%d chars)", #content)
				})
			end

			-- Check for empty function bodies
			if content:match("function%s*[%w_]*%s*%([^)]*%)%s*end") then
				table.insert(issues, {
					severity = "warning",
					field = field,
					message = "Contains empty function body"
				})
			end
		end
	end
end

function OutputValidator._checkSyntax(toolName, args, issues)
	-- Only check for script operations
	if toolName ~= "create_script" and toolName ~= "edit_script" and toolName ~= "patch_script" then
		return
	end

	local content = args.source or args.newSource or args.replace_content
	if not content or type(content) ~= "string" then return end

	-- Quick syntax sanity checks (not a full parser)

	-- Count brackets
	local openParens = select(2, content:gsub("%(", ""))
	local closeParens = select(2, content:gsub("%)", ""))
	if openParens ~= closeParens then
		table.insert(issues, {
			severity = "critical",
			field = "content",
			message = string.format("Unbalanced parentheses: %d open, %d close", openParens, closeParens)
		})
	end

	local openBrackets = select(2, content:gsub("%[", ""))
	local closeBrackets = select(2, content:gsub("%]", ""))
	-- Allow some slack for string patterns like [^%s]
	if math.abs(openBrackets - closeBrackets) > 2 then
		table.insert(issues, {
			severity = "warning",
			field = "content",
			message = string.format("Possibly unbalanced brackets: %d open, %d close", openBrackets, closeBrackets)
		})
	end

	local openBraces = select(2, content:gsub("{", ""))
	local closeBraces = select(2, content:gsub("}", ""))
	if openBraces ~= closeBraces then
		table.insert(issues, {
			severity = "critical",
			field = "content",
			message = string.format("Unbalanced braces: %d open, %d close", openBraces, closeBraces)
		})
	end

	-- Check for common typos
	local typos = {
		{ pattern = "funciton", correct = "function" },
		{ pattern = "functoin", correct = "function" },
		{ pattern = "funtion", correct = "function" },
		{ pattern = "retrun", correct = "return" },
		{ pattern = "reutrn", correct = "return" },
		{ pattern = "lcoal", correct = "local" },
		{ pattern = "locla", correct = "local" },
		{ pattern = "thn", correct = "then" },
		{ pattern = "esle", correct = "else" },
		{ pattern = "elseif", correct = "elseif" }, -- This one is correct, skip
	}

	for _, typo in ipairs(typos) do
		if content:find(typo.pattern) and typo.pattern ~= "elseif" then
			table.insert(issues, {
				severity = "warning",
				field = "content",
				message = string.format("Possible typo: '%s' (did you mean '%s'?)", typo.pattern, typo.correct)
			})
		end
	end
end

function OutputValidator._checkToolSpecific(toolName, args, issues)
	if toolName == "patch_script" then
		-- search_content and replace_content shouldn't be identical
		if args.search_content and args.replace_content then
			if args.search_content == args.replace_content then
				table.insert(issues, {
					severity = "warning",
					field = "replace_content",
					message = "search_content and replace_content are identical - no change will occur"
				})
			end
		end

	elseif toolName == "create_instance" then
		-- Validate className looks reasonable
		local className = args.className
		if className then
			-- Should start with capital letter (Roblox convention)
			if not className:match("^%u") then
				table.insert(issues, {
					severity = "warning",
					field = "className",
					message = "ClassName should start with capital letter: " .. className
				})
			end
		end

	elseif toolName == "set_instance_properties" then
		-- Properties should be a table
		if args.properties and type(args.properties) ~= "table" then
			table.insert(issues, {
				severity = "critical",
				field = "properties",
				message = "properties must be a table, got " .. type(args.properties)
			})
		end
	end
end

-- ============================================================================
-- PATH SIMILARITY
-- ============================================================================

--[[
    Find paths similar to a potentially hallucinated one
    @param targetPath string - The path that doesn't exist
    @return table - Array of similar existing paths
]]
function OutputValidator.findSimilarPaths(targetPath)
	local similar = {}

	-- Extract parts of the target path
	local targetParts = {}
	for part in targetPath:gmatch("[^%.]+") do
		table.insert(targetParts, part:lower())
	end

	if #targetParts == 0 then return similar end

	local lastPart = targetParts[#targetParts]

	-- Get all known scripts
	local IndexManager = require(script.Parent.IndexManager)
	local scanResult = IndexManager.scanScripts()

	-- Score each script by similarity
	local scored = {}
	for _, scriptData in ipairs(scanResult.scripts) do
		local pathLower = scriptData.path:lower()
		local score = 0

		-- Check if last part matches (strongest signal)
		if pathLower:find(lastPart, 1, true) then
			score = score + 50
		end

		-- Check if name matches
		if scriptData.name:lower():find(lastPart, 1, true) then
			score = score + 30
		end

		-- Check for any matching parts
		for _, part in ipairs(targetParts) do
			if pathLower:find(part, 1, true) then
				score = score + 10
			end
		end

		if score > 0 then
			table.insert(scored, { path = scriptData.path, score = score })
		end
	end

	-- Sort by score descending
	table.sort(scored, function(a, b) return a.score > b.score end)

	-- Return top matches
	for i = 1, math.min(CONFIG.maxSuggestions, #scored) do
		table.insert(similar, scored[i].path)
	end

	return similar
end

-- ============================================================================
-- FORMATTING
-- ============================================================================

--[[
    Format validation issues for LLM feedback
    @param validation table - Result from validateToolCall
    @return string|nil - Formatted message or nil if valid
]]
function OutputValidator.formatForLLM(validation)
	if validation.valid and #validation.issues == 0 then
		return nil
	end

	local parts = { "?? TOOL CALL VALIDATION ISSUES:" }

	-- Group by severity
	local critical = {}
	local warnings = {}

	for _, issue in ipairs(validation.issues) do
		if issue.severity == "critical" then
			table.insert(critical, issue)
		else
			table.insert(warnings, issue)
		end
	end

	-- Critical issues first
	if #critical > 0 then
		table.insert(parts, "\n?? CRITICAL (must fix):")
		for _, issue in ipairs(critical) do
			table.insert(parts, string.format("  • [%s] %s", issue.field, issue.message))
		end
	end

	-- Then warnings
	if #warnings > 0 then
		table.insert(parts, "\n?? WARNINGS:")
		for _, issue in ipairs(warnings) do
			table.insert(parts, string.format("  • [%s] %s", issue.field, issue.message))
		end
	end

	-- Suggestions
	if #validation.suggestions > 0 then
		table.insert(parts, "\n?? Suggestions:")
		for _, suggestion in ipairs(validation.suggestions) do
			table.insert(parts, "  ? " .. suggestion)
		end
	end

	return table.concat(parts, "\n")
end

--[[
    Quick check if validation passed
    @param toolCall table
    @return boolean
]]
function OutputValidator.isValid(toolCall)
	local result = OutputValidator.validateToolCall(toolCall)
	return result.valid
end

return OutputValidator
