--[[
    A transport that keeps every packet fired through it, with the remote
    it went on and its target, before firing it, so a test reads what a
    side sent and on which remote, byte for byte
--]]

--!strict
local Volt = require("@volt")

type Transport = Volt.Transport
type Fire = (target: any, packet: buffer, side: { any }?) -> ()

export type Fired = { remote: string, target: any, packet: buffer } -- R for the Reliable remote, U for the Unreliable

-- Keeps each packet fired through one remote, then fires it
local function keep(remote: string, fire: Fire, fired: { Fired }): Fire
	return function (target: any, packet: buffer, side: { any }?)
		table.insert(fired, { remote = remote, target = target, packet = packet })
		fire(target, packet, side)
	end
end

return function (transport: Transport, fired: { Fired }): Transport
	local copy: Transport = table.clone(transport)

	copy.reliable = keep("R", transport.reliable, fired)
	copy.unreliable = keep("U", transport.unreliable, fired)

	return copy
end
