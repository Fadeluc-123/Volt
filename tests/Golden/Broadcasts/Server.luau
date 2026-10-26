--[[
    The server module Volt 0.1.0 generated from Broadcasts.volt: a writer per
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

type Bot = Volt.Bot

export type ServerEvent<A...> = {
	fire: (player: Player | Bot, A...) -> (),
	fireAll: (A...) -> (),
	fireList: (players: { Player | Bot }, A...) -> (),
	fireExcept: (player: Player | Bot, A...) -> (),
	fireSet: (players: { [Player | Bot]: true }, A...) -> (),
}

export type ServerListener<A...> = {
	on: (listener: (player: Player | Bot, A...) -> ()) -> () -> (),
	iter: () -> () -> (number, Player | Bot, A...),
}

export type ServerPolling<A...> = { iter: () -> () -> (number, Player | Bot, A...) }

export type ServerFunction<A..., R...> = {
	on: (handler: (player: Player | Bot, A...) -> R...) -> () -> (),
}

export type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local refuseReliable: (string) -> never
local beginUnreliable: (number) -> (number, buffer)
local refuseUnreliable: (string) -> never
local markUnreliable: () -> ()

local function writeDamage(value: Hit)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 1)

	if type(value) ~= "table" then
		refuseReliable("Damage: expected table")
	end

	local target = value.target

	if type(target) ~= "number" or bit32.band(target, 65535) ~= target then
		refuseReliable("Damage.target: expected u16")
	end

	buffer.writeu16(out, offset + 1, target)
	local amount = value.amount

	if type(amount) ~= "number" or bit32.band(amount, 255) ~= amount then
		refuseReliable("Damage.amount: expected u8")
	end

	buffer.writeu8(out, offset + 3, amount)
end

local function writeSpray(x: number, y: number)
	local offset: number, out: buffer = beginUnreliable(3)
	buffer.writeu8(out, offset, 2)

	if type(x) ~= "number" or bit32.band(x, 255) ~= x then
		refuseUnreliable("Spray.x: expected u8")
	end

	buffer.writeu8(out, offset + 1, x)

	if type(y) ~= "number" or bit32.band(y, 255) ~= y then
		refuseUnreliable("Spray.y: expected u8")
	end

	buffer.writeu8(out, offset + 2, y)
	markUnreliable()
end

local function writeMatch_Start()
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 3)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xD9DF1E2D,
	scope = "Broadcasts",
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
		[1] = { name = "Damage", kind = "event", reliable = true, minBytes = 4, maxBytes = 4 },
		[2] = { name = "Spray", kind = "event", reliable = false, minBytes = 3, maxBytes = 3 },
		[3] = { name = "Match.Start", kind = "event", reliable = true, minBytes = 1, maxBytes = 1 },
	},
})

beginReliable = runtime.reliable.begin
refuseReliable = runtime.reliable.refuse
beginUnreliable = runtime.unreliable.begin
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Damage = table.freeze({
		fire = function (player: Player | Bot, value: Hit)
			if (before[1] == nil or before[1](player, value)) and runtime:target(player) then
				writeDamage(value)
			end
		end,

		fireAll = function (value: Hit)
			runtime:broadcast(1, nil, nil, writeDamage, value)
		end,

		fireList = function (players: { Player | Bot }, value: Hit)
			runtime:broadcast(1, players, nil, writeDamage, value)
		end,

		fireExcept = function (player: Player | Bot, value: Hit)
			runtime:broadcast(1, nil, player, writeDamage, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: Hit)
			runtime:broadcast(1, players, nil, writeDamage, value)
		end,
	}) :: ServerEvent<(Hit)>,

	Spray = table.freeze({
		fire = function (player: Player | Bot, x: number, y: number)
			if (before[2] == nil or before[2](player, x, y)) and runtime:target(player) then
				writeSpray(x, y)
			end
		end,

		fireAll = function (x: number, y: number)
			runtime:broadcast(2, nil, nil, writeSpray, x, y)
		end,

		fireList = function (players: { Player | Bot }, x: number, y: number)
			runtime:broadcast(2, players, nil, writeSpray, x, y)
		end,

		fireExcept = function (player: Player | Bot, x: number, y: number)
			runtime:broadcast(2, nil, player, writeSpray, x, y)
		end,

		fireSet = function (players: { [Player | Bot]: true }, x: number, y: number)
			runtime:broadcast(2, players, nil, writeSpray, x, y)
		end,
	}) :: ServerEvent<(number, number)>,

	Match = table.freeze({
		Start = table.freeze({
			fire = function (player: Player | Bot)
				if (before[3] == nil or before[3](player)) and runtime:target(player) then
					writeMatch_Start()
				end
			end,

			fireAll = function ()
				runtime:broadcast(3, nil, nil, writeMatch_Start)
			end,

			fireList = function (players: { Player | Bot })
				runtime:broadcast(3, players, nil, writeMatch_Start)
			end,

			fireExcept = function (player: Player | Bot)
				runtime:broadcast(3, nil, player, writeMatch_Start)
			end,

			fireSet = function (players: { [Player | Bot]: true })
				runtime:broadcast(3, players, nil, writeMatch_Start)
			end,
		}) :: ServerEvent<()>,
	}),

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

	isBot = runtime.isBot,
}

Network.events = table.freeze({
	["Damage"] = Network.Damage,
	["Spray"] = Network.Spray,
	["Match.Start"] = Network.Match.Start,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
