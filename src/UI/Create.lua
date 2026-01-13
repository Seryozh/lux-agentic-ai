--[[
    UI/Create.lua
    Helper utilities for creating UI instances with less boilerplate
]]

local Create = {}

--[[
    Create an instance with properties
    @param className string - Instance class name
    @param props table - Properties to set
    @return Instance

    Usage:
        local frame = Create.new("Frame", {
            Name = "MyFrame",
            Size = UDim2.new(1, 0, 0, 100),
            BackgroundColor3 = Color3.new(1, 1, 1),
            Parent = container
        })
]]
function Create.new(className, props)
	local instance = Instance.new(className)

	if props then
		for key, value in pairs(props) do
			if key == "Children" then
				-- Handle children array specially
				for _, child in ipairs(value) do
					child.Parent = instance
				end
			else
				instance[key] = value
			end
		end
	end

	return instance
end

--[[
    Create multiple instances at once
    @param definitions table - Array of {className, props} pairs
    @return table - Array of created instances

    Usage:
        local frame, padding, layout = Create.batch({
            {"Frame", {Name = "Container"}},
            {"UIPadding", {PaddingTop = UDim.new(0, 10)}},
            {"UIListLayout", {Padding = UDim.new(0, 5)}}
        })
]]
function Create.batch(definitions)
	local instances = {}
	for i, def in ipairs(definitions) do
		instances[i] = Create.new(def[1], def[2])
	end
	return table.unpack(instances)
end

return Create
