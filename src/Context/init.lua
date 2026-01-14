--[[
    Context/init.lua
    Exports: Selector (ContextSelector), PromptBuilder (SystemPrompt), Compression (CompressionFallback)
]]

-- Export modules from Context folder
local Context = {
	Selector = require(script.ContextSelector),
	PromptBuilder = require(script.SystemPrompt),
	Compression = require(script.CompressionFallback),
}

return Context
