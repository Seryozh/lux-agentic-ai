--[[
    ProjectContext.lua
    AI-generated, self-validating project memory

    Key concepts:
    - Context is OUTPUT (AI writes it), not INPUT (user writes it)
    - Each entry has an "anchor" - something verifiable in the codebase
    - On session start, anchors are validated
    - Stale entries are marked and can be refreshed
]]

local HttpService = game:GetService("HttpService")
local Constants = require(script.Parent.Parent.Shared.Constants)
local Utils = require(script.Parent.Parent.Shared.Utils)

local ProjectContext = {}

-- In-memory cache of parsed context
local contextCache = nil
local lastLoadTime = 0

--============================================================
-- STORAGE
--============================================================

local function getStorageLocation()
	return game:FindFirstChild(Constants.PROJECT_CONTEXT.storageLocation)
		or game:GetService(Constants.PROJECT_CONTEXT.storageLocation)
end

local function getContextValue()
	local location = getStorageLocation()
	return location:FindFirstChild(Constants.PROJECT_CONTEXT.storageName)
end

local function ensureContextValue()
	local location = getStorageLocation()
	local existing = location:FindFirstChild(Constants.PROJECT_CONTEXT.storageName)

	if existing then
		return existing
	end

	local contextValue = Instance.new("StringValue")
	contextValue.Name = Constants.PROJECT_CONTEXT.storageName
	contextValue.Value = HttpService:JSONEncode({
		version = 1,
		entries = {},
		metadata = {
			created = os.time(),
			lastModified = os.time(),
			gameId = game.GameId,
			placeName = game.Name
		}
	})
	contextValue.Parent = location

	return contextValue
end

--============================================================
-- LOADING & SAVING
--============================================================

function ProjectContext.load()
	local contextValue = getContextValue()

	if not contextValue then
		contextCache = { version = 1, entries = {}, metadata = {} }
		return contextCache
	end

	local success, parsed = pcall(function()
		return HttpService:JSONDecode(contextValue.Value)
	end)

	if not success or not parsed.entries then
		contextCache = { version = 1, entries = {}, metadata = {} }
		return contextCache
	end

	contextCache = parsed
	lastLoadTime = tick()
	return contextCache
end

function ProjectContext.save()
	if not contextCache then return false end

	contextCache.metadata = contextCache.metadata or {}
	contextCache.metadata.lastModified = os.time()

	local contextValue = ensureContextValue()

	local success, encoded = pcall(function()
		return HttpService:JSONEncode(contextCache)
	end)

	if not success then
		warn("[Lux] Failed to encode context: " .. tostring(encoded))
		return false
	end

	contextValue.Value = encoded
	return true
end

--============================================================
-- ANCHOR VALIDATION
--============================================================

local function validateAnchor(anchor)
	if not anchor or not anchor.type then
		return true  -- No anchor = always valid (manually added context)
	end

	if anchor.type == "script_exists" then
		local script = Utils.getScriptByPath(anchor.path)
		return script ~= nil and script:IsA("LuaSourceContainer")

	elseif anchor.type == "instance_exists" then
		local instance = Utils.getScriptByPath(anchor.path)  -- Works for any instance
		return instance ~= nil

	elseif anchor.type == "script_contains" then
		local script = Utils.getScriptByPath(anchor.path)
		if not script or not script:IsA("LuaSourceContainer") then
			return false
		end
		return script.Source:find(anchor.pattern, 1, true) ~= nil

	elseif anchor.type == "service_has_child" then
		local service = game:FindFirstChild(anchor.service)
			or pcall(function() return game:GetService(anchor.service) end) and game:GetService(anchor.service)
		if not service then return false end
		return service:FindFirstChild(anchor.childName) ~= nil

		-- NEW: Semantic anchor types

	elseif anchor.type == "content_hash" then
		-- Validate that a specific code region hasn't changed
		local script = Utils.getScriptByPath(anchor.path)
		if not script or not script:IsA("LuaSourceContainer") then
			return false
		end
		local source = script.Source
		local content
		if anchor.hashRegion then
			-- Extract specific line range
			local lines = {}
			local lineNum = 1
			for line in source:gmatch("[^\n]*") do
				if lineNum >= anchor.hashRegion.startLine and lineNum <= anchor.hashRegion.endLine then
					table.insert(lines, line)
				end
				lineNum = lineNum + 1
				if lineNum > anchor.hashRegion.endLine then break end
			end
			content = table.concat(lines, "\n")
		else
			content = source
		end
		-- Simple hash: sum of byte values (not cryptographic, just change detection)
		local hash = 0
		for i = 1, math.min(#content, 10000) do
			hash = (hash + content:byte(i) * i) % 2147483647
		end
		return tostring(hash) == anchor.hash

	elseif anchor.type == "function_signature" then
		-- Validate that a function still has expected signature
		local script = Utils.getScriptByPath(anchor.path)
		if not script or not script:IsA("LuaSourceContainer") then
			return false
		end
		local source = script.Source
		-- Look for function definition
		local funcName = anchor.functionName
		local pattern = "function%s+" .. funcName:gsub("([%.%[%]%(%)%+%-%*%?%^%$%%])", "%%%1") .. "%s*%(([^%)]*)"
		local params = source:match(pattern)
		if not params then
			-- Try local function
			pattern = "local%s+function%s+" .. funcName:gsub("([%.%[%]%(%)%+%-%*%?%^%$%%])", "%%%1") .. "%s*%(([^%)]*)"
			params = source:match(pattern)
		end
		if not params then return false end
		-- Check expected params
		if anchor.expectedParams then
			for _, expected in ipairs(anchor.expectedParams) do
				if not params:find(expected, 1, true) then
					return false
				end
			end
		end
		return true

	elseif anchor.type == "dependency_exists" then
		-- Validate that required dependencies are still present
		local script = Utils.getScriptByPath(anchor.path)
		if not script or not script:IsA("LuaSourceContainer") then
			return false
		end
		local source = script.Source
		for _, dep in ipairs(anchor.requires or {}) do
			-- Look for require statements containing the dependency
			if not source:find(dep, 1, true) then
				return false
			end
		end
		return true
	end

	return true  -- Unknown anchor type = assume valid
end

--[[
    Compute a simple hash for content change detection
    @param content string
    @return string
]]
function ProjectContext.computeHash(content)
	local hash = 0
	for i = 1, math.min(#content, 10000) do
		hash = (hash + content:byte(i) * i) % 2147483647
	end
	return tostring(hash)
end

--[[
    Validate all context entries against their anchors
    @return table - { valid: number, stale: number, staleEntries: table }
]]
function ProjectContext.validateAll()
	local context = ProjectContext.load()
	local results = { valid = 0, stale = 0, staleEntries = {} }

	local now = os.time()
	local staleThreshold = Constants.PROJECT_CONTEXT.staleThresholdDays * 86400

	for i, entry in ipairs(context.entries) do
		local isStale = false
		local reason = nil

		-- Check anchor validity
		if entry.anchor and not validateAnchor(entry.anchor) then
			isStale = true
			reason = "Anchor no longer valid: " .. (entry.anchor.path or entry.anchor.pattern or "unknown")
		end

		-- Check time-based staleness
		local lastVerified = entry.lastVerified or entry.created or 0
		if (now - lastVerified) > staleThreshold then
			isStale = true
			reason = reason or "Not verified in " .. Constants.PROJECT_CONTEXT.staleThresholdDays .. " days"
		end

		if isStale then
			entry.isStale = true
			entry.staleReason = reason
			results.stale = results.stale + 1
			table.insert(results.staleEntries, {
				index = i,
				content = entry.content,
				reason = reason
			})
		else
			entry.isStale = false
			entry.lastVerified = now
			results.valid = results.valid + 1
		end
	end

	ProjectContext.save()
	return results
end

--============================================================
-- CONTEXT OPERATIONS (called by AI tools)
--============================================================

--[[
    Add a new context entry
    @param entryType string - One of Constants.CONTEXT_TYPES
    @param content string - The context information
    @param anchor table|nil - Optional anchor for validation
    @return table - { success: boolean, message: string }
]]
function ProjectContext.addEntry(entryType, content, anchor)
	local context = ProjectContext.load()

	-- Validate type
	local validType = false
	for _, t in ipairs(Constants.CONTEXT_TYPES) do
		if t == entryType then validType = true break end
	end
	if not validType then
		return { success = false, error = "Invalid context type: " .. tostring(entryType) }
	end

	-- Truncate content if too long
	if #content > Constants.PROJECT_CONTEXT.maxContentLength then
		content = content:sub(1, Constants.PROJECT_CONTEXT.maxContentLength) .. "..."
	end

	-- Check for duplicates (similar content)
	for _, existing in ipairs(context.entries) do
		if existing.content == content then
			return { success = false, error = "Duplicate context entry" }
		end
	end

	-- Enforce max entries (remove oldest stale first, then oldest)
	while #context.entries >= Constants.PROJECT_CONTEXT.maxEntries do
		local removeIndex = nil

		-- Find oldest stale entry
		for i, entry in ipairs(context.entries) do
			if entry.isStale then
				removeIndex = i
				break
			end
		end

		-- Or remove oldest
		if not removeIndex then
			removeIndex = 1
		end

		table.remove(context.entries, removeIndex)
	end

	-- Add new entry
	local entry = {
		type = entryType,
		content = content,
		anchor = anchor,
		created = os.time(),
		lastVerified = os.time(),
		isStale = false
	}

	table.insert(context.entries, entry)
	ProjectContext.save()

	return { success = true, message = "Context added: " .. content:sub(1, 50) }
end

--[[
    Get all context entries, optionally filtered
    @param includeStale boolean - Include stale entries (default false)
    @return table - Array of entries
]]
function ProjectContext.getEntries(includeStale)
	local context = ProjectContext.load()

	if includeStale then
		return context.entries
	end

	local valid = {}
	for _, entry in ipairs(context.entries) do
		if not entry.isStale then
			table.insert(valid, entry)
		end
	end
	return valid
end

--[[
    Remove a context entry by index
    @param index number
    @return table - { success: boolean }
]]
function ProjectContext.removeEntry(index)
	local context = ProjectContext.load()

	if index < 1 or index > #context.entries then
		return { success = false, error = "Invalid index" }
	end

	table.remove(context.entries, index)
	ProjectContext.save()

	return { success = true }
end

--[[
    Clear all stale entries
    @return number - Count of removed entries
]]
function ProjectContext.clearStale()
	local context = ProjectContext.load()
	local removed = 0

	local i = 1
	while i <= #context.entries do
		if context.entries[i].isStale then
			table.remove(context.entries, i)
			removed = removed + 1
		else
			i = i + 1
		end
	end

	if removed > 0 then
		ProjectContext.save()
	end

	return removed
end

--[[
    Format context for inclusion in system prompt
    @return string
]]
function ProjectContext.formatForPrompt()
	local entries = ProjectContext.getEntries(false)  -- Valid only

	if #entries == 0 then
		return ""
	end

	local sections = {
		architecture = {},
		convention = {},
		warning = {},
		dependency = {}
	}

	for _, entry in ipairs(entries) do
		local section = sections[entry.type]
		if section then
			table.insert(section, "- " .. entry.content)
		end
	end

	local lines = { "## Project Context (AI-discovered, validated)\n" }

	if #sections.architecture > 0 then
		table.insert(lines, "### Architecture")
		for _, item in ipairs(sections.architecture) do
			table.insert(lines, item)
		end
		table.insert(lines, "")
	end

	if #sections.convention > 0 then
		table.insert(lines, "### Conventions")
		for _, item in ipairs(sections.convention) do
			table.insert(lines, item)
		end
		table.insert(lines, "")
	end

	if #sections.warning > 0 then
		table.insert(lines, "### Warnings")
		for _, item in ipairs(sections.warning) do
			table.insert(lines, item)
		end
		table.insert(lines, "")
	end

	if #sections.dependency > 0 then
		table.insert(lines, "### Dependencies")
		for _, item in ipairs(sections.dependency) do
			table.insert(lines, item)
		end
		table.insert(lines, "")
	end

	return table.concat(lines, "\n")
end

--[[
    Check if this appears to be a new/returning session
    @return table - { isNew: boolean, hasContext: boolean, staleCount: number }
]]
function ProjectContext.getSessionInfo()
	local context = ProjectContext.load()

	local hasContext = #context.entries > 0
	local staleCount = 0

	for _, entry in ipairs(context.entries) do
		if entry.isStale then
			staleCount = staleCount + 1
		end
	end

	return {
		isNew = not hasContext,
		hasContext = hasContext,
		totalEntries = #context.entries,
		staleCount = staleCount
	}
end

--[[
    Quick validation check for a single entry's anchor
    Does NOT update lastVerified - use validateAll for that
    @param entry table - Context entry
    @return boolean - Whether anchor is still valid
]]
function ProjectContext.isEntryAnchorValid(entry)
	if not entry.anchor or not entry.anchor.type then
		return true  -- No anchor = always valid
	end
	return validateAnchor(entry.anchor)
end

--[[
    Auto-cleanup entries with persistently invalid anchors
    Called periodically to remove entries that are no longer relevant
    @return number - Count of removed entries
]]
function ProjectContext.cleanupInvalidEntries()
	local context = ProjectContext.load()
	local removed = 0

	local validEntries = {}
	for _, entry in ipairs(context.entries) do
		local keepEntry = true

		-- Check if anchor is invalid
		if entry.anchor and entry.anchor.type then
			local isValid = validateAnchor(entry.anchor)

			if not isValid then
				-- Track consecutive failures
				entry.anchorFailCount = (entry.anchorFailCount or 0) + 1

				-- Remove if anchor has failed 3+ times consecutively
				if entry.anchorFailCount >= 3 then
					keepEntry = false
					removed = removed + 1

					if Constants.DEBUG then
						print(string.format("[ProjectContext] Removed invalid entry: %s", 
							entry.content:sub(1, 50)))
					end
				end
			else
				-- Reset failure count on successful validation
				entry.anchorFailCount = 0
			end
		end

		if keepEntry then
			table.insert(validEntries, entry)
		end
	end

	if removed > 0 then
		context.entries = validEntries
		ProjectContext.save()
	end

	return removed
end

--[[
    Revalidate entries before using them in prompt
    Lightweight check that filters out obviously invalid entries
    @return table - Array of valid entries only
]]
function ProjectContext.getValidatedEntries()
	local context = ProjectContext.load()
	local validEntries = {}

	for _, entry in ipairs(context.entries) do
		-- Skip already marked stale
		if entry.isStale then
			-- continue
		elseif not entry.anchor or not entry.anchor.type then
			-- No anchor = always include
			table.insert(validEntries, entry)
		elseif validateAnchor(entry.anchor) then
			-- Anchor still valid
			table.insert(validEntries, entry)
		else
			-- Anchor invalid but not yet 3x failed - still skip for this prompt
			-- Don't include in prompt but don't delete yet
		end
	end

	return validEntries
end

--============================================================
-- CASCADING INVALIDATION
--============================================================

--[[
    Invalidate entries when a dependency changes
    Uses visited set to prevent infinite loops from circular dependencies
    @param changedPath string - Path that was modified
    @param visited table|nil - Set of already-visited paths (for cycle detection)
]]
function ProjectContext.cascadeInvalidation(changedPath, visited)
	-- Prevent infinite loops from circular dependencies (A?B?A)
	visited = visited or {}
	if visited[changedPath] then
		if Constants.DEBUG then
			print("[ProjectContext] Circular dependency detected, stopping cascade at: " .. changedPath)
		end
		return
	end
	visited[changedPath] = true

	local context = ProjectContext.load()
	local invalidated = 0

	-- When a script changes, invalidate all entries that depend on it
	for _, entry in ipairs(context.entries) do
		if entry.dependencies then
			for _, dep in ipairs(entry.dependencies) do
				if dep == changedPath then
					entry.isStale = true
					entry.staleReason = "Dependency changed: " .. changedPath
					invalidated = invalidated + 1

					-- Recursively invalidate entries that depend on THIS entry's anchor
					if entry.anchor and entry.anchor.path then
						ProjectContext.cascadeInvalidation(entry.anchor.path, visited)
					end
					break
				end
			end
		end
	end

	if invalidated > 0 then
		ProjectContext.save()
		if Constants.DEBUG then
			print(string.format("[ProjectContext] Cascade invalidated %d entries from: %s",
				invalidated, changedPath))
		end
	end
end

--[[
    Detect cycles in the dependency graph
    @return table - Array of cycles found (each cycle is an array of paths)
]]
function ProjectContext.detectDependencyCycles()
	local context = ProjectContext.load()
	local cycles = {}

	local function dfs(path, currentPath, visited)
		if visited[path] then
			-- Found a cycle - extract it
			local cycleStart = nil
			for i, p in ipairs(currentPath) do
				if p == path then
					cycleStart = i
					break
				end
			end
			if cycleStart then
				local cycle = {}
				for i = cycleStart, #currentPath do
					table.insert(cycle, currentPath[i])
				end
				table.insert(cycle, path)
				table.insert(cycles, cycle)
			end
			return
		end

		visited[path] = true
		table.insert(currentPath, path)

		-- Find entries anchored at this path and follow their dependencies
		for _, entry in ipairs(context.entries) do
			if entry.anchor and entry.anchor.path == path then
				for _, dep in ipairs(entry.dependencies or {}) do
					dfs(dep, currentPath, visited)
				end
			end
		end

		table.remove(currentPath)
		visited[path] = nil
	end

	-- Check from each unique anchor path
	local checked = {}
	for _, entry in ipairs(context.entries) do
		if entry.anchor and entry.anchor.path and not checked[entry.anchor.path] then
			checked[entry.anchor.path] = true
			dfs(entry.anchor.path, {}, {})
		end
	end

	return cycles
end

--[[
    Add an entry with dependencies
    @param entryType string
    @param content string
    @param anchor table|nil
    @param dependencies table|nil - Array of paths this entry depends on
    @return table
]]
function ProjectContext.addEntryWithDependencies(entryType, content, anchor, dependencies)
	-- First add the entry normally
	local result = ProjectContext.addEntry(entryType, content, anchor)
	if not result.success then
		return result
	end

	-- Then add dependencies to the last entry
	if dependencies and #dependencies > 0 then
		local context = ProjectContext.load()
		local lastEntry = context.entries[#context.entries]
		if lastEntry then
			lastEntry.dependencies = dependencies
			ProjectContext.save()
		end
	end

	return result
end

--============================================================
-- DISCOVERY (called by AI on first session with existing codebase)
--============================================================

--[[
    Generate discovery hints based on what exists in the game
    Used by AI to know what to analyze
    @return table
]]
function ProjectContext.getDiscoveryHints()
	local hints = {
		hasScripts = false,
		locations = {},
		potentialFrameworks = {},
		scriptCount = 0
	}

	-- Check each scan location
	for _, locationName in ipairs(Constants.SCAN_LOCATIONS) do
		local location = game:FindFirstChild(locationName)
		if location then
			local scripts = {}
			for _, desc in ipairs(location:GetDescendants()) do
				if desc:IsA("LuaSourceContainer") then
					table.insert(scripts, Utils.getPath(desc))
					hints.scriptCount = hints.scriptCount + 1
				end
			end
			if #scripts > 0 then
				hints.hasScripts = true
				hints.locations[locationName] = scripts
			end
		end
	end

	-- Detect common frameworks by looking for known patterns
	local frameworkChecks = {
		{ name = "Knit", check = function()
			return game.ReplicatedStorage:FindFirstChild("Knit")
				or game.ReplicatedStorage:FindFirstChild("Packages")
		end },
		{ name = "ProfileService", check = function()
			return game.ServerScriptService:FindFirstChild("ProfileService")
		end },
		{ name = "DataStore2", check = function()
			return game.ServerScriptService:FindFirstChild("DataStore2")
		end },
	}

	for _, fw in ipairs(frameworkChecks) do
		local success, result = pcall(fw.check)
		if success and result then
			table.insert(hints.potentialFrameworks, fw.name)
		end
	end

	return hints
end

return ProjectContext
