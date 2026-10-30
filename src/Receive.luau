--[[
    The receive side, merged onto the runtime: the loop over a packet's
    messages, delivery to listeners by call mode, an ordered event's stale
    messages dropped, the queue a message waits in until a listener or a
    poll takes it, the server time of the message being handled, and the
    profiler labels around what the transport calls
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
type Profiler = Types.Profiler
type Runtime = Types.Runtime
type Stats = Types.Stats

local NO_SLOTS: { any } = table.freeze({} :: { any }) -- What a reader indexes when the packet carried no instances
local POSITION: string = Config.position
local SEQUENCES: number = Config.sequences
local NEWER: number = SEQUENCES // 2 - 1 -- How many sequences after the last taken count as newer: 1 to 32767

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

	if id then
		self:_undecoded(player, id, message)
	else
		self:fail(player, "packet", (tostring(message):gsub(POSITION, "")))
	end
end

-- Reports what a reader raised, in a packet or read again, as a decode failure named for its message
function Receive._undecoded(self: Runtime, player: any, id: number, problem: any)
	local message: Message = self._messages[id]
	local profiler: Profiler? = self._profiler

	-- An id the reader asked for before it raised must not make the next awaited message wait
	table.clear(self._missing)

	-- A generated reader raises only inside its own label, never left to the engine; the dictionary's reader opens none
	if profiler and message.kind ~= "dictionary" then
		profiler.profileend()
	end

	self:fail(player, "decode", (tostring(problem):gsub(POSITION, "")), message.name)
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
    An ordered event's reader's tail: a message newer than the last taken
    from its sender, by at most half the sequence's span, is kept and
    delivered; a duplicate or an older one was decoded, spends the
    event's rate and is dropped before any hook, queue or listener, which
    is no failure. Returns the cursors, so a reader's tail is this one call
--]]

function Receive.ordered(
	self: Runtime,
	id: number,
	sequence: number,
	player: any,
	cursor: number,
	sideCursor: number,
	...: any
): (number, number)
	local kept: { [number]: number } = self._sequences

	if player ~= nil then
		local state: Joined? = self._players[player]

		-- A player who left part way through the packet, kicked by a listener before this, is heard no more
		if not state then
			return cursor, sideCursor
		end

		kept = state.sequences
	end

	local last: number? = kept[id]

	if last and (sequence - last - 1) % SEQUENCES >= NEWER then
		local limit: Limit? = self._limits[id]

		if limit and not self:allow(player, id, limit) then
			self:_limited(player, self._messages[id].name, limit)
		end

		return cursor, sideCursor
	end

	kept[id] = sequence

	return self:deliver(id, player, cursor, sideCursor, ...)
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

	-- Each queued message is handled under its own packet's stamp, and the newest packet's is back once they are done
	local entry: Entry? = #listeners == 1 and pop(channel) or nil

	if entry then
		while entry do
			self._stamp = entry.stamp
			run(self, channel, listener, table.unpack(entry, 1, entry.n))
			entry = pop(channel)
		end

		self._stamp = self._newest
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
    values, each handed out under its own packet's stamp, and the newest
    packet's once the queue is empty
--]]

function Receive.iter(self: Runtime, id: number): () -> ...any
	local channel: Channel = self._channels[id]
	local index: number = 0

	return function (): ...any
		local entry: Entry? = pop(channel)
		if not entry then
			self._stamp = self._newest
			return nil
		end

		index += 1
		self._stamp = entry.stamp

		return index, table.unpack(entry, entry[1] == nil and 2 or 1, entry.n)
	end
end

--[[
    The server time a stamped server's packet opened with: the packet
    holding the message being handled, or the queued one being handed
    out, and otherwise the newest; 0 before the first packet
--]]

function Receive.serverTime(self: Runtime): number
	return self._stamp
end

-- The error a listener or a handler raised with the stack that raised it, taken before the stack unwinds
function Receive._trace(message: any): string
	return debug.traceback(tostring(message), 2)
end

-- A callback the transport calls, run inside a profiler label opened before it and closed once it returns
function Receive._labelled(profiler: Profiler, label: string, callback: (...any) -> ()): (...any) -> ()
	return function (...: any)
		profiler.profilebegin(label)
		callback(...)
		profiler.profileend()
	end
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

	-- A queued message keeps the stamp of the packet it came in, which serverTime reads when it is handed out
	local entry: Entry = table.pack(player, ...) :: any
	entry.stamp = self._stamp

	channel.tail += 1
	channel.queue[channel.tail] = entry
end

return Receive
