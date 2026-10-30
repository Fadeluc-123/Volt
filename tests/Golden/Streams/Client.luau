--[[
    The client module Volt 0.1.0 generated from Streams.volt: a writer per
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
local beginReliable: (number) -> (number, buffer)
local refuseReliable: (string) -> never
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

local function readNotice(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Notice: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(2, player, cursor, sideCursor, value)
end

local function readTick(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Tick: truncated")
	end

	local value: number = buffer.readu16(packet, cursor)
	cursor += 2

	return runtime:deliver(3, player, cursor, sideCursor, value)
end

local function writeAsk(slot: number, value: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseReliable("Ask: expected u8")
	end

	buffer.writeu8(out, offset + 3, value)
end

local function readAsk(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Ask: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("Ask: truncated")
		end

		local value: number = buffer.readu8(packet, cursor)
		cursor += 1

		return runtime:reply(4, player, slot, cursor, sideCursor, value)
	end

	return runtime:refused(4, player, slot, status, packet, cursor, sideCursor, length)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x0586E76B,
	scope = "Streams",
	side = "client",
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
		[1] = { name = "Chat", kind = "event", mode = "ManySync", queue = 64, read = readChat },
		[2] = { name = "Notice", kind = "event", mode = "ManySync", queue = 64, read = readNotice },
		[3] = { name = "Tick", kind = "event", mode = "Polling", queue = 64, read = readTick },
		[4] = { name = "Ask", kind = "reply", timeout = 10, read = readAsk },
	},

	outgoing = {
		[1] = { name = "Chat", kind = "event", reliable = true, stream = 1, minBytes = 2, maxBytes = 202 },
		[2] = { name = "Ask", kind = "call", reliable = true, minBytes = 4, maxBytes = 4 },
	},
})

beginReliable = runtime.reliable.begin
refuseReliable = runtime.reliable.refuse
beginReliable_Bulk = runtime.streams[1].begin
trimReliable_Bulk = runtime.streams[1].trim
refuseReliable_Bulk = runtime.streams[1].refuse

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Chat = table.freeze({
		fire = function (value: string)
			if before[1] == nil or before[1](nil, value) then
				writeChat(value)
			end
		end,

		on = function (listener: (value: string) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, string)
			return runtime:iter(1)
		end,
	}) :: ClientEvent<(string)> & ClientListener<(string)>,

	Notice = table.freeze({
		on = function (listener: (value: number) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, number)
			return runtime:iter(2)
		end,
	}) :: ClientListener<(number)>,

	Tick = table.freeze({
		iter = function (): () -> (number, number)
			return runtime:iter(3)
		end,
	}) :: ClientPolling<(number)>,

	Ask = table.freeze({
		invoke = function (value: number): (boolean, number)
			return runtime:invoke(4, writeAsk, value)
		end,
	}) :: ClientFunction<(number), (number)>,

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

	serverTime = function (): number
		return runtime:serverTime()
	end,
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
