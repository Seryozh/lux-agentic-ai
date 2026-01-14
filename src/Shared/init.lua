--[[
    Shared/init.lua
    Exports: Constants, Utils, IndexManager, MarkdownParser
]]

-- Export modules from Shared folder
local Shared = {
	Constants = require(script.Parent.Constants),
	Utils = require(script.Parent.Utils),
	IndexManager = require(script.Parent.IndexManager),
	MarkdownParser = require(script.Parent.MarkdownParser),
}

return Shared
