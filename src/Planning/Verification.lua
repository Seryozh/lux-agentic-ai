--[[
    Verification.lua
    Auto-verification system for critical operations
    
    This module validates that operations actually succeeded:
    1. Script creation/editing - verify script exists and has expected content
    2. Instance creation - verify instance exists with correct properties
    3. UI hierarchy - verify parent-child relationships
    4. Basic Lua syntax validation (pattern-based, no execution)
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Utils = require(script.Parent.Parent.Shared.Utils)

local Verification = {}

-- ============================================================================
-- SYNTAX VALIDATION (Pattern-based)
-- ============================================================================

-- Common syntax patterns that indicate problems
local SYNTAX_ISSUES = {
	-- Unbalanced brackets/parentheses (basic check)
	{
		name = "unbalanced_brackets",
		check = function(source)
			local roundOpen = select(2, source:gsub("%(", ""))
			local roundClose = select(2, source:gsub("%)", ""))
			if roundOpen ~= roundClose then
				return false, string.format("Unbalanced parentheses: %d '(' vs %d ')'", roundOpen, roundClose)
			end

			local curlyOpen = select(2, source:gsub("{", ""))
			local curlyClose = select(2, source:gsub("}", ""))
			if curlyOpen ~= curlyClose then
				return false, string.format("Unbalanced braces: %d '{' vs %d '}'", curlyOpen, curlyClose)
			end

			return true
		end
	},

	-- Function/end balance (approximate)
	{
		name = "function_end_balance",
		check = function(source)
			-- Count block openers and closers
			-- This is approximate - doesn't handle strings/comments perfectly
			local openers = 0
			local closers = 0

			-- Count function, if, for, while, repeat as openers
			for _ in source:gmatch("%f[%w]function%f[%W]") do openers = openers + 1 end
			for _ in source:gmatch("%f[%w]if%f[%W]") do openers = openers + 1 end
			for _ in source:gmatch("%f[%w]for%f[%W]") do openers = openers + 1 end
			for _ in source:gmatch("%f[%w]while%f[%W]") do openers = openers + 1 end
			for _ in source:gmatch("%f[%w]repeat%f[%W]") do openers = openers + 1 end
			for _ in source:gmatch("%f[%w]do%f[%W]") do openers = openers + 1 end

			-- Count end, until as closers
			for _ in source:gmatch("%f[%w]end%f[%W]") do closers = closers + 1 end
			for _ in source:gmatch("%f[%w]until%f[%W]") do closers = closers + 1 end

			-- 'end' at very end of file
			if source:match("%f[%w]end%s*$") then
				-- Already counted
			end

			-- Subtract 'do' used in for loops (counted separately)
			-- This is very approximate

			if openers > closers + 2 then
				return false, string.format("Possibly missing 'end' statements (found %d openers, %d closers)", openers, closers)
			end

			if closers > openers + 2 then
				return false, string.format("Possibly extra 'end' statements (found %d openers, %d closers)", openers, closers)
			end

			return true
		end
	},

	-- String literal issues (unclosed strings)
	{
		name = "unclosed_string",
		check = function(source)
			-- Very basic: Check for odd number of unescaped quotes per line
			-- (This is very approximate and has many false positives/negatives)
			-- We'll just check for obvious patterns

			-- Check for [[ without ]]
			local longOpen = select(2, source:gsub("%[%[", ""))
			local longClose = select(2, source:gsub("%]%]", ""))
			if longOpen > longClose then
				return false, "Unclosed long string ([[ without ]])"
			end

			return true
		end
	},

	-- Common typos
	{
		name = "common_typos",
		check = function(source)
			local issues = {}

			-- 'funciton' instead of 'function'
			if source:match("%f[%w]funciton%f[%W]") then
				table.insert(issues, "'funciton' should be 'function'")
			end

			-- 'retrun' instead of 'return'
			if source:match("%f[%w]retrun%f[%W]") then
				table.insert(issues, "'retrun' should be 'return'")
			end

			-- 'lcoal' instead of 'local'
			if source:match("%f[%w]lcoal%f[%W]") then
				table.insert(issues, "'lcoal' should be 'local'")
			end

			-- 'elseif' written as 'else if' (common mistake)
			if source:match("else%s+if%f[%W]") then
				table.insert(issues, "'else if' should be 'elseif'")
			end

			if #issues > 0 then
				return false, "Possible typos: " .. table.concat(issues, ", ")
			end

			return true
		end
	},

	-- Missing 'then' after 'if'
	{
		name = "missing_then",
		check = function(source)
			-- Look for 'if ... \n' without 'then' on same line
			-- This is very approximate
			for line in source:gmatch("[^\n]+") do
				if line:match("^%s*if%s+.+") and not line:match("then") and not line:match("%-%-") then
					-- Check if it's a multi-line condition
					if not line:match("%($") and not line:match("and%s*$") and not line:match("or%s*$") then
						return false, "Possible missing 'then' after 'if' condition"
					end
				end
			end
			return true
		end
	}
}

--[[
    Perform basic syntax validation on Lua source
    @param source string - Lua source code
    @return table - { valid: boolean, issues: array of strings }
]]
function Verification.validateSyntax(source)
	if not Constants.VERIFICATION.syntaxCheckEnabled then
		return { valid = true, issues = {} }
	end

	local issues = {}

	for _, check in ipairs(SYNTAX_ISSUES) do
		local ok, message = check.check(source)
		if not ok then
			table.insert(issues, message)
		end
	end

	local result = {
		valid = #issues == 0,
		issues = issues
	}

	if Constants.DEBUG and #issues > 0 then
		print(string.format("[Verification] Syntax issues found: %s", table.concat(issues, "; ")))
	end

	return result
end

-- ============================================================================
-- SCRIPT VERIFICATION
-- ============================================================================

--[[
    Verify a script exists and optionally check its content
    @param path string - Script path
    @param expectedPatterns table|nil - Patterns that should exist in source
    @return table - Verification result
]]
function Verification.verifyScript(path, expectedPatterns)
	if not Constants.VERIFICATION.enabled then
		return { verified = true, skipped = true }
	end

	local result = {
		verified = false,
		path = path,
		exists = false,
		hasSource = false,
		syntaxValid = true,
		patternMatches = {},
		issues = {}
	}

	-- Check if script exists
	local script = Utils.getScriptByPath(path)
	if not script then
		table.insert(result.issues, "Script not found at path: " .. path)
		return result
	end

	if not script:IsA("LuaSourceContainer") then
		table.insert(result.issues, "Instance exists but is not a script: " .. script.ClassName)
		return result
	end

	result.exists = true

	-- Check if has source
	local source = script.Source
	if not source or source == "" then
		table.insert(result.issues, "Script exists but has no source code")
		return result
	end

	result.hasSource = true
	result.lineCount = Utils.countLines(source)

	-- Validate syntax
	local syntaxResult = Verification.validateSyntax(source)
	result.syntaxValid = syntaxResult.valid
	result.syntaxIssues = syntaxResult.issues

	if not syntaxResult.valid then
		for _, issue in ipairs(syntaxResult.issues) do
			table.insert(result.issues, "Syntax: " .. issue)
		end
	end

	-- Check expected patterns
	if expectedPatterns then
		for _, pattern in ipairs(expectedPatterns) do
			local found = source:find(pattern, 1, true) ~= nil
			result.patternMatches[pattern] = found
			if not found then
				table.insert(result.issues, "Expected pattern not found: " .. pattern:sub(1, 50))
			end
		end
	end

	-- Overall verification status
	result.verified = result.exists and result.hasSource and result.syntaxValid and #result.issues == 0

	if Constants.DEBUG then
		print(string.format("[Verification] Script %s: %s",
			path,
			result.verified and "? VERIFIED" or "? ISSUES FOUND"
			))
	end

	return result
end

-- ============================================================================
-- INSTANCE VERIFICATION
-- ============================================================================

--[[
    Verify an instance exists with expected properties
    @param path string - Instance path
    @param expectedClass string|nil - Expected ClassName
    @param expectedProps table|nil - Properties to verify { propName = expectedValue }
    @return table - Verification result
]]
function Verification.verifyInstance(path, expectedClass, expectedProps)
	if not Constants.VERIFICATION.enabled then
		return { verified = true, skipped = true }
	end

	local result = {
		verified = false,
		path = path,
		exists = false,
		classMatch = true,
		propertyMatches = {},
		issues = {}
	}

	-- Check if instance exists
	local instance = Utils.getScriptByPath(path)
	if not instance then
		table.insert(result.issues, "Instance not found at path: " .. path)
		return result
	end

	result.exists = true
	result.className = instance.ClassName

	-- Check class
	if expectedClass and instance.ClassName ~= expectedClass then
		result.classMatch = false
		table.insert(result.issues, string.format(
			"Class mismatch: expected %s, got %s",
			expectedClass, instance.ClassName
			))
	end

	-- Check properties
	if expectedProps then
		for propName, expectedValue in pairs(expectedProps) do
			local success, actualValue = pcall(function()
				return instance[propName]
			end)

			if not success then
				result.propertyMatches[propName] = false
				table.insert(result.issues, string.format(
					"Property '%s' could not be read",
					propName
					))
			else
				-- Compare (convert to string for comparison)
				local match = tostring(actualValue) == tostring(expectedValue)
				result.propertyMatches[propName] = match

				if not match then
					table.insert(result.issues, string.format(
						"Property '%s': expected %s, got %s",
						propName, tostring(expectedValue), tostring(actualValue)
						))
				end
			end
		end
	end

	-- Overall verification status
	result.verified = result.exists and result.classMatch and #result.issues == 0

	if Constants.DEBUG then
		print(string.format("[Verification] Instance %s: %s",
			path,
			result.verified and "? VERIFIED" or "? ISSUES FOUND"
			))
	end

	return result
end

-- ============================================================================
-- UI HIERARCHY VERIFICATION
-- ============================================================================

--[[
    Verify UI hierarchy structure
    @param rootPath string - Path to root UI element
    @param expectedChildren table - Array of expected child names
    @return table - Verification result
]]
function Verification.verifyUIHierarchy(rootPath, expectedChildren)
	if not Constants.VERIFICATION.enabled or not Constants.VERIFICATION.verifyUIHierarchy then
		return { verified = true, skipped = true }
	end

	local result = {
		verified = false,
		rootPath = rootPath,
		rootExists = false,
		foundChildren = {},
		missingChildren = {},
		issues = {}
	}

	-- Check root exists
	local root = Utils.getScriptByPath(rootPath)
	if not root then
		table.insert(result.issues, "Root UI element not found: " .. rootPath)
		return result
	end

	result.rootExists = true
	result.rootClass = root.ClassName

	-- Check expected children
	for _, childName in ipairs(expectedChildren or {}) do
		local child = root:FindFirstChild(childName)
		if child then
			table.insert(result.foundChildren, {
				name = childName,
				className = child.ClassName
			})
		else
			table.insert(result.missingChildren, childName)
			table.insert(result.issues, "Missing child: " .. childName)
		end
	end

	-- Overall verification status
	result.verified = result.rootExists and #result.missingChildren == 0

	if Constants.DEBUG then
		print(string.format("[Verification] UI Hierarchy %s: %s (found %d/%d children)",
			rootPath,
			result.verified and "? VERIFIED" or "? ISSUES FOUND",
			#result.foundChildren,
			#result.foundChildren + #result.missingChildren
			))
	end

	return result
end

-- ============================================================================
-- OPERATION-SPECIFIC VERIFICATION
-- ============================================================================

--[[
    Verify result of a create_script operation
    @param operationData table - Data from the create_script tool
    @return table - Verification result
]]
function Verification.verifyScriptCreation(operationData)
	if not Constants.VERIFICATION.verifyAfterCreate then
		return { verified = true, skipped = true }
	end

	-- Check script exists and has the expected source
	local result = Verification.verifyScript(operationData.path)

	-- Additional checks for creation
	if result.exists then
		local script = Utils.getScriptByPath(operationData.path)

		-- Verify script type
		if operationData.scriptType and script.ClassName ~= operationData.scriptType then
			result.verified = false
			table.insert(result.issues, string.format(
				"Script type mismatch: expected %s, got %s",
				operationData.scriptType, script.ClassName
				))
		end

		-- Verify source length matches (rough check)
		if operationData.source then
			local expectedLines = Utils.countLines(operationData.source)
			local actualLines = result.lineCount

			-- Allow small variance
			if math.abs(expectedLines - actualLines) > 2 then
				result.verified = false
				table.insert(result.issues, string.format(
					"Line count mismatch: expected ~%d, got %d",
					expectedLines, actualLines
					))
			end
		end
	end

	return result
end

--[[
    Verify result of a patch_script operation
    @param operationData table - Data from the patch_script tool
    @return table - Verification result
]]
function Verification.verifyScriptPatch(operationData)
	if not Constants.VERIFICATION.verifyAfterEdit then
		return { verified = true, skipped = true }
	end

	local result = Verification.verifyScript(operationData.path)

	-- Additional check: verify the replacement content exists in the script
	if result.exists and operationData.replace_content then
		local script = Utils.getScriptByPath(operationData.path)
		local source = script.Source

		-- Check if replacement content is present
		local replacementFound = source:find(operationData.replace_content, 1, true) ~= nil

		if not replacementFound then
			result.verified = false
			table.insert(result.issues, "Replacement content not found in script after patch")
		end

		-- Check if search content is gone (unless it was meant to stay)
		if operationData.search_content and operationData.search_content ~= operationData.replace_content then
			local searchStillPresent = source:find(operationData.search_content, 1, true) ~= nil
			if searchStillPresent then
				result.verified = false
				table.insert(result.issues, "Original search content still present after patch")
			end
		end
	end

	return result
end

--[[
    Verify result of a create_instance operation
    @param operationData table - Data from the create_instance tool
    @return table - Verification result
]]
function Verification.verifyInstanceCreation(operationData)
	if not Constants.VERIFICATION.verifyAfterCreate then
		return { verified = true, skipped = true }
	end

	local path = operationData.parent .. "." .. operationData.name

	local result = Verification.verifyInstance(
		path,
		operationData.className,
		operationData.properties
	)

	return result
end

-- ============================================================================
-- VERIFICATION REPORT FORMATTING
-- ============================================================================

--[[
    Format verification result for display or LLM
    @param result table - Verification result
    @param operationType string - Type of operation verified
    @return string - Formatted report
]]
function Verification.formatReport(result, operationType)
	local parts = {}

	if result.skipped then
		return "?? Verification skipped (disabled)"
	end

	if result.verified then
		table.insert(parts, string.format("? Verification PASSED: %s", operationType))

		if result.lineCount then
			table.insert(parts, string.format("  ?? %d lines", result.lineCount))
		end

		if result.className then
			table.insert(parts, string.format("  ??? Class: %s", result.className))
		end
	else
		table.insert(parts, string.format("? Verification FAILED: %s", operationType))

		for _, issue in ipairs(result.issues or {}) do
			table.insert(parts, string.format("  ?? %s", issue))
		end

		-- Suggestions
		table.insert(parts, "\n?? Suggestions:")
		if not result.exists then
			table.insert(parts, "  - Check if the path is correct")
			table.insert(parts, "  - Verify parent container exists")
		elseif result.syntaxIssues and #result.syntaxIssues > 0 then
			table.insert(parts, "  - Review the code for syntax errors")
			table.insert(parts, "  - Use get_script to read current state")
		end
	end

	return table.concat(parts, "\n")
end

--[[
    Create a verification summary for multiple operations
    @param results table - Array of { operationType, result } pairs
    @return table - Summary { total, passed, failed, issues }
]]
function Verification.summarize(results)
	local summary = {
		total = #results,
		passed = 0,
		failed = 0,
		issues = {}
	}

	for _, item in ipairs(results) do
		if item.result.skipped then
			-- Don't count skipped
			summary.total = summary.total - 1
		elseif item.result.verified then
			summary.passed = summary.passed + 1
		else
			summary.failed = summary.failed + 1
			for _, issue in ipairs(item.result.issues or {}) do
				table.insert(summary.issues, {
					operation = item.operationType,
					issue = issue
				})
			end
		end
	end

	return summary
end

return Verification
