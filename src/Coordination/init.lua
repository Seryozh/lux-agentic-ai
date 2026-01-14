--[[
    Coordination/init.lua
    Exports: Session (SessionManager)
]]

-- Export modules from Coordination folder
local Coordination = {
	Session = require(script.Parent.SessionManager),
}

return Coordination
