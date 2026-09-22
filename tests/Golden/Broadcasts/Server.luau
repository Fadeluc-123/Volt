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

export type ServerEvent<A...> = {
	fire: (player: Player, A...) -> (),
	fireAll: (A...) -> (),
	fireList: (players: { Player }, A...) -> (),
	fireExcept: (player: Player, A...) -> (),
	fireSet: (players: { [Player]: true }, A...) -> (),
}

export type ServerListener<A...> = {
	on: (listener: (player: Player, A...) -> ()) -> () -> (),
	iter: () -> () -> (number, Player, A...),
}

export type ServerFunction<A..., R...> = { on: (handler: (player: Player, A...) -> R...) -> () -> () }

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

	if typeof(value) ~= "table" then
		refuseReliable("Damage: expected table")
	end

	if typeof(value.target) ~= "number" or value.target % 1 ~= 0 or value.target < 0 or value.target > 65535 then
		refuseReliable("Damage.target: expected u16")
	end

	buffer.writeu16(out, offset + 1, value.target)

	if typeof(value.amount) ~= "number" or value.amount % 1 ~= 0 or value.amount < 0 or value.amount > 255 then
		refuseReliable("Damage.amount: expected u8")
	end

	buffer.writeu8(out, offset + 3, value.amount)
end

local function writeSpray(x: number, y: number)
	local offset: number, out: buffer = beginUnreliable(3)
	buffer.writeu8(out, offset, 2)

	if typeof(x) ~= "number" or x % 1 ~= 0 or x < 0 or x > 255 then
		refuseUnreliable("Spray.x: expected u8")
	end

	buffer.writeu8(out, offset + 1, x)

	if typeof(y) ~= "number" or y % 1 ~= 0 or y < 0 or y > 255 then
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
	hash = 0x81227874,
	scope = "Broadcasts",
	side = "server",
	idBytes = 1,
	options = {
		flush = 1,
		manualReplication = false,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
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

local net = {
	Damage = table.freeze({
		fire = function (player: Player, value: Hit)
			if (before[1] == nil or before[1](player, value)) and runtime:target(player) then
				writeDamage(value)
			end
		end,

		fireAll = function (value: Hit)
			runtime:broadcast(1, nil, nil, writeDamage, value)
		end,

		fireList = function (players: { Player }, value: Hit)
			runtime:broadcast(1, players, nil, writeDamage, value)
		end,

		fireExcept = function (player: Player, value: Hit)
			runtime:broadcast(1, nil, player, writeDamage, value)
		end,

		fireSet = function (players: { [Player]: true }, value: Hit)
			runtime:broadcast(1, players, nil, writeDamage, value)
		end,
	}),

	Spray = table.freeze({
		fire = function (player: Player, x: number, y: number)
			if (before[2] == nil or before[2](player, x, y)) and runtime:target(player) then
				writeSpray(x, y)
			end
		end,

		fireAll = function (x: number, y: number)
			runtime:broadcast(2, nil, nil, writeSpray, x, y)
		end,

		fireList = function (players: { Player }, x: number, y: number)
			runtime:broadcast(2, players, nil, writeSpray, x, y)
		end,

		fireExcept = function (player: Player, x: number, y: number)
			runtime:broadcast(2, nil, player, writeSpray, x, y)
		end,

		fireSet = function (players: { [Player]: true }, x: number, y: number)
			runtime:broadcast(2, players, nil, writeSpray, x, y)
		end,
	}),

	Match = table.freeze({
		Start = table.freeze({
			fire = function (player: Player)
				if (before[3] == nil or before[3](player)) and runtime:target(player) then
					writeMatch_Start()
				end
			end,

			fireAll = function ()
				runtime:broadcast(3, nil, nil, writeMatch_Start)
			end,

			fireList = function (players: { Player })
				runtime:broadcast(3, players, nil, writeMatch_Start)
			end,

			fireExcept = function (player: Player)
				runtime:broadcast(3, nil, player, writeMatch_Start)
			end,

			fireSet = function (players: { [Player]: true })
				runtime:broadcast(3, players, nil, writeMatch_Start)
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
