--[[
    Safety/init.lua
    Exports: CircuitBreaker, OutputValidator, ErrorAnalyzer, ErrorPredictor, ToolResilience
]]

-- Export modules from Safety folder
local Safety = {
	CircuitBreaker = require(script.Parent.CircuitBreaker),
	OutputValidator = require(script.Parent.OutputValidator),
	ErrorAnalyzer = require(script.Parent.ErrorAnalyzer),
	ErrorPredictor = require(script.Parent.ErrorPredictor),
	ToolResilience = require(script.Parent.ToolResilience),
}

return Safety
