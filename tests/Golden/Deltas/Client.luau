--[[
    The client module Volt 0.1.0 generated from Deltas.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Vitals = { health: number, stamina: number, title: string, held: number?, gear: { shield: boolean, boots: boolean } }

type Bot = Volt.Bot

type ClientEvent<A...> = { fire: (A...) -> () }

type ClientListener<A...> = {
	on: (listener: (A...) -> ()) -> () -> (),
	iter: () -> () -> (number, A...),
}

type ClientPolling<A...> = { iter: () -> () -> (number, A...) }

type ClientFunction<A..., R...> = { invoke: (A...) -> (boolean, R...) }

type ClientPromise<A...> = { invoke: (A...) -> any }

type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime

local function readvitals(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("vitals: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local health: number
	local stamina: number
	local title: string
	local held: number?
	local gear: { shield: boolean, boots: boolean }
	cursor += 1

	if bit32.btest(flags, 1) then
		if cursor + 1 > length then
			error("vitals.health: truncated")
		end

		local health_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		health = health_2
	end

	if bit32.btest(flags, 2) then
		if cursor + 1 > length then
			error("vitals.stamina: truncated")
		end

		local stamina_2: number = buffer.readu8(packet, cursor)

		if stamina_2 > 100 then
			error("vitals.stamina: out of range")
		end

		cursor += 1
		stamina = stamina_2
	end

	if bit32.btest(flags, 4) then
		if cursor + 1 > length then
			error("vitals.title: truncated")
		end

		local titleLength: number = buffer.readu8(packet, cursor)

		if titleLength > 16 then
			error("vitals.title: length out of range")
		end

		cursor += 1

		if cursor + titleLength > length then
			error("vitals.title: truncated")
		end

		local title_2: string = buffer.readstring(packet, cursor, titleLength)
		cursor += titleLength
		title = title_2
	end

	if bit32.btest(flags, 8) then
		if cursor + 1 > length then
			error("vitals.held: truncated")
		end

		local flags_2: number = buffer.readu8(packet, cursor)
		local held_2: number?
		cursor += 1

		if bit32.btest(flags_2, 1) then
			if cursor + 2 > length then
				error("vitals.held: truncated")
			end

			local held_3: number = buffer.readu16(packet, cursor)
			cursor += 2
			held_2 = held_3
		end

		held = held_2
	end

	if bit32.btest(flags, 16) then
		if cursor + 1 > length then
			error("vitals.gear: truncated")
		end

		local flags_3: number = buffer.readu8(packet, cursor)
		cursor += 1
		local gear_2 = { shield = bit32.btest(flags_3, 1), boots = bit32.btest(flags_3, 2) }
		gear = gear_2
	end

	return runtime:deliver(1, player, cursor, sideCursor, runtime:merge(1, flags, { health = health, stamina = stamina, title = title, held = held, gear = gear }))
end

local function readzone(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("zone: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local id: number
	local safe: boolean
	cursor += 1

	if bit32.btest(flags, 1) then
		if cursor + 2 > length then
			error("zone.id: truncated")
		end

		local id_2: number = buffer.readu16(packet, cursor)
		cursor += 2
		id = id_2
	end

	if bit32.btest(flags, 2) then
		if cursor + 1 > length then
			error("zone.safe: truncated")
		end

		local flags_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		safe = bit32.btest(flags_2, 1)
	end

	return runtime:deliver(2, player, cursor, sideCursor, runtime:merge(2, flags, { id = id, safe = safe }))
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x917D2C44,
	scope = "Deltas",
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
		[1] = { name = "vitals", kind = "event", mode = "SingleAsync", queue = 64, fields = { "health", "stamina", "title", "held", "gear" }, read = readvitals },
		[2] = { name = "zone", kind = "event", mode = "Polling", queue = 64, fields = { "id", "safe" }, read = readzone },
	},

	outgoing = {},
})

local Network = {
	vitals = table.freeze({
		on = function (listener: (value: Vitals) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Vitals)
			return runtime:iter(1)
		end,
	}) :: ClientListener<(Vitals)>,

	zone = table.freeze({
		iter = function (): () -> (number, { id: number, safe: boolean })
			return runtime:iter(2)
		end,
	}) :: ClientPolling<({ id: number, safe: boolean })>,

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
	["vitals"] = Network.vitals,
	["zone"] = Network.zone,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
