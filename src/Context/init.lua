--[[
    Context/init.lua
    Exports: Selector (ContextSelector), PromptBuilder (SystemPrompt), Compression (CompressionFallback)
]]

-- Export modules from Context folder
local Context = {
	Selector = require(script.Parent.ContextSelector),
	PromptBuilder = require(script.Parent.SystemPrompt),
	Compression = require(script.Parent.CompressionFallback),
}

return Context
