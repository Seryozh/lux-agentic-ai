--[[
    Memory/init.lua
    Exports: WorkingMemory, DecisionMemory, ProjectContext
]]

-- Export modules from Memory folder
local Memory = {
	Working = require(script.WorkingMemory),
	Decision = require(script.DecisionMemory),
	Project = require(script.ProjectContext),
}

return Memory
