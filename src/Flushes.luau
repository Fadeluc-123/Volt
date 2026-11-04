--[[
    The runtime's flush, merged onto it: what the Heartbeat runs whenever
    a flush is due and a generated module's flush calls, and the check of
    whether a target's unsent bytes have reached flushBytes
--]]

--!strict
local Flushes = {}

local Types = require("./Config/Types/Runtime")

type Runtime = Types.Runtime
type Send = Types.Send

--[[
    Fails the calls and drops the awaited messages past their deadlines,
    sends every target's accumulated bytes, the default stream's first,
    then each channel's in order, then the unreliable, with each send's
    drops reported, then announces every handshake accepted before it
    began, in the order read, for each player still here; the Heartbeat
    does this whenever a flush is due
--]]

function Flushes.flush(self: Runtime)
	local accepted: { any }? = nil
	local clock: (() -> number)? = self._clock
	local stamp: number? = clock and clock() -- The time every packet of this flush opens with, on a stamped server

	-- Taken first, so a handshake accepted while this runs is left for a later flush and nobody is announced twice
	if self._accepted[1] ~= nil then
		accepted = self._accepted
		self._accepted = {}
	end

	self:_sweep()
	self:_expire()
	self.reliable:flush(stamp)

	for _, stream: Send in self.streams do
		stream:flush(stamp)
	end

	self.unreliable:flush(stamp)

	if accepted then
		for _, player: any in accepted do
			if self._players[player] then
				self:_announce(self._handshakes, player)
			end
		end
	end
end

-- Whether one target's unsent bytes on any send have reached a size, which is what flushBytes flushes at
function Flushes._piled(self: Runtime, bytes: number): boolean
	if self.reliable:reached(bytes) or self.unreliable:reached(bytes) then
		return true
	end

	for _, stream: Send in self.streams do
		if stream:reached(bytes) then
			return true
		end
	end

	return false
end

return Flushes
