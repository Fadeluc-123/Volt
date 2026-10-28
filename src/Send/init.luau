--[[
    The send side of one reliability: a state per target with a growing
    buffer, a side array and their cursors; the calls every generated
    writer makes to begin or trim a message, take bytes, store a slot or
    refuse a value; and what a raise leaves taken back
--]]

--!strict
--!native
local Send = {}
Send.__index = Send

-- An init file's ./ is its folder's parent, so the send's own files are named through its folder
local Broadcast = require("./Send/Broadcast")
local Config = require("./Config/Runtime")
local Flush = require("./Send/Flush")
local States = require("./Send/States")
local Types = require("./Config/Types/Send")

local GROWTH: number = Config.growth
local POSITION: string = Config.position

export type Send = Types.Send
export type State = Types.State

type Fields = Types.Fields
type Fire = Types.Fire
type Record = Types.Record
type Self = Types.Send
type Stats = Types.Stats

--[[
    A send for one reliability over the transport's fire, counting into the
    runtime's totals and reporting a dropped message for its target, with the
    cap a target's frame may hold and, unreliable, the budget one fire may
    carry. A writer's calls are plain functions, as writers take them as values
--]]

function Send.new(fire: Fire, total: Stats, dropped: (target: any) -> (), cap: number, budget: number?): Self
	local scratch: State = States.blank(nil, nil, nil, false)
	local send: Fields -- What a writer's calls reach, the send's own fields once they are built below

	-- Takes bytes at the end of the current buffer, growing it when the frame needs more than it holds
	local function allocate(bytes: number): (number, buffer)
		local state: State = send.current
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
		local state: State = send.current
		local stats: Stats? = state.stats

		if state.cursor > cap then
			States.rollback(state, total)
			dropped(state.target)
			send.current = state -- The failure handler may have fired, which points the send at another target
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
		send.current.cursor = offset
	end

	-- Stores a value at the next side-array index, never with insert, so a nil cannot shift the rest
	local function slot(value: any)
		local state: State = send.current
		state.side[state.sideCursor] = value
		state.sideCursor += 1
	end

	-- Refuses the value a writer is on: the message so far is discarded, and the refusal reaches whoever fired
	local function refuse(message: string): never
		States.rollback(send.current, total)
		error(message, 0)
	end

	-- Ends a message, so a flush can split the packet between messages and never inside one
	local function mark()
		local state: State = send.current
		table.insert(state.marks, state.cursor)
		table.insert(state.sideMarks, state.sideCursor)
	end

	local fields: Fields = {
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
	}

	-- The closures keep a local of their own, since the checker retypes the one handed to setmetatable
	send = fields

	return setmetatable(fields, Send) :: any
end

-- A joiner's state, counting into their counters and byte count, held until their handshake when a client will send one
function Send.add(self: Self, target: any, stats: Stats, record: Record?, held: boolean?): State
	local state: State = States.blank(target, stats, record, held == true)

	self._states[target] = state

	if record then
		record.states[state] = true
	end

	return state
end

function Send.remove(self: Self, target: any)
	local state: State? = self._states[target]
	local record: Record? = state and state.record

	if record then
		record.states[state] = nil
	end

	self._states[target] = nil
end

--[[
    Takes back what a writer left in the current state when it raised and
    returns the error to raise again: a refusal returned the state already
    and goes on as it was, while anything else left bytes behind, since
    begin takes the id at least, so they go, uncounted, and the error is named
--]]

function Send.undo(self: Self, name: string, message: any): string
	local state: State = self.current
	if state.cursor == state.committed then
		return tostring(message)
	end

	States.rollback(state, self._total)

	return `{name}: {(tostring(message):gsub(POSITION, ""))}`
end

local _: Types.Own, _: Types.Broadcast, _: Types.Flush = Send, Broadcast, Flush

-- A broadcast and the flush are a sibling each; a name defined twice is a bug
local parts: { any } = { Broadcast, Flush }

for _, part in parts do
	for name: string, method in part do
		assert(Send[name] == nil, `Send.{name} is defined twice`)
		Send[name] = method
	end
end

return Send
