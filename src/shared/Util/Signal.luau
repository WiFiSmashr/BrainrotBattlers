--!strict
-- Minimal signal for plain-Luau event wiring (no Instances).

export type Connection = { disconnect: () -> () }
export type Signal<T...> = {
	connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}
Signal.__index = Signal

-- Creates a new signal.
function Signal.new<T...>(): Signal<T...>
	return (setmetatable({ _handlers = {} }, Signal) :: any) :: Signal<T...>
end

-- Subscribes `fn`; returns a connection whose disconnect() unsubscribes it.
function Signal.connect(self: any, fn: (...any) -> ()): Connection
	local handlers = self._handlers
	table.insert(handlers, fn)
	return {
		disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

-- Calls every handler synchronously, in subscription order.
function Signal.fire(self: any, ...: any)
	local snapshot = table.clone(self._handlers)
	for _, fn in snapshot do
		fn(...)
	end
end

return Signal
