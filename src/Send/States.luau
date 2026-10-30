--[[
    The plain functions over one send state that a send's files share: a
    blank state for a target, a state emptied for the next frame, one
    returned to where its last message began, with that message uncounted,
    and the next sequence of an ordered event sent to the state's target
--]]

--!strict
--!native
local Config = require("../Config/Runtime")
local Types = require("../Config/Types/Send")

type Record = Types.Record
type State = Types.State
type Stats = Types.Stats

local INITIAL_BYTES: number = Config.initialBytes
local SEQUENCES: number = Config.sequences

local States = {}

-- A state for one target, or for the scratch state when there is none, with a buffer at its first size
function States.blank(target: any, stats: Stats?, record: Record?, held: boolean): State
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
		queued = 0,
		since = 0,
		opened = false,
	}
end

-- Empties a state for the next frame, keeping its buffer and its tables
function States.reset(state: State)
	state.cursor = 0
	state.sideCursor = 1
	state.committed = 0
	state.sideCommitted = 1

	table.clear(state.side)
	table.clear(state.marks)
	table.clear(state.sideMarks)
end

-- Returns a state to where its last message began and uncounts that message, so it is as if never written
function States.rollback(state: State, total: Stats)
	local stats: Stats? = state.stats
	local marks: { number } = state.marks

	state.cursor = state.committed
	state.sideCursor = state.sideCommitted

	-- A message a cap drops has marked its end already, and a mark left past the cursor would name bytes that are gone
	while marks[#marks] and marks[#marks] > state.cursor do
		table.remove(marks)
		table.remove(state.sideMarks)
	end

	if stats then
		stats.messagesOut -= 1
		total.messagesOut -= 1
	end
end

-- The next sequence of an ordered event to the state's target: 1 first, then one more, wrapping to 0 after 65535
function States.next(state: State, id: number): number
	local sequences: { [number]: number } = state.sequences or {}
	local sequence: number = ((sequences[id] or 0) + 1) % SEQUENCES

	sequences[id] = sequence
	state.sequences = sequences

	return sequence
end

return States
