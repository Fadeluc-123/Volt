--[[
    The server module Volt 0.1.0 generated from Deltas.volt: a writer per
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

type ServerEvent<A...> = {
	fire: (player: Player | Bot, A...) -> (),
	fireAll: (A...) -> (),
	fireList: (players: { Player | Bot }, A...) -> (),
	fireExcept: (player: Player | Bot, A...) -> (),
	fireSet: (players: { [Player | Bot]: true }, A...) -> (),
}

type ServerListener<A...> = {
	on: (listener: (player: Player | Bot, A...) -> ()) -> () -> (),
	iter: () -> () -> (number, Player | Bot, A...),
}

type ServerPolling<A...> = { iter: () -> () -> (number, Player | Bot, A...) }

type ServerFunction<A..., R...> = {
	on: (handler: (player: Player | Bot, A...) -> R...) -> () -> (),
}

type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local trimReliable: (number) -> ()
local refuseReliable: (string) -> never

local function writevitals(mask: number, value: Vitals)
	local offset: number, out: buffer = beginReliable(25)
	buffer.writeu8(out, offset, 1)

	if type(value) ~= "table" then
		refuseReliable("vitals: expected table")
	end

	local flags: number = 0
	flags += bit32.band(mask, 1)
	flags += bit32.band(mask, 2)
	flags += bit32.band(mask, 4)
	flags += bit32.band(mask, 8)
	flags += bit32.band(mask, 16)
	buffer.writeu8(out, offset + 1, flags)
	offset += 2

	if bit32.btest(mask, 1) then
		local health = value.health

		if type(health) ~= "number" or bit32.band(health, 255) ~= health then
			refuseReliable("vitals.health: expected u8")
		end

		buffer.writeu8(out, offset, health)
		offset += 1
	end

	if bit32.btest(mask, 2) then
		local stamina = value.stamina

		if type(stamina) ~= "number" or bit32.band(stamina, 255) ~= stamina or stamina > 100 then
			refuseReliable("vitals.stamina: expected u8(0..100)")
		end

		buffer.writeu8(out, offset, stamina)
		offset += 1
	end

	if bit32.btest(mask, 4) then
		local title = value.title

		if type(title) ~= "string" then
			refuseReliable("vitals.title: expected string")
		end

		if #title > 16 then
			refuseReliable("vitals.title: length out of range")
		end

		buffer.writeu8(out, offset, #title)
		offset += 1
		buffer.writestring(out, offset, title)
		offset += #title
	end

	if bit32.btest(mask, 8) then
		local flags_2: number = 0
		local held = value.held
		flags_2 += held ~= nil and 1 or 0
		buffer.writeu8(out, offset, flags_2)
		offset += 1

		if held ~= nil then
			if type(held) ~= "number" or bit32.band(held, 65535) ~= held then
				refuseReliable("vitals.held: expected u16")
			end

			buffer.writeu16(out, offset, held)
			offset += 2
		end
	end

	if bit32.btest(mask, 16) then
		local flags_3: number = 0
		local gear = value.gear

		if type(gear) ~= "table" then
			refuseReliable("vitals.gear: expected table")
		end

		local shield = gear.shield

		if type(shield) ~= "boolean" then
			refuseReliable("vitals.gear.shield: expected boolean")
		end

		flags_3 += shield and 1 or 0
		local boots = gear.boots

		if type(boots) ~= "boolean" then
			refuseReliable("vitals.gear.boots: expected boolean")
		end

		flags_3 += boots and 2 or 0
		buffer.writeu8(out, offset, flags_3)
		offset += 1
	end

	trimReliable(offset)
end

local function writezone(mask: number, value: { id: number, safe: boolean })
	local offset: number, out: buffer = beginReliable(5)
	buffer.writeu8(out, offset, 2)

	if type(value) ~= "table" then
		refuseReliable("zone: expected table")
	end

	local flags: number = 0
	flags += bit32.band(mask, 1)
	flags += bit32.band(mask, 2)
	buffer.writeu8(out, offset + 1, flags)
	offset += 2

	if bit32.btest(mask, 1) then
		local id = value.id

		if type(id) ~= "number" or bit32.band(id, 65535) ~= id then
			refuseReliable("zone.id: expected u16")
		end

		buffer.writeu16(out, offset, id)
		offset += 2
	end

	if bit32.btest(mask, 2) then
		local flags_2: number = 0
		local safe = value.safe

		if type(safe) ~= "boolean" then
			refuseReliable("zone.safe: expected boolean")
		end

		flags_2 += safe and 1 or 0
		buffer.writeu8(out, offset, flags_2)
		offset += 1
	end

	trimReliable(offset)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x917D2C44,
	scope = "Deltas",
	side = "server",
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

	messages = {},

	outgoing = {
		[1] = { name = "vitals", kind = "event", reliable = true, fields = { "health", "stamina", "title", "held", "gear" }, minBytes = 2, maxBytes = 25 },
		[2] = { name = "zone", kind = "event", reliable = true, fields = { "id", "safe" }, minBytes = 2, maxBytes = 5 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
refuseReliable = runtime.reliable.refuse

local Network = {
	vitals = table.freeze({
		fire = function (player: Player | Bot, value: Vitals)
			assert(player ~= nil, "Volt: a message for one player was sent to none")
			runtime:delta(1, player, nil, nil, writevitals, value)
		end,

		fireAll = function (value: Vitals)
			runtime:delta(1, nil, nil, nil, writevitals, value)
		end,

		fireList = function (players: { Player | Bot }, value: Vitals)
			runtime:delta(1, nil, players, nil, writevitals, value)
		end,

		fireExcept = function (player: Player | Bot, value: Vitals)
			runtime:delta(1, nil, nil, player, writevitals, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: Vitals)
			runtime:delta(1, nil, players, nil, writevitals, value)
		end,
	}) :: ServerEvent<(Vitals)>,

	zone = table.freeze({
		fire = function (player: Player | Bot, value: { id: number, safe: boolean })
			assert(player ~= nil, "Volt: a message for one player was sent to none")
			runtime:delta(2, player, nil, nil, writezone, value)
		end,

		fireAll = function (value: { id: number, safe: boolean })
			runtime:delta(2, nil, nil, nil, writezone, value)
		end,

		fireList = function (players: { Player | Bot }, value: { id: number, safe: boolean })
			runtime:delta(2, nil, players, nil, writezone, value)
		end,

		fireExcept = function (player: Player | Bot, value: { id: number, safe: boolean })
			runtime:delta(2, nil, nil, player, writezone, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: { id: number, safe: boolean })
			runtime:delta(2, nil, players, nil, writezone, value)
		end,
	}) :: ServerEvent<({ id: number, safe: boolean })>,

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

	onJoin = function (callback: (player: Player | Bot) -> ()): () -> ()
		return runtime:onJoin(callback)
	end,

	onLeave = function (callback: (player: Player | Bot) -> ()): () -> ()
		return runtime:onLeave(callback)
	end,

	onHandshake = function (callback: (player: Player | Bot) -> ()): () -> ()
		return runtime:onHandshake(callback)
	end,

	traffic = function (player: Player | Bot): (number, number)
		return runtime:traffic(player)
	end,

	budget = function (bytesPerSecond: number?)
		runtime:budget(bytesPerSecond)
	end,

	isBot = runtime.isBot,
}

Network.events = table.freeze({
	["vitals"] = Network.vitals,
	["zone"] = Network.zone,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
