--[[
    The flush, merged onto a send: every target's bytes fired as exact
    packets, a run of whole messages to a packet while it fits the budget,
    what a hold or a refusal keeps or drops, the message a cap drops, and
    what a player's allowance holds back as packets or drops unsent
--]]

--!strict
--!native
local Flush = {}

local Config = require("../Config/Runtime")
local States = require("./States")
local Traffic = require("../Traffic")
local Types = require("../Config/Types/Send")

type Loss = Types.Loss
type Record = Types.Record
type Send = Types.Send
type State = Types.State
type Stats = Types.Stats
type Waiting = Types.Waiting

local STAMP_BYTES: number = Config.stampBytes
local WINDOW: number = Config.trafficSeconds

--[[
    Fires every target's bytes as exact packets, a run of whole messages
    to a packet while it fits the budget, and empties the states for the
    next frame; a held state keeps its reliable bytes for the flush after
    the handshake, a refused or held unreliable one goes unsent, and a
    drop is reported once the loop is done, since its handler may fire.
    A stamped send's packets carry the server time the flush began at
--]]

function Flush.flush(self: Send, stamp: number?)
	self._stamp = stamp or 0

	-- A send with no allowance pays this one look for it, and each of its states one look at waiting
	local walk: (self: Send, target: any, state: State) -> () = self._send

	if self.allowance then
		walk = self._keeps and self._spend or self._thin
	end

	for target, state: State in self._states do
		if state.cursor > self._cap then
			self:_discard(state)
		end

		if state.refused or state.held and not self._keeps then
			States.reset(state)
			state.waiting = nil
			state.queued = 0
		elseif state.waiting then
			self:_spend(target, state)
		elseif state.cursor > 0 and not state.held then
			walk(self, target, state)
		end
	end

	self:_tell()

	while self._losses[1] do
		local loss: Loss = table.remove(self._losses, 1) :: Loss
		local lost = self.lost :: (target: any, count: number) -> ()

		lost(loss.target, loss.count)
	end
end

-- Whether any target's unsent bytes have reached a size, a held state's aside since a flush could not send them
function Flush.reached(self: Send, bytes: number): boolean
	for _, state: State in self._states do
		if state.cursor >= bytes and not state.held then
			return true
		end
	end

	return false
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

--[[
    Judges a reliable state against its allowance. Over it, with a packet
    sent before, room left under the cap and the oldest waiting packet not
    yet a traffic window old, the frame is cut into a packet that waits;
    otherwise every waiting packet goes in the order cut, then the frame.
    The cap and the window are why a deferral always ends
--]]

function Flush._spend(self: Send, target: any, state: State)
	local allowance: number? = self.allowance
	local waiting: { Waiting }? = state.waiting
	local cursor: number = state.cursor

	if
		allowance
		and state.opened
		and state.queued + cursor <= self._cap
		and (not waiting or os.clock() - state.since < WINDOW)
		and Traffic.sent(state.record :: Record) >= allowance
	then
		if cursor > 0 then
			local packet: buffer, side: { any }? = self:_cut(state, 0, cursor, 1, state.sideCursor)
			local list: { Waiting } = waiting or {}

			if not waiting then
				state.waiting = list
				state.since = os.clock()
			end

			table.insert(list, { packet = packet, side = side })
			state.queued += cursor
			States.reset(state)
		end

		return
	end

	if waiting then
		state.waiting = nil
		state.queued = 0

		for _, held: Waiting in waiting do
			self:_launch(target, state, held.packet, held.side)
		end
	end

	if cursor > 0 then
		self:_send(target, state)
	end
end

--[[
    Keeps the longest run of an unreliable state's whole messages from its
    start that its allowance leaves room for, each kept while the count and
    what is already kept are under it, and sends those as always. The rest
    go unsent, reported once the walk is done
--]]

function Flush._thin(self: Send, target: any, state: State)
	local marks: { number }, sideMarks: { number } = state.marks, state.sideMarks
	local room: number = (self.allowance :: number) - Traffic.sent(state.record :: Record)
	local count: number = #marks
	local kept: number = 0
	local to: number, sideTo: number = 0, 1

	while kept < count and to < room do
		kept += 1
		to, sideTo = marks[kept], sideMarks[kept]
	end

	if kept < count then
		state.cursor = to
		state.sideCursor = sideTo

		-- The slots past it go when the state is emptied, and only its marks are read before then
		for index: number = count, kept + 1, -1 do
			marks[index] = nil
			sideMarks[index] = nil
		end

		table.insert(self._losses, { target = target, count = count - kept })
	end

	if state.cursor > 0 then
		self:_send(target, state)
	else
		States.reset(state)
	end
end

-- One packet of the bytes and slots between two points of a state, fired at once
function Flush._packet(
	self: Send,
	target: any,
	state: State,
	from: number,
	to: number,
	sideFrom: number,
	sideTo: number
)
	local packet: buffer, side: { any }? = self:_cut(state, from, to, sideFrom, sideTo)

	self:_launch(target, state, packet, side)
end

-- An exact copy of the bytes between two points of a state, room left for what opens it, its slots if it holds any
function Flush._cut(
	self: Send,
	state: State,
	from: number,
	to: number,
	sideFrom: number,
	sideTo: number
): (buffer, { any }?)
	local prefix: number = self._prefix
	local packet: buffer = buffer.create(prefix + to - from)
	local side: { any }? = sideTo > sideFrom and table.move(state.side, sideFrom, sideTo - 1, 1, {}) or nil

	buffer.copy(packet, prefix, state.out, from, to - from)

	return packet, side
end

--[[
    Fires a cut packet: the channel byte first, then the stamp of the flush
    sending it, every byte of it counted as it leaves, so one a budget held
    back counts then and reads the flush that sent it
--]]

function Flush._launch(self: Send, target: any, state: State, packet: buffer, side: { any }?)
	local bytes: number = buffer.len(packet)
	local stats: Stats = state.stats :: Stats
	local total: Stats = self._total
	local record: Record? = state.record
	local channel: number? = self._channel

	if channel then
		buffer.writeu8(packet, 0, channel)
	end

	if self._stamped then
		buffer.writef64(packet, self._prefix - STAMP_BYTES, self._stamp)
	end

	stats.packetsOut += 1
	stats.bytesOut += bytes

	total.packetsOut += 1
	total.bytesOut += bytes

	if record then
		Traffic.add(record, bytes)
	end

	state.opened = true

	self._fire(target, packet, side)
end

return Flush
