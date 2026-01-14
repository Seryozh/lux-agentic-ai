--[[
    Memory/init.lua
    Exports: WorkingMemory, DecisionMemory, ProjectContext
]]

-- Export modules from Memory folder
local Memory = {
	Working = require(script.Parent.WorkingMemory),
	Decision = require(script.Parent.DecisionMemory),
	Project = require(script.Parent.ProjectContext),
}

return Memory
