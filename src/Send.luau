--[[
    The send side of one reliability: a state per target with a growing
    buffer, a side array and their cursors; the calls every generated
    writer makes to begin or trim a message, take bytes, store a slot or
    refuse a value; what a raise leaves taken back; the flush's marks and
    holds; a broadcast written once and copied; the cap and the counters
--]]

--!strict
--!native
local Send = {} :: any
Send.__index = Send

local Config = require("./Config/Runtime")
local Traffic = require("./Traffic")
local Types = require("./Config/Types/Runtime")

type Fire = Types.Fire
type Record = Types.Record
type Stats = Types.Stats

local INITIAL_BYTES: number = Config.initialBytes
local GROWTH: number = Config.growth
local POSITION: string = Config.position

export type State = {
	out: buffer,
	cursor: number,
	side: { any },
	sideCursor: number,
	marks: { number }, -- The cursor after each message, where a packet may be split
	sideMarks: { number }, -- The side cursor after each message
	committed: number, -- The cursor where the last message began, which a refusal or a drop returns to
	sideCommitted: number, -- The side cursor where it began
	target: any, -- Who the state's bytes go to; nil for the scratch state
	stats: Stats?, -- The target's counters; the scratch state has none, since a broadcast counts once per target
	record: Record?, -- The target's byte count across the VM, for a player or a bot
	held: boolean, -- Until the player's handshake: a flush keeps reliable bytes and drops unreliable ones
	refused: boolean, -- After a failed handshake: nothing is written or kept for the player again
}

export type Send = {
	begin: (bytes: number) -> (number, buffer),
	trim: (offset: number) -> (),
	allocate: (bytes: number) -> (number, buffer),
	slot: (value: any) -> (),
	refuse: (message: string) -> never,
	mark: () -> (),
	current: State,
	scratch: State,
	add: (self: Send, target: any, stats: Stats, record: Record?, held: boolean?) -> State,
	remove: (self: Send, target: any) -> (),
	broadcast: (self: Send, targets: { [any]: any }?, except: any?) -> (),
	undo: (self: Send, name: string, message: any) -> string,
	take: (self: Send) -> (buffer, { any }?),
	flush: (self: Send) -> (),
}

local function blank(target: any, stats: Stats?, record: Record?, held: boolean): State
	return {
		out = buffer.create(INITIAL_BYTES),
		cursor = 0,
		side = {},
		sideCursor = 1,
		marks = {},
		sideMarks = {},
		committed = 0,
		sideCommitted = 1,
		target = target,
		stats = stats,
		record = record,
		held = held,
		refused = false,
	}
end

-- Empties a state for the next frame, keeping its buffer and its tables
local function reset(state: State)
	state.cursor = 0
	state.sideCursor = 1
	state.committed = 0
	state.sideCommitted = 1

	table.clear(state.side)
	table.clear(state.marks)
	table.clear(state.sideMarks)
end

-- Returns a state to where its last message began and uncounts that message, so it is as if never written
local function rollback(state: State, total: Stats)
	local stats: Stats? = state.stats

	state.cursor = state.committed
	state.sideCursor = state.sideCommitted

	if stats then
		stats.messagesOut -= 1
		total.messagesOut -= 1
	end
end

--[[
    A send for one reliability over the transport's fire, counting into the
    runtime's totals and reporting a dropped message for its target, with the
    cap a target's frame may hold and, unreliable, the budget one fire may
    carry. A writer's calls are plain functions, as writers take them as values
--]]

function Send.new(fire: Fire, total: Stats, dropped: (target: any) -> (), cap: number, budget: number?): Send
	local scratch: State = blank(nil, nil, nil, false)
	local self: Send

	-- Takes bytes at the end of the current buffer, growing it when the frame needs more than it holds
	local function allocate(bytes: number): (number, buffer)
		local state: State = self.current
		local cursor: number = state.cursor
		local out: buffer = state.out
		local needed: number = cursor + bytes

		if needed > buffer.len(out) then
			local grown: buffer = buffer.create(math.max(needed, math.ceil(buffer.len(out) * GROWTH)))
			buffer.copy(grown, 0, out, 0, cursor)
			state.out = grown
			out = grown
		end

		state.cursor = needed

		return cursor, out
	end

	--[[
	    Begins a message: drops the one before it when that left the state
	    over the cap, records where this one starts so a refusal can return
	    to it, counts it, and takes its first bytes
	--]]

	local function begin(bytes: number): (number, buffer)
		local state: State = self.current
		local stats: Stats? = state.stats

		if state.cursor > cap then
			rollback(state, total)
			dropped(state.target)
			self.current = state -- The failure handler may have fired, which points the send at another target
		end

		state.committed = state.cursor
		state.sideCommitted = state.sideCursor

		if stats then
			stats.messagesOut += 1
			total.messagesOut += 1
		end

		return allocate(bytes)
	end

	-- Ends a message that began with its largest size where its bytes did, so the next begins right after them
	local function trim(offset: number)
		self.current.cursor = offset
	end

	-- Stores a value at the next side-array index, never with insert, so a nil cannot shift the rest
	local function slot(value: any)
		local state: State = self.current
		state.side[state.sideCursor] = value
		state.sideCursor += 1
	end

	-- Refuses the value a writer is on: the message so far is discarded, and the refusal reaches whoever fired
	local function refuse(message: string): never
		rollback(self.current, total)
		error(message, 0)
	end

	-- Ends a message, so a flush can split the packet between messages and never inside one
	local function mark()
		local state: State = self.current
		table.insert(state.marks, state.cursor)
		table.insert(state.sideMarks, state.sideCursor)
	end

	self = setmetatable({
		begin = begin,
		trim = trim,
		allocate = allocate,
		slot = slot,
		refuse = refuse,
		mark = mark,
		current = scratch, -- The state the next write lands in, pointed by the runtime's target
		scratch = scratch, -- Where a broadcast is written before it is copied to every target
		_fire = fire,
		_total = total,
		_dropped = dropped,
		_cap = cap,
		_budget = budget or math.huge,
		_keeps = budget == nil, -- A reliable send has no budget and keeps a held state's bytes; an unreliable one drops them
		_states = {} :: { [any]: State },
		_drops = {} :: { any }, -- Whom a copy or a flush dropped a message for, told once its loop is done
	}, Send) :: any

	return self
end

-- A joiner's state, counting into their counters and byte count, held until their handshake when a client will send one
function Send:add(target: any, stats: Stats, record: Record?, held: boolean?): State
	local state: State = blank(target, stats, record, held == true)

	self._states[target] = state

	if record then
		record.states[state] = true
	end

	return state
end

function Send:remove(target: any)
	local state: State? = self._states[target]
	local record: Record? = state and state.record

	if record then
		record.states[state] = nil
	end

	self._states[target] = nil
end

--[[
    Copies what a broadcast wrote to the scratch state into every
    target's state, or into those listed or set, or into all but one,
    skipping one who has left or whose handshake failed; then empties the
    scratch state, and only then reports a message a copy dropped
--]]

function Send:broadcast(targets: { [any]: any }?, except: any?)
	if targets then
		-- A list carries its players as values and a set as keys
		for key, value in targets do
			self:_copy(self._states[typeof(key) == "number" and value or key])
		end
	else
		for target, state: State in self._states do
			if target ~= except then
				self:_copy(state)
			end
		end
	end

	reset(self.scratch)
	self:_tell()
end

-- Appends the scratch state's bytes, slots and marks to one target's state as one message of its own
function Send:_copy(state: State?)
	if not state or state.refused then
		return
	end

	if state.cursor > self._cap then
		self:_discard(state) -- A handler told now could broadcast and empty the scratch state mid copy
	end

	local scratch: State = self.scratch
	local was: State = self.current
	local sideBase: number = state.sideCursor

	self.current = state
	local offset: number, out: buffer = self.begin(scratch.cursor)
	self.current = was

	buffer.copy(out, offset, scratch.out, 0, scratch.cursor)

	for index = 1, scratch.sideCursor - 1 do
		state.side[state.sideCursor] = scratch.side[index]
		state.sideCursor += 1
	end

	for index: number, mark: number in scratch.marks do
		table.insert(state.marks, offset + mark)
		table.insert(state.sideMarks, sideBase + scratch.sideMarks[index] - 1)
	end
end

--[[
    Takes back what a writer left in the current state when it raised and
    returns the error to raise again: a refusal returned the state already
    and goes on as it was, while anything else left bytes behind, since
    begin takes the id at least, so they go, uncounted, and the error is named
--]]

function Send:undo(name: string, message: any): string
	local state: State = self.current
	if state.cursor == state.committed then
		return tostring(message)
	end

	rollback(state, self._total)

	return `{name}: {(tostring(message):gsub(POSITION, ""))}`
end

--[[
    The scratch state's bytes and slots as one exact packet, for a value
    serialised on its own rather than sent; the state is empty again after
--]]

function Send:take(): (buffer, { any }?)
	local scratch: State = self.scratch
	local bytes: number = scratch.cursor
	local packet: buffer = buffer.create(bytes)
	local side: { any }? = scratch.sideCursor > 1 and table.move(scratch.side, 1, scratch.sideCursor - 1, 1, {}) or nil

	buffer.copy(packet, 0, scratch.out, 0, bytes)
	reset(scratch)

	return packet, side
end

--[[
    Fires every target's bytes as exact packets, a run of whole messages
    to a packet while it fits the budget, and empties the states for the
    next frame; a held state keeps its reliable bytes for the flush after
    the handshake, a refused or held unreliable one goes unsent, and a
    drop is reported once the loop is done, since its handler may fire
--]]

function Send:flush()
	for target, state: State in self._states do
		if state.cursor > self._cap then
			self:_discard(state)
		end

		if state.refused or state.held and not self._keeps then
			reset(state)
		elseif state.cursor > 0 and not state.held then
			self:_send(target, state)
		end
	end

	self:_tell()
end

-- Drops the message that left a state over the cap, the last one written, and keeps its target to be told
function Send:_discard(state: State)
	rollback(state, self._total)
	table.insert(self._drops, state.target)
end

-- Tells the runtime of every message dropped since it was last told, once the writes that dropped them are done
function Send:_tell()
	while self._drops[1] do
		self._dropped(table.remove(self._drops, 1))
	end
end

function Send:_send(target: any, state: State)
	local budget: number = self._budget
	local from: number, sideFrom: number = 0, 1
	local to: number, sideTo: number = 0, 1

	for index: number, mark: number in state.marks do
		if mark - from > budget and to > from then
			self:_packet(target, state, from, to, sideFrom, sideTo)
			from, sideFrom = to, sideTo
		end

		to, sideTo = mark, state.sideMarks[index]
	end

	self:_packet(target, state, from, state.cursor, sideFrom, state.sideCursor)
	reset(state)
end

-- One packet of the bytes and slots between two points of a state, with no side array when it holds no slot, counted
function Send:_packet(target: any, state: State, from: number, to: number, sideFrom: number, sideTo: number)
	local bytes: number = to - from
	local packet: buffer = buffer.create(bytes)
	local side: { any }? = sideTo > sideFrom and table.move(state.side, sideFrom, sideTo - 1, 1, {}) or nil
	local stats: Stats = state.stats :: Stats
	local total: Stats = self._total
	local record: Record? = state.record

	buffer.copy(packet, 0, state.out, from, bytes)

	stats.packetsOut += 1
	stats.bytesOut += bytes

	total.packetsOut += 1
	total.bytesOut += bytes

	if record then
		Traffic.add(record, bytes)
	end

	self._fire(target, packet, side)
end

return Send
