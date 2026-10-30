--[[
    The client module Volt 0.1.0 generated from Ordered.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

type Bot = Volt.Bot

export type ClientEvent<A...> = { fire: (A...) -> () }

export type ClientListener<A...> = {
	on: (listener: (A...) -> ()) -> () -> (),
	iter: () -> () -> (number, A...),
}

export type ClientPolling<A...> = { iter: () -> () -> (number, A...) }

export type ClientFunction<A..., R...> = { invoke: (A...) -> (boolean, R...) }

export type ClientPromise<A...> = { invoke: (A...) -> any }

export type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime
local beginUnreliable: (number) -> (number, buffer)
local refuseUnreliable: (string) -> never
local markUnreliable: () -> ()
local orderUnreliable: (number) -> number

local function writeAim(yaw: number, pitch: number)
	local offset: number, out: buffer = beginUnreliable(7)
	buffer.writeu8(out, offset, 1)
	buffer.writeu16(out, offset + 1, orderUnreliable(1))

	if type(yaw) ~= "number" or yaw ~= yaw then
		refuseUnreliable("Aim.yaw: expected q16(-3.2..3.2)")
	end

	buffer.writeu16(out, offset + 3, math.round((math.clamp(yaw, -3.2, 3.2) + 3.2) / 6.4 * 65535))

	if type(pitch) ~= "number" or pitch ~= pitch then
		refuseUnreliable("Aim.pitch: expected q16(-1.6..1.6)")
	end

	buffer.writeu16(out, offset + 5, math.round((math.clamp(pitch, -1.6, 1.6) + 1.6) / 3.2 * 65535))
	markUnreliable()
end

local function readAim(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 6 > length then
		error("Aim: truncated")
	end

	local sequence: number = buffer.readu16(packet, cursor)
	local yaw: number = -3.2 + buffer.readu16(packet, cursor + 2) / 65535 * 6.4
	local pitch: number = -1.6 + buffer.readu16(packet, cursor + 4) / 65535 * 3.2
	cursor += 6

	return runtime:ordered(1, sequence, player, cursor, sideCursor, yaw, pitch)
end

local function readSpray(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Spray: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(2, player, cursor, sideCursor, value)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xAF570C31,
	scope = "Ordered",
	side = "client",
	idBytes = 1,
	options = {
		flush = 1,
		manualReplication = false,
		maxOutgoing = 262144,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
		writeValidation = true,
	},

	messages = {
		[1] = { name = "Aim", kind = "event", mode = "SingleSync", queue = 64, read = readAim },
		[2] = { name = "Spray", kind = "event", mode = "ManyAsync", queue = 64, read = readSpray },
	},

	outgoing = {
		[1] = { name = "Aim", kind = "event", reliable = false, sequence = 1, minBytes = 7, maxBytes = 7 },
	},
})

beginUnreliable = runtime.unreliable.begin
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark
orderUnreliable = runtime.unreliable.order

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Aim = table.freeze({
		fire = function (yaw: number, pitch: number)
			if before[1] == nil or before[1](nil, yaw, pitch) then
				writeAim(yaw, pitch)
			end
		end,

		on = function (listener: (yaw: number, pitch: number) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, number, number)
			return runtime:iter(1)
		end,
	}) :: ClientEvent<(number, number)> & ClientListener<(number, number)>,

	Spray = table.freeze({
		on = function (listener: (value: number) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, number)
			return runtime:iter(2)
		end,
	}) :: ClientListener<(number)>,

	version = "0.1.0",

	hooks = table.freeze({
		beforeSend = runtime.beforeSend,
		afterReceive = runtime.afterReceive,
	}),

	rate = runtime.rate,

	flush = function ()
		runtime:flush()
	end,

	onFailure = function (handler: Volt.Failure): Volt.Failure
		return runtime:onFailure(handler)
	end,

	stats = function (player: (Player | Bot)?): Volt.Stats
		return runtime:stats(player)
	end,
}

Network.events = table.freeze({
	["Aim"] = Network.Aim,
	["Spray"] = Network.Spray,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
