--[[
	Core/init.lua
	Exports all Core modules for the Lux AI system

	Core modules (v5.0 - Refactored Architecture):
	- ApiClient: API key management & HTTP communication
	- ConversationHistory: Conversation state management
	- MessageConverter: Message format conversion
	- AgenticLoop: Agentic loop & tool execution
]]

return {
	ApiClient = require(script.ApiClient),
	ConversationHistory = require(script.ConversationHistory),
	MessageConverter = require(script.MessageConverter),
	AgenticLoop = require(script.AgenticLoop)
}
