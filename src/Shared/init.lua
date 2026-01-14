--[[
    Shared/init.lua
    Exports: Constants, Utils, IndexManager, MarkdownParser
]]

-- Export modules from Shared folder
local Shared = {
	Constants = require(script.Constants),
	Utils = require(script.Utils),
	IndexManager = require(script.IndexManager),
	MarkdownParser = require(script.MarkdownParser),
}

return Shared
