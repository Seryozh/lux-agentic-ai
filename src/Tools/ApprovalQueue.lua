--[[
	ApprovalQueue.lua
	Manages pending operations that require user approval before execution

	Handles:
	- Queueing dangerous write operations
	- Managing operation lifecycle (pending -> approved/rejected)
	- TTL-based cleanup of stale operations
	- Operation limits to prevent memory leaks

	Creator Store Compliant - No dynamic code execution
]]

local Constants = require(script.Parent.Parent.Shared.Constants)

local ApprovalQueue = {}

--============================================================
-- PENDING OPERATIONS STATE
--============================================================

local pendingOperations = {}
local nextOperationId = 1
local OPERATION_TTL_SECONDS = 600  -- Operations expire after 10 minutes
local MAX_PENDING_OPERATIONS = 50  -- Maximum operations to keep in queue

--============================================================
-- QUEUE MANAGEMENT
--============================================================

--- Clean up old/stale operations from the queue
local function cleanupOperations()
	local now = tick()
	local removed = 0

	-- Remove expired and processed operations
	for i = #pendingOperations, 1, -1 do
		local op = pendingOperations[i]
		local age = now - op.timestamp

		-- Remove if: expired, or processed (approved/rejected) and older than 60s
		if age > OPERATION_TTL_SECONDS then
			table.remove(pendingOperations, i)
			removed = removed + 1
		elseif op.status ~= "pending" and age > 60 then
			table.remove(pendingOperations, i)
			removed = removed + 1
		end
	end

	-- If still over max, remove oldest processed operations
	while #pendingOperations > MAX_PENDING_OPERATIONS do
		-- Find oldest non-pending operation
		local oldestIdx = nil
		local oldestTime = math.huge
		for i, op in ipairs(pendingOperations) do
			if op.status ~= "pending" and op.timestamp < oldestTime then
				oldestTime = op.timestamp
				oldestIdx = i
			end
		end

		if oldestIdx then
			table.remove(pendingOperations, oldestIdx)
			removed = removed + 1
		else
			-- All are pending - remove oldest pending as last resort
			table.remove(pendingOperations, 1)
			removed = removed + 1
		end
	end

	if Constants.DEBUG and removed > 0 then
		print(string.format("[Lux ApprovalQueue] Cleaned up %d stale operations", removed))
	end
end

--- Queue an operation for user approval
--- @param operationType string
--- @param data table
--- @return number operationId
function ApprovalQueue.queue(operationType, data)
	-- Cleanup old operations before adding new one
	cleanupOperations()

	local operation = {
		id = nextOperationId,
		type = operationType,
		timestamp = tick(),
		status = "pending",  -- "pending" | "approved" | "rejected"
		data = data
	}

	nextOperationId = nextOperationId + 1
	table.insert(pendingOperations, operation)

	if Constants.DEBUG then
		print(string.format("[Lux ApprovalQueue] Queued operation #%d: %s (queue size: %d)", operation.id, operationType, #pendingOperations))
	end

	return operation.id
end

--- Get a specific pending operation by ID
--- @param operationId number
--- @return table|nil operation
function ApprovalQueue.get(operationId)
	for _, op in ipairs(pendingOperations) do
		if op.id == operationId then
			return op
		end
	end
	return nil
end

--- Get all pending operations
--- @return table - Array of all operations
function ApprovalQueue.getAll()
	return pendingOperations
end

--- Mark an operation as approved
--- @param operationId number
--- @return boolean success
function ApprovalQueue.approve(operationId)
	local op = ApprovalQueue.get(operationId)
	if op and op.status == "pending" then
		op.status = "approved"
		if Constants.DEBUG then
			print(string.format("[Lux ApprovalQueue] Approved operation #%d: %s", op.id, op.type))
		end
		return true
	end
	return false
end

--- Mark an operation as rejected
--- @param operationId number
--- @return boolean success
function ApprovalQueue.reject(operationId)
	local op = ApprovalQueue.get(operationId)
	if op then
		op.status = "rejected"
		if Constants.DEBUG then
			print(string.format("[Lux ApprovalQueue] Rejected operation #%d: %s", op.id, op.type))
		end
		return true
	end
	return false
end

--- Clear all pending operations
--- @return number count - Number of operations cleared
function ApprovalQueue.clear()
	local count = #pendingOperations
	pendingOperations = {}
	nextOperationId = 1
	if Constants.DEBUG then
		print(string.format("[Lux ApprovalQueue] Cleared %d pending operations", count))
	end
	return count
end

--- Force cleanup of stale operations
--- @return number removed - Number of operations removed
function ApprovalQueue.cleanup()
	local beforeCount = #pendingOperations
	cleanupOperations()
	return beforeCount - #pendingOperations
end

--- Get queue statistics
--- @return table stats
function ApprovalQueue.getStats()
	local pending = 0
	local approved = 0
	local rejected = 0

	for _, op in ipairs(pendingOperations) do
		if op.status == "pending" then
			pending = pending + 1
		elseif op.status == "approved" then
			approved = approved + 1
		elseif op.status == "rejected" then
			rejected = rejected + 1
		end
	end

	return {
		total = #pendingOperations,
		pending = pending,
		approved = approved,
		rejected = rejected,
		ttl = OPERATION_TTL_SECONDS,
		maxSize = MAX_PENDING_OPERATIONS
	}
end

return ApprovalQueue
