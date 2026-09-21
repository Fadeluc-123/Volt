--[[
    The send side of one reliability: a state per target holding a
    growing buffer, its cursor, a side array and its cursor; the
    allocator and slot store every generated writer calls; an exact
    packet per target at flush, split at message marks to fit a budget;
    and a broadcast written once to a scratch state and copied
--]]

--!strict
local Send = {} :: any
Send.__index = Send

local Config = require("./Config/Runtime")
local Types = require("./Config/Types/Runtime")

type Fire = Types.Fire

local INITIAL_BYTES: number = Config.initialBytes
local GROWTH: number = Config.growth

export type State = {
	out: buffer,
	cursor: number,
	side: { any },
	sideCursor: number,
	marks: { number }, -- The cursor after each message, where a packet may be split
	sideMarks: { number }, -- The side cursor after each message
}

export type Send = {
	allocate: (bytes: number) -> (number, buffer),
	slot: (value: any) -> (),
	mark: () -> (),
	current: State,
	scratch: State,
	add: (self: Send, target: any) -> State,
	remove: (self: Send, target: any) -> (),
	broadcast: (self: Send, targets: { [any]: any }?, except: any?) -> (),
	flush: (self: Send) -> (),
}

local function blank(): State
	return { out = buffer.create(INITIAL_BYTES), cursor = 0, side = {}, sideCursor = 1, marks = {}, sideMarks = {} }
end

-- Empties a state for the next frame, keeping its buffer and its tables
local function reset(state: State)
	state.cursor = 0
	state.sideCursor = 1

	table.clear(state.side)
	table.clear(state.marks)
	table.clear(state.sideMarks)
end

--[[
    A send for one reliability, firing through the transport's function
    for it. An unreliable send takes the budget one fire may carry; a
    reliable send has no limit. The allocator, slot store and mark are
    plain functions because every generated writer takes them as values
--]]

function Send.new(fire: Fire, budget: number?): Send
	local scratch: State = blank()
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

	-- Stores a value at the next side-array index, never with insert, so a nil cannot shift the rest
	local function slot(value: any)
		local state: State = self.current
		state.side[state.sideCursor] = value
		state.sideCursor += 1
	end

	-- Ends a message, so a flush can split the packet between messages and never inside one
	local function mark()
		local state: State = self.current
		table.insert(state.marks, state.cursor)
		table.insert(state.sideMarks, state.sideCursor)
	end

	self = setmetatable({
		allocate = allocate,
		slot = slot,
		mark = mark,
		current = scratch, -- The state the next write lands in, pointed by the runtime's target
		scratch = scratch, -- Where a broadcast is written before it is copied to every target
		_fire = fire,
		_budget = budget or math.huge,
		_states = {} :: { [any]: State },
	}, Send) :: any

	return self
end

-- A state for a target that joined; nothing is ever sent to a target without one
function Send:add(target: any): State
	local state: State = blank()
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

-- Appends the scratch state's bytes, slots and marks to one target's state
function Send:_copy(state: State?)
	if not state then
		return
	end

	local scratch: State = self.scratch
	local was: State = self.current
	local sideBase: number = state.sideCursor

	self.current = state
	local offset: number, out: buffer = self.allocate(scratch.cursor)
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
		if state.cursor > 0 then
			self:_send(target, state)
		end
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

-- One packet of the bytes and slots between two points of a state, with no side array when it holds no slot
function Send:_packet(target: any, state: State, from: number, to: number, sideFrom: number, sideTo: number)
	local packet: buffer = buffer.create(to - from)
	local side: { any }? = sideTo > sideFrom and table.move(state.side, sideFrom, sideTo - 1, 1, {}) or nil

	buffer.copy(packet, 0, state.out, from, to - from)
	self._fire(target, packet, side)
end

return Send
