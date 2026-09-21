--[[
    The send side of one reliability: a state per target with a growing
    buffer, a side array and their cursors; the calls every generated
    writer makes, which begin a message, take its bytes, store a slot or
    refuse a value; the mark a flush splits packets at; a broadcast
    written once and copied; the per-frame cap and the counters
--]]

--!strict
local Send = {} :: any
Send.__index = Send

local Config = require("./Config/Runtime")
local Types = require("./Config/Types/Runtime")

type Fire = Types.Fire
type Stats = Types.Stats

local INITIAL_BYTES: number = Config.initialBytes
local GROWTH: number = Config.growth
local MAX_OUTGOING: number = Config.maxOutgoing

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
}

export type Send = {
	begin: (bytes: number) -> (number, buffer),
	allocate: (bytes: number) -> (number, buffer),
	slot: (value: any) -> (),
	refuse: (message: string) -> (),
	mark: () -> (),
	current: State,
	scratch: State,
	add: (self: Send, target: any, stats: Stats) -> State,
	remove: (self: Send, target: any) -> (),
	broadcast: (self: Send, targets: { [any]: any }?, except: any?) -> (),
	flush: (self: Send) -> (),
}

local function blank(target: any, stats: Stats?): State
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
    A send for one reliability, firing through the transport's function
    for it, counting into the runtime's totals and reporting a dropped
    message for its target. An unreliable send takes the budget one fire
    may carry; a reliable send has no limit. The calls a writer makes are
    plain functions because every generated writer takes them as values
--]]

function Send.new(fire: Fire, total: Stats, dropped: (target: any) -> (), budget: number?): Send
	local scratch: State = blank(nil, nil)
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

		if state.cursor > MAX_OUTGOING then
			(self :: any):_discard(state)
		end

		state.committed = state.cursor
		state.sideCommitted = state.sideCursor

		if stats then
			stats.messagesOut += 1
			total.messagesOut += 1
		end

		return allocate(bytes)
	end

	-- Stores a value at the next side-array index, never with insert, so a nil cannot shift the rest
	local function slot(value: any)
		local state: State = self.current
		state.side[state.sideCursor] = value
		state.sideCursor += 1
	end

	-- Refuses the value a writer is on: the message so far is discarded, and the refusal reaches whoever fired
	local function refuse(message: string)
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
		allocate = allocate,
		slot = slot,
		refuse = refuse,
		mark = mark,
		current = scratch, -- The state the next write lands in, pointed by the runtime's target
		scratch = scratch, -- Where a broadcast is written before it is copied to every target
		_fire = fire,
		_total = total,
		_dropped = dropped,
		_budget = budget or math.huge,
		_states = {} :: { [any]: State },
	}, Send) :: any

	return self
end

-- A state for a target that joined, counting into their counters; nothing is ever sent to a target without one
function Send:add(target: any, stats: Stats): State
	local state: State = blank(target, stats)
	self._states[target] = state
	return state
end

function Send:remove(target: any)
	self._states[target] = nil
end

--[[
    Copies what a broadcast wrote to the scratch state into every
    target's state, or into those listed or set, or into all but one;
    a target that has left is skipped. Then the scratch state is empty
    again
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
end

-- Appends the scratch state's bytes, slots and marks to one target's state as one message of its own
function Send:_copy(state: State?)
	if not state then
		return
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
    Fires every target's bytes as exact packets, then empties the
    states for the next frame. A run of whole messages goes in one
    packet while it fits the budget, so an unreliable fire never carries
    part of a message; a reliable state has no budget and goes in one
--]]

function Send:flush()
	for target, state: State in self._states do
		if state.cursor > MAX_OUTGOING then
			self:_discard(state)
		end

		if state.cursor > 0 then
			self:_send(target, state)
		end
	end
end

-- Drops the message that left a state over the cap, which is the last one written, and reports it for its target
function Send:_discard(state: State)
	rollback(state, self._total)
	self._dropped(state.target)
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

	buffer.copy(packet, 0, state.out, from, bytes)
	
	stats.packetsOut += 1
	stats.bytesOut += bytes
	
	total.packetsOut += 1
	total.bytesOut += bytes
	
	self._fire(target, packet, side)
end

return Send
