--[[
    The server module Volt 0.1.0 generated from Events.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

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

local function readInput(player: Player?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Input: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local dir: number = buffer.readu8(packet, cursor + 1)

	if dir > 8 then
		error("Input.dir: out of range")
	end

	cursor += 2

	return runtime:deliver(1, player, cursor, sideCursor, dir, bit32.btest(flags, 1))
end

local function readChat(player: Player?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Chat: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 64 then
		error("Chat: length out of range")
	end

	cursor += 1

	if cursor + valueLength > length then
		error("Chat: truncated")
	end

	local value: string = buffer.readstring(packet, cursor, valueLength)
	cursor += valueLength

	return runtime:deliver(2, player, cursor, sideCursor, value)
end

local function readReady(player: Player?, _: buffer, cursor: number, _: { any }, sideCursor: number, _: number): (number, number)
	return runtime:deliver(3, player, cursor, sideCursor)
end

local function readGrab(player: Player?, _: buffer, cursor: number, side: { any }, sideCursor: number, _: number): (number, number)
	local value: Instance? = side[sideCursor]
	sideCursor += 1

	if typeof(value) ~= "Instance" then
		error("Grab: expected Instance")
	end

	return runtime:deliver(4, player, cursor, sideCursor, value)
end

local function readPing(player: Player?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 4 > length then
		error("Ping: truncated")
	end

	local value: number = buffer.readu32(packet, cursor)
	cursor += 4

	return runtime:deliver(5, player, cursor, sideCursor, value)
end

local function writeSync(value: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 1)

	if typeof(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
		refuseReliable("Sync: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function readSync(player: Player?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Sync: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(6, player, cursor, sideCursor, value)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x88701285,
	scope = "Events",
	side = "server",
	idBytes = 1,
	options = {
		flush = 1,
		manualReplication = false,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
	},

	messages = {
		[1] = { name = "Input", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readInput },
		[2] = { name = "Chat", kind = "event", mode = "SingleAsync", queue = 64, rate = 120, read = readChat },
		[3] = { name = "Ready", kind = "event", mode = "ManySync", queue = 64, rate = 120, read = readReady },
		[4] = { name = "Grab", kind = "event", mode = "ManyAsync", queue = 64, rate = 120, read = readGrab },
		[5] = { name = "Ping", kind = "event", mode = "Polling", queue = 64, read = readPing },
		[6] = { name = "Sync", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readSync },
	},

	outgoing = {
		[1] = { name = "Sync", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
	},
})

beginReliable = runtime.reliable.begin
refuseReliable = runtime.reliable.refuse

local before: { [number]: Volt.Hook } = runtime.before

local net = {
	Input = table.freeze({
		on = function (listener: (player: Player, dir: number, jump: boolean) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player, number, boolean)
			return runtime:iter(1)
		end,
	}),

	Chat = table.freeze({
		on = function (listener: (player: Player, value: string) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, Player, string)
			return runtime:iter(2)
		end,
	}),

	Ready = table.freeze({
		on = function (listener: (player: Player) -> ()): () -> ()
			return runtime:on(3, listener)
		end,

		iter = function (): () -> (number, Player)
			return runtime:iter(3)
		end,
	}),

	Grab = table.freeze({
		on = function (listener: (player: Player, value: Instance) -> ()): () -> ()
			return runtime:on(4, listener)
		end,

		iter = function (): () -> (number, Player, Instance)
			return runtime:iter(4)
		end,
	}),

	Ping = table.freeze({
		iter = function (): () -> (number, Player, number)
			return runtime:iter(5)
		end,
	}),

	Sync = table.freeze({
		fire = function (player: Player, value: number)
			if (before[1] == nil or before[1](player, value)) and runtime:target(player) then
				writeSync(value)
			end
		end,

		fireAll = function (value: number)
			runtime:broadcast(1, nil, nil, writeSync, value)
		end,

		fireList = function (players: { Player }, value: number)
			runtime:broadcast(1, players, nil, writeSync, value)
		end,

		fireExcept = function (player: Player, value: number)
			runtime:broadcast(1, nil, player, writeSync, value)
		end,

		fireSet = function (players: { [Player]: true }, value: number)
			runtime:broadcast(1, players, nil, writeSync, value)
		end,

		on = function (listener: (player: Player, value: number) -> ()): () -> ()
			return runtime:on(6, listener)
		end,

		iter = function (): () -> (number, Player, number)
			return runtime:iter(6)
		end,
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
	["Input"] = net.Input,
	["Chat"] = net.Chat,
	["Ready"] = net.Ready,
	["Grab"] = net.Grab,
	["Ping"] = net.Ping,
	["Sync"] = net.Sync,
})

net.functions = table.freeze({})
net.exports = table.freeze({})

return table.freeze(net)
