--[[
    UI/init.lua
    Exports: Builder, ChatRenderer, InputApproval, UserFeedback, KeySetup, Components, Create
]]

local UI = {
	Builder = require(script.Parent.Builder),
	ChatRenderer = require(script.Parent.ChatRenderer),
	InputApproval = require(script.Parent.InputApproval),
	UserFeedback = require(script.Parent.UserFeedback),
	KeySetup = require(script.Parent.KeySetup),
	Components = require(script.Parent.Components),
	Create = require(script.Parent.Create),
}

return UI
