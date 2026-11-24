--!strict
--[[
	Signal
	Minimal in-process event used between server services (and between client
	controllers). Handlers are deferred (task.defer): they run after the
	emitting code finishes its current step, so an emitter is never re-entered
	half-way through a state change, and one erroring handler cannot break the
	emitter or other listeners.

	local changed = Signal.new()
	local connection = changed:Connect(function(a, b) ... end)
	changed:Fire(a, b)
	connection:Disconnect()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
}

type Listener = { handler: (...any) -> (), connection: Connection }

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	local self = setmetatable({}, Signal) :: any
	self._listeners = {} :: { Listener }
	return self :: Signal
end

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	local internal = self :: any
	local connection = { Connected = true } :: any
	local listener: Listener = { handler = handler, connection = connection }

	function connection.Disconnect(conn: Connection)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local listeners: { Listener } = internal._listeners
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end

	table.insert(internal._listeners, listener)
	return connection :: Connection
end

function Signal.Once(self: Signal, handler: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	-- Snapshot so handlers may disconnect themselves while firing.
	local listeners = table.clone((self :: any)._listeners) :: { Listener }
	for _, listener in listeners do
		if listener.connection.Connected then
			task.defer(listener.handler, ...)
		end
	end
end

function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	local internal = self :: any
	for _, listener: Listener in internal._listeners do
		listener.connection.Connected = false
	end
	table.clear(internal._listeners)
end

return Signal
