--[[
    The client module Volt 0.1.0 generated from Console.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)
local Promise: any = require(ReplicatedStorage.Packages.Promise)

export type Decree_Kind = "Info" | "Warn" | "Error"
type Decree_Line = string

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
local beginReliable: (number) -> (number, buffer)
local trimReliable: (number) -> ()
local refuseReliable: (string) -> never

local DECREE_KIND: { "Info" | "Warn" | "Error" } = { "Info", "Warn", "Error" }

local function readDecree_Line(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Decree_Line)
	if cursor + 2 > length then
		error("Decree.Line: truncated")
	end

	local valueLength: number = buffer.readu16(packet, cursor)

	if valueLength > 16384 then
		error("Decree.Line: length out of range")
	end

	cursor += 2

	if cursor + valueLength > length then
		error("Decree.Line: truncated")
	end

	local value: string = buffer.readstring(packet, cursor, valueLength)
	cursor += valueLength

	if utf8.len(value) == nil then
		error("Decree.Line: invalid UTF-8")
	end

	return cursor, sideCursor, value
end

local function readDecree_Kind(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Decree_Kind)
	if cursor + 1 > length then
		error("Decree.Kind: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local value: ("Info" | "Warn" | "Error")? = DECREE_KIND[bit32.extract(flags, 0, 2) + 1]

	if not value then
		error("Decree.Kind: out of range")
	end

	cursor += 1

	return cursor, sideCursor, value
end

local function readDecree_line(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	local text: Decree_Line
	local kind: Decree_Kind
	cursor, sideCursor, text = readDecree_Line(packet, cursor, side, sideCursor, length)
	cursor, sideCursor, kind = readDecree_Kind(packet, cursor, side, sideCursor, length)

	return runtime:deliver(1, player, cursor, sideCursor, text, kind)
end

local function writeDecree_run(slot: number, text: string)
	local offset: number, out: buffer = beginReliable(4101)
	buffer.writeu8(out, offset, 1)
	buffer.writeu16(out, offset + 1, slot)

	if type(text) ~= "string" then
		refuseReliable("Decree.run.text: expected string")
	end

	if #text < 1 or #text > 4096 then
		refuseReliable("Decree.run.text: length out of range")
	end

	buffer.writeu16(out, offset + 3, #text - 1)

	if utf8.len(text) == nil then
		refuseReliable("Decree.run.text: invalid UTF-8")
	end

	offset += 5
	buffer.writestring(out, offset, text)
	offset += #text
	trimReliable(offset)
end

local function readDecree_run(_: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Decree.run: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		local text: Decree_Line
		local kind: Decree_Kind
		cursor, sideCursor, text = readDecree_Line(packet, cursor, side, sideCursor, length)
		cursor, sideCursor, kind = readDecree_Kind(packet, cursor, side, sideCursor, length)

		return runtime:reply(2, slot, cursor, sideCursor, text, kind)
	end

	return runtime:refused(2, slot, packet, cursor, sideCursor, length)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x72A12928,
	scope = "Console",
	side = "client",
	idBytes = 1,
	promise = Promise,
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
		[1] = { name = "Decree.line", kind = "event", mode = "SingleSync", queue = 64, read = readDecree_line },
		[2] = { name = "Decree.run", kind = "reply", timeout = 10, promise = Promise, read = readDecree_run },
	},

	outgoing = {
		[1] = { name = "Decree.run", kind = "call", reliable = true, minBytes = 6, maxBytes = 4101 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
refuseReliable = runtime.reliable.refuse

local Network = {
	Decree = table.freeze({
		line = table.freeze({
			on = function (listener: (text: Decree_Line, kind: Decree_Kind) -> ()): () -> ()
				return runtime:on(1, listener)
			end,

			iter = function (): () -> (number, Decree_Line, Decree_Kind)
				return runtime:iter(1)
			end,
		}) :: ClientListener<(Decree_Line, Decree_Kind)>,

		run = table.freeze({
			invoke = function (text: string)
				return runtime:invoke(2, writeDecree_run, text)
			end,
		}) :: ClientPromise<(string)>,
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
}

Network.events = table.freeze({
	["Decree.line"] = Network.Decree.line,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Decree.run"] = Network.Decree.run,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
