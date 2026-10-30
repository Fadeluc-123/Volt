--[[
    The client module Volt 0.1.0 generated from Dictionary.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Item = string
export type Title = string
export type Slot = { title: Title, count: number }

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
local dictionaryEntries: { string }

local function readpicked(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 4 > length then
		error("picked: truncated")
	end

	local itemId: number = buffer.readu16(packet, cursor)
	local item: string = dictionaryEntries[itemId]

	if item == nil then
		error("picked.item: unknown dictionary id")
	end

	if #item < 1 or #item > 32 then
		error("picked.item: length out of range")
	end

	local titleId: number = buffer.readu16(packet, cursor + 2)
	local title: string = dictionaryEntries[titleId]

	if title == nil then
		error("picked.title: unknown dictionary id")
	end

	if #title > 24 then
		error("picked.title: length out of range")
	end

	if utf8.len(title) == nil then
		error("picked.title: invalid UTF-8")
	end

	cursor += 4

	return runtime:deliver(1, player, cursor, sideCursor, item, title)
end

local function readstock(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("stock: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 16 then
		error("stock: length out of range")
	end

	cursor += 1

	if cursor + 5 * valueLength > length then
		error("stock: truncated")
	end

	local value: { [Item]: Slot } = {}

	for _ = 1, valueLength do
		local valueKeyId: number = buffer.readu16(packet, cursor)
		local valueKey: string = dictionaryEntries[valueKeyId]

		if valueKey == nil then
			error("stock[key]: unknown dictionary id")
		end

		if #valueKey < 1 or #valueKey > 32 then
			error("stock[key]: length out of range")
		end

		local titleId: number = buffer.readu16(packet, cursor + 2)
		local title: string = dictionaryEntries[titleId]

		if title == nil then
			error("stock[value].title: unknown dictionary id")
		end

		if #title > 24 then
			error("stock[value].title: length out of range")
		end

		if utf8.len(title) == nil then
			error("stock[value].title: invalid UTF-8")
		end

		local count: number = buffer.readu8(packet, cursor + 4)
		cursor += 5
		local valueValue = { title = title, count = count }

		if value[valueKey] ~= nil then
			error("stock: duplicate key")
		end

		value[valueKey] = valueValue
	end

	return runtime:deliver(2, player, cursor, sideCursor, value)
end

local function writelookup(slot: number, value: number)
	local offset: number, out: buffer = beginReliable(5)
	buffer.writeu8(out, offset, 1)
	buffer.writeu16(out, offset + 1, slot)

	if type(value) ~= "number" or bit32.band(value, 65535) ~= value then
		refuseReliable("lookup: expected u16")
	end

	buffer.writeu16(out, offset + 3, value)
end

local function readlookup(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("lookup: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("lookup: truncated")
		end

		local flags: number = buffer.readu8(packet, cursor)
		local value: Item?
		cursor += 1

		if bit32.btest(flags, 1) then
			if cursor + 2 > length then
				error("lookup: truncated")
			end

			local valueId: number = buffer.readu16(packet, cursor)
			local value_2: string = dictionaryEntries[valueId]

			if value_2 == nil then
				error("lookup: unknown dictionary id")
			end

			if #value_2 < 1 or #value_2 > 32 then
				error("lookup: length out of range")
			end

			cursor += 2
			value = value_2
		end

		return runtime:reply(3, player, slot, cursor, sideCursor, value)
	end

	return runtime:refused(3, player, slot, status, packet, cursor, sideCursor, length)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x8E079DB0,
	scope = "Dictionary",
	side = "client",
	idBytes = 1,
	dictionary = 1,
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
		[1] = { name = "picked", kind = "event", mode = "ManySync", queue = 64, read = readpicked },
		[2] = { name = "stock", kind = "event", mode = "SingleAsync", queue = 64, read = readstock },
		[3] = { name = "lookup", kind = "reply", timeout = 10, read = readlookup },
	},

	outgoing = {
		[1] = { name = "lookup", kind = "call", reliable = true, minBytes = 5, maxBytes = 5 },
	},
})

beginReliable = runtime.reliable.begin
refuseReliable = runtime.reliable.refuse
dictionaryEntries = runtime.dictionary

local Network = {
	picked = table.freeze({
		on = function (listener: (item: Item, title: Title) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Item, Title)
			return runtime:iter(1)
		end,
	}) :: ClientListener<(Item, Title)>,

	stock = table.freeze({
		on = function (listener: (value: { [Item]: Slot }) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, { [Item]: Slot })
			return runtime:iter(2)
		end,
	}) :: ClientListener<({ [Item]: Slot })>,

	lookup = table.freeze({
		invoke = function (value: number): (boolean, Item?)
			return runtime:invoke(3, writelookup, value)
		end,
	}) :: ClientFunction<(number), (Item?)>,

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
	["picked"] = Network.picked,
	["stock"] = Network.stock,
}) :: { [string]: any }

Network.functions = table.freeze({
	["lookup"] = Network.lookup,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
