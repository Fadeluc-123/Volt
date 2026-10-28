--[[
    The plain functions over one send state that a send's files share: a
    blank state for a target, a state emptied for the next frame, and one
    returned to where its last message began, with that message uncounted
--]]

--!strict
--!native
local Config = require("../Config/Runtime")
local Types = require("../Config/Types/Send")

type Record = Types.Record
type State = Types.State
type Stats = Types.Stats

local INITIAL_BYTES: number = Config.initialBytes

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

	state.cursor = state.committed
	state.sideCursor = state.sideCommitted

	if stats then
		stats.messagesOut -= 1
		total.messagesOut -= 1
	end
end

return States
