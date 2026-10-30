--[[
    The client module Volt 0.1.0 generated from Tooling.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Kind = "Info" | "Warn"
export type Entry = { name: string, kind: Kind }

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
local trimReliable: (number) -> ()
local refuseReliable: (string) -> never
local beginUnreliable: (number) -> (number, buffer)
local allocateUnreliable: (number) -> (number, buffer)
local slotUnreliable: (any) -> ()
local refuseUnreliable: (string) -> never
local markUnreliable: () -> ()

local ENTRY_KIND: { "Info" | "Warn" } = { "Info", "Warn" }

local function writeEntry(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(2)
	local flags: number = 0

	if type(value) ~= "table" then
		refuse("Entry: expected table")
	end

	local name = value.name

	if type(name) ~= "string" then
		refuse("Entry.name: expected string")
	end

	if #name < 1 or #name > 16 then
		refuse("Entry.name: length out of range")
	end

	buffer.writeu8(out, offset + 1, #name - 1)
	local kind = value.kind
	local kindIndex: number = table.find(ENTRY_KIND, kind) or 0

	if kindIndex == 0 then
		refuse("Entry.kind: expected enum { Info, Warn }")
	end

	flags += kindIndex - 1
	buffer.writeu8(out, offset, flags)
	local nameOffset: number, nameOut: buffer = allocate(#name)
	buffer.writestring(nameOut, nameOffset, name)
end

local function readEntry(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Entry)
	if cursor + 2 > length then
		error("Entry: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local nameLength: number = 1 + buffer.readu8(packet, cursor + 1)

	if nameLength > 16 then
		error("Entry.name: length out of range")
	end

	local kind: ("Info" | "Warn")? = ENTRY_KIND[bit32.extract(flags, 0, 1) + 1]

	if not kind then
		error("Entry.kind: out of range")
	end

	cursor += 2

	if cursor + nameLength > length then
		error("Entry.name: truncated")
	end

	local name: string = buffer.readstring(packet, cursor, nameLength)
	cursor += nameLength
	local value = { name = name, kind = kind }

	return cursor, sideCursor, value
end

local function writeSync(value: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 1)

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseReliable("Sync: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function readSync(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	debug.profilebegin("Volt Tooling Sync")

	if cursor + 1 > length then
		error("Sync: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	cursor, sideCursor = runtime:deliver(1, player, cursor, sideCursor, value)
	debug.profileend()
	return cursor, sideCursor
end

local function writePost(value: Entry)
	local offset: number, out: buffer = beginUnreliable(1)
	buffer.writeu8(out, offset, 2)
	writeEntry(allocateUnreliable, slotUnreliable, refuseUnreliable, value)
	markUnreliable()
end

local function readSeen(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	debug.profilebegin("Volt Tooling Seen")
	local who: Instance? = side[sideCursor]
	sideCursor += 1

	if typeof(who) ~= "Instance" then
		error("Seen.who: expected Instance")
	end

	local entry: Entry
	cursor, sideCursor, entry = readEntry(packet, cursor, side, sideCursor, length)

	cursor, sideCursor = runtime:deliver(2, player, cursor, sideCursor, who, entry)
	debug.profileend()
	return cursor, sideCursor
end

local function writeLookup(slot: number, value: string)
	local offset: number, out: buffer = beginReliable(20)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)

	if type(value) ~= "string" then
		refuseReliable("Lookup: expected string")
	end

	if #value < 1 or #value > 16 then
		refuseReliable("Lookup: length out of range")
	end

	buffer.writeu8(out, offset + 3, #value - 1)
	offset += 4
	buffer.writestring(out, offset, value)
	offset += #value
	trimReliable(offset)
end

local function readLookup(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	debug.profilebegin("Volt Tooling Lookup")

	if cursor + 3 > length then
		error("Lookup: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("Lookup: truncated")
		end

		local flags: number = buffer.readu8(packet, cursor)
		local value: Entry?
		cursor += 1

		if bit32.btest(flags, 1) then
			local value_2: Entry
			cursor, sideCursor, value_2 = readEntry(packet, cursor, side, sideCursor, length)
			value = value_2
		end

		cursor, sideCursor = runtime:reply(3, player, slot, cursor, sideCursor, value)
		debug.profileend()
		return cursor, sideCursor
	end

	cursor, sideCursor = runtime:refused(3, player, slot, status, packet, cursor, sideCursor, length)
	debug.profileend()
	return cursor, sideCursor
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xA5794D8C,
	scope = "Tooling",
	side = "client",
	idBytes = 1,
	profiler = debug,
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
		[1] = { name = "Sync", kind = "event", mode = "SingleSync", queue = 64, read = readSync },
		[2] = { name = "Seen", kind = "event", mode = "SingleAsync", queue = 64, read = readSeen },
		[3] = { name = "Lookup", kind = "reply", timeout = 10, read = readLookup },
	},

	outgoing = {
		[1] = { name = "Sync", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[2] = { name = "Post", kind = "event", reliable = false, minBytes = 4, maxBytes = 19 },
		[3] = { name = "Lookup", kind = "call", reliable = true, minBytes = 5, maxBytes = 20 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
refuseReliable = runtime.reliable.refuse
beginUnreliable = runtime.unreliable.begin
allocateUnreliable = runtime.unreliable.allocate
slotUnreliable = runtime.unreliable.slot
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Sync = table.freeze({
		fire = function (value: number)
			if before[1] == nil or before[1](nil, value) then
				writeSync(value)
			end
		end,

		on = function (listener: (value: number) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, number)
			return runtime:iter(1)
		end,
	}) :: ClientEvent<(number)> & ClientListener<(number)>,

	Post = table.freeze({
		fire = function (value: Entry)
			if before[2] == nil or before[2](nil, value) then
				writePost(value)
			end
		end,
	}) :: ClientEvent<(Entry)>,

	Seen = table.freeze({
		on = function (listener: (who: Instance, entry: Entry) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, Instance, Entry)
			return runtime:iter(2)
		end,
	}) :: ClientListener<(Instance, Entry)>,

	Lookup = table.freeze({
		invoke = function (value: string): (boolean, Entry?)
			return runtime:invoke(3, writeLookup, value)
		end,
	}) :: ClientFunction<(string), (Entry?)>,

	version = "0.1.0",

	hooks = table.freeze({
		beforeSend = runtime.beforeSend,
		afterReceive = runtime.afterReceive,
	}),

	rate = runtime.rate,

	flush = function ()
		debug.profilebegin("Volt Tooling flush")
		runtime:flush()
		debug.profileend()
	end,

	onFailure = function (handler: Volt.Failure): Volt.Failure
		return runtime:onFailure(handler)
	end,

	stats = function (player: (Player | Bot)?): Volt.Stats
		return runtime:stats(player)
	end,
}

Network.events = table.freeze({
	["Sync"] = Network.Sync,
	["Post"] = Network.Post,
	["Seen"] = Network.Seen,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Lookup"] = Network.Lookup,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
