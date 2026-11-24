--!strict
--[[
	Janitor
	Collects cleanup work (connections, instances, threads, callbacks) so a
	feature can be torn down in one call. Used for per-round and per-screen
	lifetimes.

	local janitor = Janitor.new()
	janitor:Add(part)                    -- Instance -> :Destroy()
	janitor:Add(connection)              -- RBXScriptConnection / Signal connection
	janitor:Add(function() ... end)      -- arbitrary callback
	janitor:Add(task.delay(5, fn))       -- thread -> task.cancel
	janitor:Cleanup()
]]

export type Janitor = {
	Add: <T>(self: Janitor, item: T) -> T,
	Cleanup: (self: Janitor) -> (),
	Destroy: (self: Janitor) -> (),
}

local Janitor = {}
Janitor.__index = Janitor

function Janitor.new(): Janitor
	local self = setmetatable({}, Janitor) :: any
	self._items = {}
	return self :: Janitor
end

function Janitor.Add<T>(self: Janitor, item: T): T
	table.insert((self :: any)._items, item)
	return item
end

local function cleanItem(item: any)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Cleanup) == "function" then
			item:Cleanup()
		end
	end
end

function Janitor.Cleanup(self: Janitor)
	local internal = self :: any
	local items = internal._items
	internal._items = {}
	-- Clean in reverse order of acquisition.
	for index = #items, 1, -1 do
		local ok, err = pcall(cleanItem :: any, items[index])
		if not ok then
			warn("[Janitor] cleanup error:", err)
		end
	end
end

function Janitor.Destroy(self: Janitor)
	self:Cleanup()
end

return Janitor
