--[[
    The server module Volt 0.1.0 generated from Tooling.volt: a writer per
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
local slotReliable: (any) -> ()
local refuseReliable: (string) -> never

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

local function readPost(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	debug.profilebegin("Volt Tooling Post")
	local value: Entry
	cursor, sideCursor, value = readEntry(packet, cursor, side, sideCursor, length)

	cursor, sideCursor = runtime:deliver(2, player, cursor, sideCursor, value)
	debug.profileend()
	return cursor, sideCursor
end

local function writeSeen(who: Instance, entry: Entry)
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 2)

	if typeof(who) ~= "Instance" then
		refuseReliable("Seen.who: expected Instance")
	end

	slotReliable(who)
	writeEntry(allocateReliable, slotReliable, refuseReliable, entry)
end

local function readLookup(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	debug.profilebegin("Volt Tooling Lookup")

	if cursor + 3 > length then
		error("Lookup: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local valueLength: number = 1 + buffer.readu8(packet, cursor + 2)

	if valueLength > 16 then
		error("Lookup: length out of range")
	end

	cursor += 3

	if cursor + valueLength > length then
		error("Lookup: truncated")
	end

	local value: string = buffer.readstring(packet, cursor, valueLength)
	cursor += valueLength

	cursor, sideCursor = runtime:call(3, player, slot, cursor, sideCursor, value)
	debug.profileend()
	return cursor, sideCursor
end

local function writeLookup(slot: number, status: number, value: Entry?)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)

	if status == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)
		local flags: number = 0
		flags += value ~= nil and 1 or 0
		buffer.writeu8(out_2, offset_2, flags)

		if value ~= nil then
			writeEntry(allocateReliable, slotReliable, refuseReliable, value)
		end
	end
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xA5794D8C,
	scope = "Tooling",
	side = "server",
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
		[1] = { name = "Sync", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readSync },
		[2] = { name = "Post", kind = "event", mode = "ManySync", queue = 64, rate = 120, read = readPost },
		[3] = { name = "Lookup", kind = "call", rate = 60, read = readLookup, reply = writeLookup },
	},

	outgoing = {
		[1] = { name = "Sync", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[2] = { name = "Seen", kind = "event", reliable = true, minBytes = 4, maxBytes = 19 },
		[3] = { name = "Lookup", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
	},
})

beginReliable = runtime.reliable.begin
allocateReliable = runtime.reliable.allocate
slotReliable = runtime.reliable.slot
refuseReliable = runtime.reliable.refuse

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Sync = table.freeze({
		fire = function (player: Player | Bot, value: number)
			if (before[1] == nil or before[1](player, value)) and runtime:target(player) then
				writeSync(value)
			end
		end,

		fireAll = function (value: number)
			runtime:broadcast(1, nil, nil, writeSync, value)
		end,

		fireList = function (players: { Player | Bot }, value: number)
			runtime:broadcast(1, players, nil, writeSync, value)
		end,

		fireExcept = function (player: Player | Bot, value: number)
			runtime:broadcast(1, nil, player, writeSync, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: number)
			runtime:broadcast(1, players, nil, writeSync, value)
		end,

		on = function (listener: (player: Player | Bot, value: number) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number)
			return runtime:iter(1)
		end,
	}) :: ServerEvent<(number)> & ServerListener<(number)>,

	Post = table.freeze({
		on = function (listener: (player: Player | Bot, value: Entry) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, Player | Bot, Entry)
			return runtime:iter(2)
		end,
	}) :: ServerListener<(Entry)>,

	Seen = table.freeze({
		fire = function (player: Player | Bot, who: Instance, entry: Entry)
			if (before[2] == nil or before[2](player, who, entry)) and runtime:target(player) then
				writeSeen(who, entry)
			end
		end,

		fireAll = function (who: Instance, entry: Entry)
			runtime:broadcast(2, nil, nil, writeSeen, who, entry)
		end,

		fireList = function (players: { Player | Bot }, who: Instance, entry: Entry)
			runtime:broadcast(2, players, nil, writeSeen, who, entry)
		end,

		fireExcept = function (player: Player | Bot, who: Instance, entry: Entry)
			runtime:broadcast(2, nil, player, writeSeen, who, entry)
		end,

		fireSet = function (players: { [Player | Bot]: true }, who: Instance, entry: Entry)
			runtime:broadcast(2, players, nil, writeSeen, who, entry)
		end,
	}) :: ServerEvent<(Instance, Entry)>,

	Lookup = table.freeze({
		on = function (handler: (player: Player | Bot, value: string) -> (Entry?)): () -> ()
			return runtime:handle(3, handler)
		end,
	}) :: ServerFunction<(string), (Entry?)>,

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
	["Sync"] = Network.Sync,
	["Post"] = Network.Post,
	["Seen"] = Network.Seen,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Lookup"] = Network.Lookup,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
