--[[
    The receive side, merged onto the runtime: the loop over a packet's
    messages, delivery to listeners by call mode, the queue a message
    waits in until a listener exists or a poll drains it, and the
    iterator a polled event is drained through
--]]

--!strict
--!native
local Receive = {}

local Config = require("./Config/Runtime")
local Types = require("./Config/Types/Runtime")

type Channel = Types.Channel
type Entry = Types.Entry
type Joined = Types.Joined
type Limit = Types.Limit
type Message = Types.Message
type Runtime = Types.Runtime
type Stats = Types.Stats

local NO_SLOTS: { any } = table.freeze({} :: { any }) -- What a reader indexes when the packet carried no instances
local POSITION: string = Config.position

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
    Runs one listener the way the channel's mode says: a sync listener
    inline under one xpcall, with the frame compared before and after so
    an error or a yield is the listener's failure and the packet goes
    on; an async listener on a new thread. Both deliver and the drain of
    a queue come through here, and nothing else sits before the listener
--]]

local function run(self: Runtime, channel: Channel, listener: (...any) -> (), player: any, ...: any)
	if channel.kind ~= "sync" then
		self._spawn(invoke, listener, player, ...)
		return
	end

	local frame: number = self.frame
	local ok: boolean, message: any

	if player == nil then
		ok, message = xpcall(listener, self._trace, ...)
	else
		ok, message = xpcall(listener, self._trace, player, ...)
	end

	if not ok then
		self:fail(player, "listener", tostring(message), channel.name)
	elseif self.frame ~= frame then
		self:fail(player, "listener", "a sync listener yielded", channel.name)
	end
end

--[[
    Reads every message of a packet in turn from where the checks before
    decode left off: the id, then the reader, which decodes the bytes and
    delivers the values in one call and returns the cursors past them.
    Runs under the packet's pcall, so an error anywhere in a message
    drops the rest of the packet, and the id being read says whose it is
--]]

local function loop(self: Runtime, player: any, packet: buffer, side: { any }, start: number)
	local length: number = buffer.len(packet)
	local idBytes: number = self._idBytes
	local readId = self._readId
	local messages: { [number]: Message } = self._messages
	local total: Stats = self._stats
	local state: Joined? = self._players[player]
	local mine: Stats? = state and state.stats
	local cursor: number, sideCursor: number = start, 1

	while cursor < length do
		if cursor + idBytes > length then
			self._reading = nil
			error("truncated message id")
		end

		local id: number = readId(packet, cursor)
		local message: Message? = messages[id]

		if not message then
			self._reading = nil
			error(`unknown message {id}`)
		end

		self._reading = id -- Every error a reader raises comes before its listeners run, so this names the message
		total.messagesIn += 1

		if mine then
			mine.messagesIn += 1
		end

		cursor, sideCursor = message.read(player, packet, cursor + idBytes, side, sideCursor, length)
	end
end

-- The dispatch state of every incoming event, by id; a call is dispatched by its own concern
function Receive.channels(self: Runtime, messages: { [number]: Message })
	local channels: { [number]: Channel } = self._channels

	for id: number, message: Message in messages do
		local mode: string? = message.mode

		if mode then
			channels[id] = {
				name = message.name,
				kind = mode == "Polling" and "polling" or mode:find("Async") and "async" or "sync",
				single = mode:sub(1, 6) == "Single",
				depth = message.queue :: number,
				listeners = {},
				queue = {},
				head = 1,
				tail = 0,
				warned = false,
			}
		end
	end
end

--[[
    Handles one packet from a player, or from the server on the client:
    the checks before decode, then the loop. A message that fails to
    decode leaves the cursor nowhere, so the rest of the packet is
    dropped with it and reported once, named for that message; an id cut
    short or naming no message is the packet's failure and names none
--]]

function Receive.packet(self: Runtime, player: any, packet: any, side: any)
	if typeof(packet) ~= "buffer" or (side ~= nil and typeof(side) ~= "table") then
		return self:fail(player, "packet", "not a packet")
	end

	local start: number? = self:admit(player, packet)
	if not start then
		return
	end

	local ok: boolean, message: any = pcall(loop, self, player, packet, side or NO_SLOTS, start)
	if ok then
		return
	end

	local id: number? = self._reading
	local detail: string = (tostring(message):gsub(POSITION, ""))

	if id then
		self:fail(player, "decode", detail, self._messages[id].name)
	else
		self:fail(player, "packet", detail)
	end
end

--[[
    Hands a decoded message to its listeners by the event's call mode,
    unless the player is past the event's rate or a hook vetoes it, when
    it is dropped here, decoded, so the packet goes on: inline for a sync
    mode, on a new thread for an async mode, and into the queue for a
    polled event or one no listener has claimed yet. Returns the cursors,
    so a reader's tail is this one call
--]]

function Receive.deliver(
	self: Runtime,
	id: number,
	player: any,
	cursor: number,
	sideCursor: number,
	...: any
): (number, number)
	local channel: Channel = self._channels[id]
	local limit: Limit? = self._limits[id]
	local listeners = channel.listeners

	if limit and not self:allow(player, id, limit) then
		self:_limited(player, channel.name, limit)
		return cursor, sideCursor
	end

	if self._hooked and not self:guard(id, player, ...) then
		return cursor, sideCursor
	end

	if channel.kind == "polling" or #listeners == 0 then
		self:_push(channel, player, ...)
	else
		for _, listener in listeners do
			run(self, channel, listener, player, ...)
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

function Receive.on(self: Runtime, id: number, listener: (...any) -> ()): () -> ()
	local channel: Channel = self._channels[id]
	local listeners = table.clone(channel.listeners) -- A copy, so a delivery in flight keeps its list

	assert(not channel.single or #listeners == 0, `{channel.name}: a listener is already connected`)
	table.insert(listeners, listener)
	channel.listeners = listeners

	if #listeners == 1 then
		local entry: Entry? = pop(channel)
		while entry do
			run(self, channel, listener, table.unpack(entry, 1, entry.n))
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

function Receive.iter(self: Runtime, id: number): () -> ...any
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

-- The error a listener or a handler raised with the stack that raised it, taken before the stack unwinds
function Receive._trace(message: any): string
	return debug.traceback(tostring(message), 2)
end

-- Queues a message behind the others, dropping the oldest when the queue is full
function Receive._push(self: Runtime, channel: Channel, player: any, ...: any)
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
