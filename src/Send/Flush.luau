--[[
    The flush, merged onto a send: every target's bytes fired as exact
    packets, a run of whole messages to a packet while it fits the budget,
    what a hold or a refusal keeps or drops, the message a cap drops and the
    runtime told of it once a loop is done, and every packet counted
--]]

--!strict
--!native
local Flush = {}

local States = require("./States")
local Traffic = require("../Traffic")
local Types = require("../Config/Types/Send")

type Record = Types.Record
type Send = Types.Send
type State = Types.State
type Stats = Types.Stats

--[[
    Fires every target's bytes as exact packets, a run of whole messages
    to a packet while it fits the budget, and empties the states for the
    next frame; a held state keeps its reliable bytes for the flush after
    the handshake, a refused or held unreliable one goes unsent, and a
    drop is reported once the loop is done, since its handler may fire
--]]

function Flush.flush(self: Send)
	for target, state: State in self._states do
		if state.cursor > self._cap then
			self:_discard(state)
		end

		if state.refused or state.held and not self._keeps then
			States.reset(state)
		elseif state.cursor > 0 and not state.held then
			self:_send(target, state)
		end
	end

	self:_tell()
end

-- Drops the message that left a state over the cap, the last one written, and keeps its target to be told
function Flush._discard(self: Send, state: State)
	States.rollback(state, self._total)
	table.insert(self._drops, state.target)
end

-- Tells the runtime of every message dropped since it was last told, once the writes that dropped them are done
function Flush._tell(self: Send)
	while self._drops[1] do
		self._dropped(table.remove(self._drops, 1))
	end
end

function Flush._send(self: Send, target: any, state: State)
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
	States.reset(state)
end

-- One packet of the bytes and slots between two points of a state, with no side array when it holds no slot, counted
function Flush._packet(
	self: Send,
	target: any,
	state: State,
	from: number,
	to: number,
	sideFrom: number,
	sideTo: number
)
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

return Flush
