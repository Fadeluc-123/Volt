--[[
    The client module Volt 0.1.0 generated from Broadcasts.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Hit = { target: number, amount: number }

export type ClientEvent<A...> = { fire: (A...) -> () }

export type ClientListener<A...> = {
	on: (listener: (A...) -> ()) -> () -> (),
	iter: () -> () -> (number, A...),
}

export type ClientFunction<A..., R...> = { invoke: (A...) -> (boolean, R...) }

export type ClientPromise<A...> = { invoke: (A...) -> any }

export type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime

local function readDamage(player: Player?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Damage: truncated")
	end

	local target: number = buffer.readu16(packet, cursor)
	local amount: number = buffer.readu8(packet, cursor + 2)
	cursor += 3
	local value = { target = target, amount = amount }

	return runtime:deliver(1, player, cursor, sideCursor, value)
end

local function readSpray(player: Player?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Spray: truncated")
	end

	local x: number = buffer.readu8(packet, cursor)
	local y: number = buffer.readu8(packet, cursor + 1)
	cursor += 2

	return runtime:deliver(2, player, cursor, sideCursor, x, y)
end

local function readMatch_Start(player: Player?, _: buffer, cursor: number, _: { any }, sideCursor: number, _: number): (number, number)
	return runtime:deliver(3, player, cursor, sideCursor)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x81227874,
	scope = "Broadcasts",
	side = "client",
	idBytes = 1,
	options = {
		flush = 1,
		manualReplication = false,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
	},

	messages = {
		[1] = { name = "Damage", kind = "event", mode = "SingleSync", queue = 64, read = readDamage },
		[2] = { name = "Spray", kind = "event", mode = "ManyAsync", queue = 64, read = readSpray },
		[3] = { name = "Match.Start", kind = "event", mode = "Polling", queue = 64, read = readMatch_Start },
	},

	outgoing = {},
})

local net = {
	Damage = table.freeze({
		on = function (listener: (value: Hit) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Hit)
			return runtime:iter(1)
		end,
	}),

	Spray = table.freeze({
		on = function (listener: (x: number, y: number) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, number, number)
			return runtime:iter(2)
		end,
	}),

	Match = table.freeze({
		Start = table.freeze({
			iter = function (): () -> (number)
				return runtime:iter(3)
			end,
		}),
	}),

	hooks = table.freeze({
		beforeSend = runtime.beforeSend,
		afterReceive = runtime.afterReceive,
	}),

	rate = runtime.rate,

	flush = function ()
		runtime:flush()
	end,

	onFailure = function (handler: Volt.Failure)
		runtime:onFailure(handler)
	end,

	stats = function (player: Player?): Volt.Stats
		return runtime:stats(player)
	end,
}

net.events = table.freeze({
	["Damage"] = net.Damage,
	["Spray"] = net.Spray,
	["Match.Start"] = net.Match.Start,
})

net.functions = table.freeze({})
net.exports = table.freeze({})

return table.freeze(net)
