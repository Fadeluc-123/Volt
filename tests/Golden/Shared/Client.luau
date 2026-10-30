--[[
    The client module Volt 0.1.0 generated from Shared.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Kind = "Info" | "Warn" | "Error"
export type Commands = { { name: string, type: number } }

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
local allocateReliable: (number) -> (number, buffer)
local slotReliable: (any) -> ()
local refuseReliable: (string) -> never

local KIND: { "Info" | "Warn" | "Error" } = { "Info", "Warn", "Error" }

local function readKind(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Kind)
	if cursor + 1 > length then
		error("Kind: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local value: ("Info" | "Warn" | "Error")? = KIND[bit32.extract(flags, 0, 2) + 1]

	if not value then
		error("Kind: out of range")
	end

	cursor += 1

	return cursor, sideCursor, value
end

local function writeCommands(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(1)

	if type(value) ~= "table" then
		refuse("Commands: expected table")
	end

	if #value > 8 then
		refuse("Commands: length out of range")
	end

	buffer.writeu8(out, offset, #value)

	for index = 1, #value do
		local offset_2: number, out_2: buffer = allocate(2)
		local valueEntry = value[index]

		if type(valueEntry) ~= "table" then
			refuse("Commands[]: expected table")
		end

		local name = valueEntry.name

		if type(name) ~= "string" then
			refuse("Commands[].name: expected string")
		end

		if #name < 1 or #name > 16 then
			refuse("Commands[].name: length out of range")
		end

		buffer.writeu8(out_2, offset_2, #name - 1)
		local type_2 = valueEntry.type

		if type(type_2) ~= "number" or bit32.band(type_2, 255) ~= type_2 then
			refuse("Commands[].type: expected u8")
		end

		buffer.writeu8(out_2, offset_2 + 1, type_2)
		local nameOffset: number, nameOut: buffer = allocate(#name)
		buffer.writestring(nameOut, nameOffset, name)
	end
end

local function readLine(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Line: truncated")
	end

	local kind: Kind
	local textLength: number = buffer.readu8(packet, cursor)

	if textLength > 64 then
		error("Line.text: length out of range")
	end

	cursor += 1
	cursor, sideCursor, kind = readKind(packet, cursor, side, sideCursor, length)

	if cursor + textLength > length then
		error("Line.text: truncated")
	end

	local text: string = buffer.readstring(packet, cursor, textLength)
	cursor += textLength

	return runtime:deliver(1, player, cursor, sideCursor, kind, text)
end

local function writeSubmit(value: Commands)
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 1)
	writeCommands(allocateReliable, slotReliable, refuseReliable, value)
end

local function writeRun(slot: number, value: Commands)
	local offset: number, out: buffer = beginReliable(3)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)
	writeCommands(allocateReliable, slotReliable, refuseReliable, value)
end

local function readRun(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Run: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("Run: truncated")
		end

		local kind: Kind
		local textLength: number = buffer.readu8(packet, cursor)

		if textLength > 64 then
			error("Run.text: length out of range")
		end

		cursor += 1
		cursor, sideCursor, kind = readKind(packet, cursor, side, sideCursor, length)

		if cursor + textLength > length then
			error("Run.text: truncated")
		end

		local text: string = buffer.readstring(packet, cursor, textLength)
		cursor += textLength

		return runtime:reply(2, player, slot, cursor, sideCursor, kind, text)
	end

	return runtime:refused(2, player, slot, status, packet, cursor, sideCursor, length)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xCA88011D,
	scope = "Shared",
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
		[1] = { name = "Line", kind = "event", mode = "SingleSync", queue = 64, read = readLine },
		[2] = { name = "Run", kind = "reply", timeout = 10, read = readRun },
	},

	outgoing = {
		[1] = { name = "Submit", kind = "event", reliable = true, minBytes = 2, maxBytes = 146 },
		[2] = { name = "Run", kind = "call", reliable = true, minBytes = 4, maxBytes = 148 },
	},
})

beginReliable = runtime.reliable.begin
allocateReliable = runtime.reliable.allocate
slotReliable = runtime.reliable.slot
refuseReliable = runtime.reliable.refuse

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Line = table.freeze({
		on = function (listener: (kind: Kind, text: string) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Kind, string)
			return runtime:iter(1)
		end,
	}) :: ClientListener<(Kind, string)>,

	Submit = table.freeze({
		fire = function (value: Commands)
			if before[1] == nil or before[1](nil, value) then
				writeSubmit(value)
			end
		end,
	}) :: ClientEvent<(Commands)>,

	Run = table.freeze({
		invoke = function (value: Commands): (boolean, Kind, string)
			return runtime:invoke(2, writeRun, value)
		end,
	}) :: ClientFunction<(Commands), (Kind, string)>,

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
	["Line"] = Network.Line,
	["Submit"] = Network.Submit,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Run"] = Network.Run,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
