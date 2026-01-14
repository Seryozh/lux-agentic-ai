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
	Core = require(script.Core),
	Memory = require(script.Memory),
	Safety = require(script.Safety),
	Context = require(script.Context),
	Planning = require(script.Planning),
	Tools = require(script.Tools),
	Coordination = require(script.Coordination),
	Shared = require(script.Shared),
	UI = require(script.UI),

	-- Backwards compatibility: direct exports of commonly used modules
	Constants = require(script.Shared.Constants),
	Utils = require(script.Shared.Utils),
	OpenRouterClient = require(script.OpenRouterClient)
}
