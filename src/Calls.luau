--[[
    The calls, merged onto the runtime. On the client: a slot per call in
    flight, the reply that resumes its thread or settles its promise, the
    deadline every call fails by and the calls refused before they are
    sent. On the server: the handler a function runs on a thread of its
    own, and the reply or the refusal its result becomes
--]]

--!strict
local Calls = {} :: any

local Config = require("./Config/Runtime")
local Types = require("./Config/Types/Runtime")

type Message = Types.Message

-- A call in flight: when it fails, and what settles it, gone once it has been settled
type Pending = { deadline: number, settle: ((ok: boolean, ...any) -> ())? }

-- What the client keeps per function: its calls in flight by slot, the slots freed for reuse and the highest given
type Call = {
	name: string,
	timeout: number,
	promise: any?, -- The promise library, when the function yields one
	pending: { [number]: Pending },
	free: { number },
	last: number,
}

local SLOTS: number = Config.slots
local MESSAGE_BYTES: number = Config.messageBytes
local STATUS = Config.status

local PREFIX_BYTES: number = 2 -- The u16 a reason's length is carried in, as far as its bound reaches

-- What a call that fails before it is sent returns: the error tuple, or a promise rejected with the reason
local function failed(call: Call, reason: string): ...any
	if call.promise then
		return call.promise.new(function (_, reject: (any) -> ())
			reject(reason)
		end)
	end
	return false, reason
end

-- Settles a call in flight once, with the reply or the reason it failed
local function settle(pending: Pending, ok: boolean, ...: any)
	local resume = pending.settle
	if resume then
		pending.settle = nil
		resume(ok, ...)
	end
end

-- The state of every function this side calls, by the id its replies arrive with
function Calls:functions(messages: { [number]: Message })
	local calls: { [number]: Call } = {}

	for id: number, message: Message in messages do
		if message.kind == "reply" then
			calls[id] = {
				name = message.name,
				timeout = message.timeout :: number,
				promise = message.promise,
				pending = {},
				free = {},
				last = 0,
			}
		end
	end

	self._calls = calls
end

--[[
    Makes one call: takes a slot, writes the call through the function's
    writer with it and waits for the reply, on the calling thread or
    through a promise as the function asks. A call fails at once, taking
    no slot, when nothing is listening, which is edit mode, or when every
    slot is in flight
--]]

function Calls:invoke(id: number, write: (slot: number, ...any) -> (), ...: any): ...any
	local call: Call = self._calls[id]
	if self._inert then
		return failed(call, "edit mode")
	end

	local slot: number = table.remove(call.free) or call.last + 1
	if slot > SLOTS then
		return failed(call, "too many calls")
	end

	local pending: Pending = { deadline = os.clock() + call.timeout }
	local written: boolean, refused: any = pcall(write, slot, ...)

	-- A refused argument undid the call's bytes; its slot goes back too, and the refusal reaches the caller
	if not written then
		table.insert(call.free, slot)
		error(refused, 0)
	end

	call.last = math.max(call.last, slot)
	call.pending[slot] = pending

	if call.promise then
		return call.promise.new(function (resolve: (...any) -> (), reject: (any) -> ())
			pending.settle = function (ok: boolean, ...: any)
				if ok then
					resolve(...)
				else
					reject(...)
				end
			end
		end)
	end

	local thread: thread = coroutine.running()
	local spawn = self._spawn

	pending.settle = function (ok: boolean, ...: any)
		spawn(thread :: any, ok, ...)
	end

	return coroutine.yield()
end

--[[
    Settles the call a reply is for with its returns and frees its slot.
    Returns the cursors, so a reader's tail is this one call
--]]

function Calls:reply(id: number, slot: number, cursor: number, sideCursor: number, ...: any): (number, number)
	self:_release(id, slot, true, ...)
	return cursor, sideCursor
end

--[[
    The reply that refuses a call: the reason is read here, since it is
    the one string every function's refusal carries, and the call is
    settled with it. Returns the cursors past the reason
--]]

function Calls:refused(
	id: number,
	slot: number,
	packet: buffer,
	cursor: number,
	sideCursor: number,
	length: number
): (number, number)
	local name: string = self._calls[id].name
	if cursor + PREFIX_BYTES > length then
		error(`{name}: truncated`)
	end

	local count: number = buffer.readu16(packet, cursor)
	cursor += PREFIX_BYTES

	if count > MESSAGE_BYTES or cursor + count > length then
		error(`{name}: truncated`)
	end

	self:_release(id, slot, false, buffer.readstring(packet, cursor, count))

	return cursor + count, sideCursor
end

--[[
    Connects the one handler a function has, whose returns become the
    reply, and returns the closure that disconnects it. A second while
    one is connected is an error rather than a silent replacement
--]]

function Calls:handle(id: number, handler: (...any) -> ...any): () -> ()
	local handlers = self._handlers

	assert(handlers[id] == nil, `{self._messages[id].name}: a handler is already connected`)
	handlers[id] = handler

	-- Cleanup and disconnect from handler
	return function ()
		if handlers[id] == handler then
			handlers[id] = nil
		end
	end
end

--[[
    Runs a call from a player: the handler on a thread of its own, since
    most yield, with its returns as the reply; a call past the function's
    rate or with no handler is refused at once. Returns the cursors, so a
    reader's tail is this one call
--]]

function Calls:call(
	id: number,
	player: any,
	slot: number,
	cursor: number,
	sideCursor: number,
	...: any
): (number, number)
	local message: Message = self._messages[id]
	local rate: number? = message.rate
	local handler = self._handlers[id]

	if rate and not self:allow(player, id, message.name, rate) then
		self:_reply(id, player, slot, STATUS.limited, "rate limited")
	elseif handler then
		self._spawn(self._serve, self, id, player, slot, handler, ...)
	else
		self:_reply(id, player, slot, STATUS.unhandled, "no handler")
	end

	return cursor, sideCursor
end

-- Serves one call: the handler's returns become the reply; its error is reported, and its first line refuses the call
function Calls:_serve(id: number, player: any, slot: number, handler: (...any) -> ...any, ...: any)
	local results = table.pack(xpcall(handler, self._trace, player, ...))
	if results[1] then
		return self:_reply(id, player, slot, STATUS.ok, table.unpack(results, 2, results.n))
	end

	local message: string = tostring(results[2])

	self:fail(player, "handler", `{self._messages[id].name}: {message}`)
	self:_reply(id, player, slot, STATUS.failed, message:match("^[^\n]*"))
end

--[[
    Writes a reply into the caller's state: the returns after a status of
    ok, or after any other the reason, cut to what a refusal carries. A
    return the function's return type cannot carry is the handler's
    bug: the writer refuses it and undoes the reply, which then fails
    the call with the refusal. Nothing is sent to a caller who has left
--]]

function Calls:_reply(id: number, player: any, slot: number, status: number, ...: any)
	if not self:target(player) then
		return
	end

	local message: Message = self._messages[id]
	local reply = message.reply :: (slot: number, status: number, ...any) -> ()

	if status == STATUS.ok then
		local ok: boolean, refused: any = pcall(reply, slot, status, ...)
		if ok then
			return
		end

		local reason: string = tostring(refused) -- Names the function and the return itself, as every refusal does

		self:fail(player, "handler", reason)
		return self:_reply(id, player, slot, STATUS.failed, reason)
	end

	local reason: string = ...
	reason = reason:sub(1, MESSAGE_BYTES)
	reply(slot, status)

	local offset: number, out: buffer = self.reliable.allocate(PREFIX_BYTES + #reason)
	buffer.writeu16(out, offset, #reason)
	buffer.writestring(out, offset + PREFIX_BYTES, reason)
end

-- Settles a call in flight and frees its slot; a call that timed out kept its slot for this, and one never made is a decode failure
function Calls:_release(id: number, slot: number, ok: boolean, ...: any)
	local call: Call = self._calls[id]
	local pending: Pending? = call.pending[slot]

	if not pending then
		error(`{call.name}: no call in slot {slot}`)
	end

	call.pending[slot] = nil
	table.insert(call.free, slot)
	settle(pending, ok, ...)
end

--[[
    Fails every call past its deadline, at each flush. Its slot stays
    taken until the late reply arrives, so a later call can never be
    given another call's answer; the walk finishes before anything is
    settled, since a resumed caller may call again into the same table
--]]

function Calls:_sweep()
	local now: number = os.clock()

	for _, call: Call in self._calls do
		local expired: { Pending }? = nil

		for _, pending: Pending in call.pending do
			if pending.settle and now >= pending.deadline then
				expired = expired or {}
				table.insert(expired :: { Pending }, pending)
			end
		end

		if expired then
			for _, pending: Pending in expired do
				settle(pending, false, "timeout")
			end
		end
	end
end

return Calls
