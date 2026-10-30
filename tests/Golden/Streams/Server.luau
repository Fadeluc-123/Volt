--[[
    The server module Volt 0.1.0 generated from Streams.volt: a writer per
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
local beginReliable: (number) -> (number, buffer)
local allocateReliable: (number) -> (number, buffer)
local refuseReliable: (string) -> never
local beginUnreliable: (number) -> (number, buffer)
local refuseUnreliable: (string) -> never
local markUnreliable: () -> ()
local beginReliable_Bulk: (number) -> (number, buffer)
local trimReliable_Bulk: (number) -> ()
local refuseReliable_Bulk: (string) -> never

local function writeChat(value: string)
	local offset: number, out: buffer = beginReliable_Bulk(202)
	buffer.writeu8(out, offset, 1)

	if type(value) ~= "string" then
		refuseReliable_Bulk("Chat: expected string")
	end

	if #value > 200 then
		refuseReliable_Bulk("Chat: length out of range")
	end

	buffer.writeu8(out, offset + 1, #value)
	offset += 2
	buffer.writestring(out, offset, value)
	offset += #value
	trimReliable_Bulk(offset)
end

local function readChat(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Chat: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 200 then
		error("Chat: length out of range")
	end

	cursor += 1

	if cursor + valueLength > length then
		error("Chat: truncated")
	end

	local value: string = buffer.readstring(packet, cursor, valueLength)
	cursor += valueLength

	return runtime:deliver(1, player, cursor, sideCursor, value)
end

local function writeNotice(value: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 2)

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseReliable("Notice: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function writeTick(value: number)
	local offset: number, out: buffer = beginUnreliable(3)
	buffer.writeu8(out, offset, 3)

	if type(value) ~= "number" or bit32.band(value, 65535) ~= value then
		refuseUnreliable("Tick: expected u16")
	end

	buffer.writeu16(out, offset + 1, value)
	markUnreliable()
end

local function readAsk(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Ask: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local value: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	return runtime:call(2, player, slot, cursor, sideCursor, value)
end

local function writeAsk(slot: number, status: number, value: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 4)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)

	if status == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)

		if type(value) ~= "number" or bit32.band(value, 255) ~= value then
			refuseReliable("Ask: expected u8")
		end

		buffer.writeu8(out_2, offset_2, value)
	end
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x0586E76B,
	scope = "Streams",
	side = "server",
	idBytes = 1,
	stamp = true,
	streams = { "Bulk" },
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
		[1] = { name = "Chat", kind = "event", mode = "ManySync", queue = 64, rate = 120, read = readChat },
		[2] = { name = "Ask", kind = "call", rate = 60, read = readAsk, reply = writeAsk },
	},

	outgoing = {
		[1] = { name = "Chat", kind = "event", reliable = true, stream = 1, minBytes = 2, maxBytes = 202 },
		[2] = { name = "Notice", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[3] = { name = "Tick", kind = "event", reliable = false, minBytes = 3, maxBytes = 3 },
		[4] = { name = "Ask", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
	},
})

beginReliable = runtime.reliable.begin
allocateReliable = runtime.reliable.allocate
refuseReliable = runtime.reliable.refuse
beginUnreliable = runtime.unreliable.begin
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark
beginReliable_Bulk = runtime.streams[1].begin
trimReliable_Bulk = runtime.streams[1].trim
refuseReliable_Bulk = runtime.streams[1].refuse

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Chat = table.freeze({
		fire = function (player: Player | Bot, value: string)
			if (before[1] == nil or before[1](player, value)) and runtime:target(player, 1) then
				writeChat(value)
			end
		end,

		fireAll = function (value: string)
			runtime:broadcast(1, nil, nil, writeChat, value)
		end,

		fireList = function (players: { Player | Bot }, value: string)
			runtime:broadcast(1, players, nil, writeChat, value)
		end,

		fireExcept = function (player: Player | Bot, value: string)
			runtime:broadcast(1, nil, player, writeChat, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: string)
			runtime:broadcast(1, players, nil, writeChat, value)
		end,

		on = function (listener: (player: Player | Bot, value: string) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player | Bot, string)
			return runtime:iter(1)
		end,
	}) :: ServerEvent<(string)> & ServerListener<(string)>,

	Notice = table.freeze({
		fire = function (player: Player | Bot, value: number)
			if (before[2] == nil or before[2](player, value)) and runtime:target(player) then
				writeNotice(value)
			end
		end,

		fireAll = function (value: number)
			runtime:broadcast(2, nil, nil, writeNotice, value)
		end,

		fireList = function (players: { Player | Bot }, value: number)
			runtime:broadcast(2, players, nil, writeNotice, value)
		end,

		fireExcept = function (player: Player | Bot, value: number)
			runtime:broadcast(2, nil, player, writeNotice, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: number)
			runtime:broadcast(2, players, nil, writeNotice, value)
		end,
	}) :: ServerEvent<(number)>,

	Tick = table.freeze({
		fire = function (player: Player | Bot, value: number)
			if (before[3] == nil or before[3](player, value)) and runtime:target(player) then
				writeTick(value)
			end
		end,

		fireAll = function (value: number)
			runtime:broadcast(3, nil, nil, writeTick, value)
		end,

		fireList = function (players: { Player | Bot }, value: number)
			runtime:broadcast(3, players, nil, writeTick, value)
		end,

		fireExcept = function (player: Player | Bot, value: number)
			runtime:broadcast(3, nil, player, writeTick, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: number)
			runtime:broadcast(3, players, nil, writeTick, value)
		end,
	}) :: ServerEvent<(number)>,

	Ask = table.freeze({
		on = function (handler: (player: Player | Bot, value: number) -> (number)): () -> ()
			return runtime:handle(2, handler)
		end,
	}) :: ServerFunction<(number), (number)>,

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
	["Chat"] = Network.Chat,
	["Notice"] = Network.Notice,
	["Tick"] = Network.Tick,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Ask"] = Network.Ask,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
