--[[
    Safety/init.lua
    Exports: CircuitBreaker, OutputValidator, ErrorAnalyzer, ErrorPredictor, ToolResilience
]]

-- Export modules from Safety folder
local Safety = {
	CircuitBreaker = require(script.CircuitBreaker),
	OutputValidator = require(script.OutputValidator),
	ErrorAnalyzer = require(script.ErrorAnalyzer),
	ErrorPredictor = require(script.ErrorPredictor),
	ToolResilience = require(script.ToolResilience),
}

return Safety
