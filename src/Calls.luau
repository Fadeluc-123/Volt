--[[
    The calling side, merged onto the runtime: a slot per call in flight,
    the client's per function and the server's per function and player,
    the reply that resumes its thread or settles its promise, the deadline
    every call fails by and the calls refused before they are sent
--]]

--!strict
local Calls = {}

local Config = require("./Config/Runtime")
local Types = require("./Config/Types/Runtime")

type Call = Types.Call
type Joined = Types.Joined
type Message = Types.Message
type Pending = Types.Pending
type Runtime = Types.Runtime
type Slots = Types.Slots

local SLOTS: number = Config.slots
local PLAYER_SLOTS: number = Config.playerSlots
local MESSAGE_BYTES: number = Config.messageBytes
local PREFIX_BYTES: number = Config.prefixBytes
local STATUS = Config.status

-- What a call that fails before it is sent returns: the error tuple, or a promise rejected with the reason
local function failed(call: Call, reason: string): ...any
	if call.promise then
		return call.promise.new(function (_, reject: (any) -> ())
			reject(reason)
		end)
	end
	return false, reason
end

-- A slot table with no call in flight
local function empty(): Slots
	return { pending = {}, free = {}, last = 0 }
end

-- Settles a call in flight once, with the reply or the reason it failed
local function settle(pending: Pending, ok: boolean, ...: any)
	local resume = pending.settle
	if resume then
		pending.settle = nil
		resume(ok, ...)
	end
end

-- Adds every call in a slot table that is past its deadline and not yet settled to the list, made at the first
local function expired(slots: Slots, now: number, list: { Pending }?): { Pending }?
	for _, pending: Pending in slots.pending do
		if pending.settle and now >= pending.deadline then
			list = list or {}
			table.insert(list :: { Pending }, pending)
		end
	end
	return list
end

--[[
    Sends one call from a slot table: takes a slot below the ceiling,
    writes the call with it and waits for the reply, on the calling
    thread or through a promise as the function asks. A writer that
    raised, or a message the cap dropped, gives its slot straight back
--]]

local function place(
	self: Runtime,
	call: Call,
	slots: Slots,
	ceiling: number,
	write: (slot: number, ...any) -> (),
	...: any
): ...any
	local slot: number = table.remove(slots.free) or slots.last + 1
	if slot > ceiling then
		return failed(call, "too many calls")
	end

	local pending: Pending = { deadline = os.clock() + call.timeout }
	local written: boolean, refused: any = pcall(write, slot, ...)

	-- Whatever the writer raised leaves none of the call's bytes behind; its slot goes back too, and the error reaches the caller
	if not written then
		table.insert(slots.free, slot)
		error(self.reliable:undo(call.name, refused), 0)
	end

	-- A message past the cap is dropped and reported here; none of its bytes left, so no reply can name its slot
	if self.reliable:drop() then
		table.insert(slots.free, slot)
		return failed(call, "dropped")
	end

	slots.last = math.max(slots.last, slot)
	slots.pending[slot] = pending

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

-- The state of every function this side calls, by the id its replies arrive with; the client's slots are its own
function Calls.functions(self: Runtime, messages: { [number]: Message })
	local calls: { [number]: Call } = self._calls
	local client: boolean = not self._server

	for id: number, message: Message in messages do
		if message.kind == "reply" then
			calls[id] = {
				name = message.name,
				timeout = message.timeout :: number,
				promise = message.promise,
				slots = client and empty() or nil,
			}
		end
	end
end

--[[
    Makes one call. On the server the first value is the player it goes
    to and the rest are the call's, and outside edit mode a nil player
    raises, as a fire at one does. A call fails at once, taking no slot,
    when nothing is listening, which is edit mode, when its player has
    left or their handshake failed, when every slot is in flight, or when
    its message took the frame past the cap
--]]

function Calls.invoke(self: Runtime, id: number, write: (slot: number, ...any) -> (), ...: any): ...any
	local call: Call = self._calls[id]
	if self._inert then
		return failed(call, "edit mode")
	end

	if not self._server then
		return place(self, call, call.slots :: Slots, SLOTS, write, ...)
	end

	local player: any = ...
	if not self:target(player) then
		return failed(call, "departed")
	end

	return place(self, call, self:_slots(id, player, true) :: Slots, PLAYER_SLOTS, write, select(2, ...))
end

--[[
    Settles the call a reply is for with its returns and frees its slot.
    Returns the cursors, so a reader's tail is this one call
--]]

function Calls.reply(
	self: Runtime,
	id: number,
	player: any,
	slot: number,
	cursor: number,
	sideCursor: number,
	...: any
): (number, number)
	self:_release(id, player, slot, true, ...)
	return cursor, sideCursor
end

--[[
    The reply that refuses a call: the reason is read here, since it is
    the one string every function's refusal carries, and the call is
    settled with it. A status no reply carries is a decode failure.
    Returns the cursors past the reason
--]]

function Calls.refused(
	self: Runtime,
	id: number,
	player: any,
	slot: number,
	status: number,
	packet: buffer,
	cursor: number,
	sideCursor: number,
	length: number
): (number, number)
	local name: string = self._calls[id].name
	if status > STATUS.limited then
		error(`{name}: unknown status {status}`)
	end

	if cursor + PREFIX_BYTES > length then
		error(`{name}: truncated`)
	end

	local count: number = buffer.readu16(packet, cursor)
	cursor += PREFIX_BYTES

	if count > MESSAGE_BYTES or cursor + count > length then
		error(`{name}: truncated`)
	end

	self:_release(id, player, slot, false, buffer.readstring(packet, cursor, count))

	return cursor + count, sideCursor
end

--[[
    The slot table a caller keeps for a function: the client's one, or
    on the server the one for a player, which a call to them opens when
    asked to and which goes when they leave
--]]

function Calls._slots(self: Runtime, id: number, player: any, open: boolean): Slots?
	if not self._server then
		return self._calls[id].slots
	end

	local state: Joined? = self._players[player]
	if not state then
		return nil
	end

	local slots: Slots? = state.calls[id]
	if slots or not open then
		return slots
	end

	local opened: Slots = empty()
	state.calls[id] = opened

	return opened
end

--[[
    Settles a call in flight and frees its slot in the table of whoever
    the reply came from, the server on the client; a call that timed out
    kept its slot for this, and one never made is a decode failure
--]]

function Calls._release(self: Runtime, id: number, player: any, slot: number, ok: boolean, ...: any)
	local slots: Slots? = self:_slots(id, player, false)
	local pending: Pending? = slots and slots.pending[slot]

	if not slots or not pending then
		error(`{self._calls[id].name}: no call in slot {slot}`)
	end

	slots.pending[slot] = nil
	table.insert(slots.free, slot)
	settle(pending, ok, ...)
end

--[[
    Fails every call past its deadline, at each flush. Its slot stays
    taken until the late reply arrives, so a later call can never be
    given another call's answer; every slot table is walked before
    anything is settled, since a resumed caller may call again, which on
    the server can set a player up or open a slot table
--]]

function Calls._sweep(self: Runtime)
	local now: number = os.clock()
	local list: { Pending }? = nil

	if self._server then
		for _, state: Joined in self._players do
			for _, slots: Slots in state.calls do
				list = expired(slots, now, list)
			end
		end
	else
		for _, call: Call in self._calls do
			list = expired(call.slots :: Slots, now, list)
		end
	end

	if list then
		for _, pending: Pending in list do
			settle(pending, false, "timeout")
		end
	end
end

--[[
    Fails every call the server has in flight to a player who left with
    departed, reporting no failure, once their states are gone, so a
    caller resumed here that calls them again fails at once as well
--]]

function Calls._abandon(_: Runtime, state: Joined)
	for _, slots: Slots in state.calls do
		for _, pending: Pending in slots.pending do
			settle(pending, false, "departed")
		end
	end
end

return Calls
