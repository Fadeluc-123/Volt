--[[
    What a send writes once to its scratch state, merged onto the send: a
    broadcast copied into every target it should reach as a message of
    each one's own, and a value taken as one exact packet rather than sent
--]]

--!strict
--!native
local Broadcast = {}

local States = require("./States")
local Types = require("../Config/Types/Send")

type Send = Types.Send
type State = Types.State

--[[
    Copies what a broadcast wrote to the scratch state into every
    target's state, or into those listed or set, or into all but one,
    skipping one who has left or whose handshake failed; then empties the
    scratch state, and only then reports a message a copy dropped
--]]

function Broadcast.broadcast(self: Send, targets: { [any]: any }?, except: any?)
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

	States.reset(self.scratch)
	self:_tell()
end

-- Appends the scratch state's bytes, slots and marks to one target's state as one message of its own
function Broadcast._copy(self: Send, state: State?)
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
    The scratch state's bytes and slots as one exact packet, for a value
    serialised on its own rather than sent; the state is empty again after
--]]

function Broadcast.take(self: Send): (buffer, { any }?)
	local scratch: State = self.scratch
	local bytes: number = scratch.cursor
	local packet: buffer = buffer.create(bytes)
	local side: { any }? = scratch.sideCursor > 1 and table.move(scratch.side, 1, scratch.sideCursor - 1, 1, {}) or nil

	buffer.copy(packet, 0, scratch.out, 0, bytes)
	States.reset(scratch)

	return packet, side
end

return Broadcast
