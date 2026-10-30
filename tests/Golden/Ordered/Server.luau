--[[
    The server module Volt 0.1.0 generated from Ordered.volt: a writer per
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

local function writeSpray(value: number)
	local offset: number, out: buffer = beginUnreliable(2)
	buffer.writeu8(out, offset, 2)

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseUnreliable("Spray: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
	markUnreliable()
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xAF570C31,
	scope = "Ordered",
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

	messages = {
		[1] = { name = "Aim", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readAim },
	},

	outgoing = {
		[1] = { name = "Aim", kind = "event", reliable = false, sequence = 1, minBytes = 7, maxBytes = 7 },
		[2] = { name = "Spray", kind = "event", reliable = false, minBytes = 2, maxBytes = 2 },
	},
})

beginUnreliable = runtime.unreliable.begin
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark
orderUnreliable = runtime.unreliable.order

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Aim = table.freeze({
		fire = function (player: Player | Bot, yaw: number, pitch: number)
			if (before[1] == nil or before[1](player, yaw, pitch)) and runtime:target(player) then
				writeAim(yaw, pitch)
			end
		end,

		fireAll = function (yaw: number, pitch: number)
			runtime:broadcast(1, nil, nil, writeAim, yaw, pitch)
		end,

		fireList = function (players: { Player | Bot }, yaw: number, pitch: number)
			runtime:broadcast(1, players, nil, writeAim, yaw, pitch)
		end,

		fireExcept = function (player: Player | Bot, yaw: number, pitch: number)
			runtime:broadcast(1, nil, player, writeAim, yaw, pitch)
		end,

		fireSet = function (players: { [Player | Bot]: true }, yaw: number, pitch: number)
			runtime:broadcast(1, players, nil, writeAim, yaw, pitch)
		end,

		on = function (listener: (player: Player | Bot, yaw: number, pitch: number) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number, number)
			return runtime:iter(1)
		end,
	}) :: ServerEvent<(number, number)> & ServerListener<(number, number)>,

	Spray = table.freeze({
		fire = function (player: Player | Bot, value: number)
			if (before[2] == nil or before[2](player, value)) and runtime:target(player) then
				writeSpray(value)
			end
		end,

		fireAll = function (value: number)
			runtime:broadcast(2, nil, nil, writeSpray, value)
		end,

		fireList = function (players: { Player | Bot }, value: number)
			runtime:broadcast(2, players, nil, writeSpray, value)
		end,

		fireExcept = function (player: Player | Bot, value: number)
			runtime:broadcast(2, nil, player, writeSpray, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: number)
			runtime:broadcast(2, players, nil, writeSpray, value)
		end,
	}) :: ServerEvent<(number)>,

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
	["Aim"] = Network.Aim,
	["Spray"] = Network.Spray,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
