--[[
	ProjectTools.lua
	Project context and discovery tool implementations

	Handles:
	- Project context management (update, get, validate)
	- Project discovery and structure analysis
	- Context lifecycle and staleness tracking

	These tools help the AI maintain understanding of the project architecture.

	Creator Store Compliant - No dynamic code execution
]]

local Constants = require(script.Parent.Parent.Shared.Constants)
local Utils = require(script.Parent.Parent.Shared.Utils)
local ProjectContext = require(script.Parent.Parent.Memory.ProjectContext)

local ProjectTools = {}

--============================================================
-- PROJECT CONTEXT TOOLS
--============================================================

--- Update project context with new information
--- @param args table {contextType: string, content: string, anchorPath: string (optional)}
--- @return table
function ProjectTools.update_project_context(args)
	if Constants.DEBUG then
		print(string.format("[Lux ProjectTools] update_project_context(%s): %s",
			args.contextType, args.content:sub(1, 50)))
	end

	-- Build anchor if path provided
	local anchor = nil
	if args.anchorPath and args.anchorPath ~= "" then
		-- Determine anchor type based on what exists
		local instance = Utils.getScriptByPath(args.anchorPath)
		if instance then
			if instance:IsA("LuaSourceContainer") then
				anchor = { type = "script_exists", path = args.anchorPath }
			else
				anchor = { type = "instance_exists", path = args.anchorPath }
			end
		end
	end

	local result = ProjectContext.addEntry(args.contextType, args.content, anchor)
	return result
end

--- Get all project context entries
--- @param args table {includeStale: boolean (optional)}
--- @return table
function ProjectTools.get_project_context(args)
	if Constants.DEBUG then
		print("[Lux ProjectTools] get_project_context()")
	end

	local entries = ProjectContext.getEntries(args.includeStale or false)
	local sessionInfo = ProjectContext.getSessionInfo()

	if #entries == 0 then
		return {
			hasContext = false,
			message = "No project context exists yet. Use update_project_context to add discoveries.",
			sessionInfo = sessionInfo
		}
	end

	return {
		hasContext = true,
		entries = entries,
		sessionInfo = sessionInfo,
		formatted = ProjectContext.formatForPrompt()
	}
end

--- Discover project structure and provide hints about the codebase
--- @param args table (empty)
--- @return table
function ProjectTools.discover_project(args)
	if Constants.DEBUG then
		print("[Lux ProjectTools] discover_project()")
	end

	local hints = ProjectContext.getDiscoveryHints()
	local sessionInfo = ProjectContext.getSessionInfo()

	return {
		scriptCount = hints.scriptCount,
		hasExistingScripts = hints.hasScripts,
		locations = hints.locations,
		potentialFrameworks = hints.potentialFrameworks,
		existingContext = sessionInfo.hasContext,
		staleContextCount = sessionInfo.staleCount,
		suggestion = hints.hasScripts and not sessionInfo.hasContext
			and "This game has scripts but no context. Consider reading key scripts and documenting architecture."
			or nil
	}
end

--- Validate all project context entries for staleness
--- @param args table (empty)
--- @return table
function ProjectTools.validate_context(args)
	if Constants.DEBUG then
		print("[Lux ProjectTools] validate_context()")
	end

	local results = ProjectContext.validateAll()

	local response = {
		validEntries = results.valid,
		staleEntries = results.stale,
		message = results.stale > 0
			and string.format("%d entries are stale and should be reviewed or removed", results.stale)
			or "All context entries are valid"
	}

	if results.stale > 0 then
		response.staleDetails = results.staleEntries
	end

	return response
end

--============================================================
-- TOOL DISPATCHER
--============================================================

--- Execute a project tool by name
--- @param toolName string
--- @param args table
--- @return table result
function ProjectTools.execute(toolName, args)
	if toolName == "update_project_context" then
		return ProjectTools.update_project_context(args)
	elseif toolName == "get_project_context" then
		return ProjectTools.get_project_context(args)
	elseif toolName == "discover_project" then
		return ProjectTools.discover_project(args)
	elseif toolName == "validate_context" then
		return ProjectTools.validate_context(args)
	else
		return {
			error = "Unknown project tool: " .. toolName
		}
	end
end

return ProjectTools
