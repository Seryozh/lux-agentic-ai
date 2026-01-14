--[[
    src/init.lua
    Main exports for the entire src folder

    Usage:
        local src = require(script.src)
        local Core = src.Core
        local Memory = src.Memory
        -- etc.
]]

return {
	Core = require(script.Parent.Core.init),
	Memory = require(script.Parent.Memory.init),
	Safety = require(script.Parent.Safety.init),
	Context = require(script.Parent.Context.init),
	Planning = require(script.Parent.Planning.init),
	Tools = require(script.Parent.Tools.init),
	Coordination = require(script.Parent.Coordination.init),
	Shared = require(script.Parent.Shared.init),
	UI = require(script.Parent.UI.init),

	-- Backwards compatibility: direct exports of commonly used modules
	Constants = require(script.Parent.Shared.Constants),
	Utils = require(script.Parent.Shared.Utils),
	OpenRouterClient = require(script.Parent.OpenRouterClient)
}
