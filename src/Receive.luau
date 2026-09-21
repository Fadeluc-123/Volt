--[[
    The receive side, merged onto the runtime: the loop over a packet's
    messages, delivery to listeners by call mode, the queue a message
    waits in until a listener exists or a poll drains it, and the
    iterator a polled event is drained through
--]]

--!strict
local Receive = {} :: any

local Types = require("./Config/Types/Runtime")

type Message = Types.Message
type Stats = Types.Stats

type Entry = { n: number, [number]: any } -- A queued message: the player, then its values

type Channel = {
	name: string,
	kind: string, -- sync, async or polling
	single: boolean, -- Whether one listener is the most the event allows
	depth: number, -- How many messages the queue holds before the oldest is dropped
	rate: number?, -- What the server allows a player a second, when the event is limited
	listeners: { (...any) -> () },
	queue: { Entry },
	head: number,
	tail: number,
	warned: boolean, -- An overflow is reported once per event
}

local NO_SLOTS: { any } = table.freeze({}) -- What a reader indexes when the packet carried no instances

-- Calls a listener with the player first on the server and with the values alone on the client
local function invoke(listener: (...any) -> (), player: any, ...: any)
	if player == nil then
		return listener(...)
	end
	return listener(player, ...)
end

-- The oldest queued message, or nil; an empty queue starts its indices over
local function pop(channel: Channel): Entry?
	local head: number = channel.head

	if head > channel.tail then
		channel.head, channel.tail = 1, 0
		return nil
	end

	local entry: Entry = channel.queue[head]
	channel.queue[head] = nil
	channel.head = head + 1

	return entry
end

--[[
    Reads every message of a packet in turn from where the checks before
    decode left off: the id, then the reader, which decodes the bytes and
    delivers the values in one call and returns the cursors past them.
    Runs under the packet's pcall, so an error anywhere in a message
    drops the rest of the packet
--]]

local function loop(self: any, player: any, packet: buffer, side: { any }, start: number)
	local length: number = buffer.len(packet)
	local idBytes: number = self._idBytes
	local readId = self._readId
	local messages: { [number]: Message } = self._messages
	local total: Stats = self._stats
	local state = self._players[player]
	local mine: Stats? = state and state.stats
	local cursor: number, sideCursor: number = start, 1

	while cursor < length do
		if cursor + idBytes > length then
			error("truncated message id")
		end

		local id: number = readId(packet, cursor)
		local message: Message? = messages[id]

		if not message then
			error(`unknown message {id}`)
		end

		total.messagesIn += 1

		if mine then
			mine.messagesIn += 1
		end

		cursor, sideCursor = message.read(player, packet, cursor + idBytes, side, sideCursor, length)
	end
end

-- The dispatch state of every incoming event, by id; a call is dispatched by its own concern
function Receive:channels(messages: { [number]: Message })
	local channels: { [number]: Channel } = {}

	for id: number, message: Message in messages do
		local mode: string? = message.mode

		if mode then
			channels[id] = {
				name = message.name,
				kind = mode == "Polling" and "polling" or mode:find("Async") and "async" or "sync",
				single = mode:sub(1, 6) == "Single",
				depth = message.queue :: number,
				rate = message.rate,
				listeners = {},
				queue = {},
				head = 1,
				tail = 0,
				warned = false,
			}
		end
	end

	self._channels = channels
end

--[[
    Handles one packet from a player, or from the server on the client:
    the checks before decode, then the loop. A message that fails to
    decode leaves the cursor nowhere, so the rest of the packet is
    dropped with it and reported once
--]]

function Receive:packet(player: any, packet: any, side: any)
	if typeof(packet) ~= "buffer" or (side ~= nil and typeof(side) ~= "table") then
		return self:fail(player, "packet", "not a packet")
	end

	local start: number? = self:admit(player, packet)
	if not start then
		return
	end

	local ok: boolean, message: any = pcall(loop, self, player, packet, side or NO_SLOTS, start)
	if not ok then
		self:fail(player, "decode", (tostring(message):gsub("^.-:%d+: ", "")))
	end
end

--[[
    Hands a decoded message to its listeners by the event's call mode,
    unless the player is past the event's rate, when it is dropped here,
    decoded, so the packet goes on: inline for a sync mode, on a new
    thread for an async mode, and into the queue for a polled event or
    one no listener has claimed yet. Returns the cursors, so a reader's
    tail is this one call
--]]

function Receive:deliver(id: number, player: any, cursor: number, sideCursor: number, ...: any): (number, number)
	local channel: Channel = self._channels[id]
	local rate: number? = channel.rate
	local listeners = channel.listeners

	if rate and not self:allow(player, id, channel.name, rate) then
		return cursor, sideCursor
	end

	if channel.kind == "polling" or #listeners == 0 then
		self:_push(channel, player, ...)
	else
		for _, listener in listeners do
			self:_run(channel, listener, player, ...)
		end
	end

	return cursor, sideCursor
end

--[[
    Connects a listener and returns the closure that disconnects it. A
    single mode holds one listener, so a second is an error rather than
    a silent replacement; the first listener takes what queued before
    it, in arrival order
--]]

function Receive:on(id: number, listener: (...any) -> ()): () -> ()
	local channel: Channel = self._channels[id]
	local listeners = table.clone(channel.listeners) -- A copy, so a delivery in flight keeps its list

	assert(not channel.single or #listeners == 0, `{channel.name}: a listener is already connected`)
	table.insert(listeners, listener)
	channel.listeners = listeners

	if #listeners == 1 then
		local entry: Entry? = pop(channel)
		while entry do
			self:_run(channel, listener, table.unpack(entry, 1, entry.n))
			entry = pop(channel)
		end
	end

	-- Cleanup and disconnect from listener
	return function ()
		local index: number? = table.find(channel.listeners, listener)
		if index then
			local kept = table.clone(channel.listeners)
			table.remove(kept, index)
			channel.listeners = kept
		end
	end
end

--[[
    An iterator over the messages queued for a polled event, each popped
    as it is reached: the index, the player on the server, then the
    values
--]]

function Receive:iter(id: number): () -> ...any
	local channel: Channel = self._channels[id]
	local index: number = 0

	return function (): ...any
		local entry: Entry? = pop(channel)
		if not entry then
			return nil
		end

		index += 1

		return index, table.unpack(entry, entry[1] == nil and 2 or 1, entry.n)
	end
end

-- Runs one listener the way the channel's mode says
function Receive:_run(channel: Channel, listener: (...any) -> (), player: any, ...: any)
	if channel.kind == "sync" then
		self:_call(channel, listener, player, ...)
	else
		self._spawn(invoke, listener, player, ...)
	end
end

-- The error a listener or a handler raised with the stack that raised it, taken before the stack unwinds
function Receive._trace(message: any): string
	return debug.traceback(tostring(message), 2)
end

-- Runs one sync listener inline; an error or a yield is the listener's failure and the packet goes on
function Receive:_call(channel: Channel, listener: (...any) -> (), player: any, ...: any)
	local frame: number = self.frame
	local ok: boolean, message: any = xpcall(invoke, self._trace, listener, player, ...)

	if not ok then
		self:fail(player, "listener", `{channel.name}: {message}`)
	elseif self.frame ~= frame then
		self:fail(player, "listener", `{channel.name}: a sync listener yielded`)
	end
end

-- Queues a message behind the others, dropping the oldest when the queue is full
function Receive:_push(channel: Channel, player: any, ...: any)
	if channel.tail - channel.head + 1 >= channel.depth then
		channel.queue[channel.head] = nil
		channel.head += 1

		if not channel.warned then
			channel.warned = true
			self:fail(player, "queue", `{channel.name}: queue full, oldest dropped`)
		end
	end

	channel.tail += 1
	channel.queue[channel.tail] = table.pack(player, ...)
end

return Receive
