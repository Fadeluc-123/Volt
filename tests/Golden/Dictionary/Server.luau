--[[
    The server module Volt 0.1.0 generated from Dictionary.volt: a writer per
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
local trimReliable: (number) -> ()
local refuseReliable: (string) -> never
local internDictionary: (string) -> number

local function writepicked(item: Item, title: Title)
	local offset: number, out: buffer = beginReliable(5)
	buffer.writeu8(out, offset, 1)

	if type(item) ~= "string" then
		refuseReliable("picked.item: expected string")
	end

	if #item < 1 or #item > 32 then
		refuseReliable("picked.item: length out of range")
	end

	local itemId: number = internDictionary(item)

	if itemId == 0 then
		refuseReliable("picked.item: dictionary full")
	end

	buffer.writeu16(out, offset + 1, itemId)

	if type(title) ~= "string" then
		refuseReliable("picked.title: expected string")
	end

	if #title > 24 then
		refuseReliable("picked.title: length out of range")
	end

	if utf8.len(title) == nil then
		refuseReliable("picked.title: invalid UTF-8")
	end

	local titleId: number = internDictionary(title)

	if titleId == 0 then
		refuseReliable("picked.title: dictionary full")
	end

	buffer.writeu16(out, offset + 3, titleId)
end

local function writestock(value: { [Item]: Slot })
	local offset: number, out: buffer = beginReliable(82)
	buffer.writeu8(out, offset, 2)

	if type(value) ~= "table" then
		refuseReliable("stock: expected table")
	end

	local valueCount: number = 0

	for _ in value do
		valueCount += 1
	end

	if valueCount > 16 then
		refuseReliable("stock: length out of range")
	end

	buffer.writeu8(out, offset + 1, valueCount)
	offset += 2

	for valueKey, valueValue in value do
		if type(valueKey) ~= "string" then
			refuseReliable("stock[key]: expected string")
		end

		if #valueKey < 1 or #valueKey > 32 then
			refuseReliable("stock[key]: length out of range")
		end

		local valueKeyId: number = internDictionary(valueKey)

		if valueKeyId == 0 then
			refuseReliable("stock[key]: dictionary full")
		end

		buffer.writeu16(out, offset, valueKeyId)

		if type(valueValue) ~= "table" then
			refuseReliable("stock[value]: expected table")
		end

		local title = valueValue.title

		if type(title) ~= "string" then
			refuseReliable("stock[value].title: expected string")
		end

		if #title > 24 then
			refuseReliable("stock[value].title: length out of range")
		end

		if utf8.len(title) == nil then
			refuseReliable("stock[value].title: invalid UTF-8")
		end

		local titleId: number = internDictionary(title)

		if titleId == 0 then
			refuseReliable("stock[value].title: dictionary full")
		end

		buffer.writeu16(out, offset + 2, titleId)
		local count = valueValue.count

		if type(count) ~= "number" or bit32.band(count, 255) ~= count then
			refuseReliable("stock[value].count: expected u8")
		end

		buffer.writeu8(out, offset + 4, count)
		offset += 5
	end

	trimReliable(offset)
end

local function readlookup(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 4 > length then
		error("lookup: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local value: number = buffer.readu16(packet, cursor + 2)
	cursor += 4

	return runtime:call(1, player, slot, cursor, sideCursor, value)
end

local function writelookup(slot: number, status: number, value: Item?)
	local offset: number, out: buffer = beginReliable(7)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)
	offset += 4

	if status == 0 then
		local flags: number = 0
		flags += value ~= nil and 1 or 0
		buffer.writeu8(out, offset, flags)
		offset += 1

		if value ~= nil then
			if type(value) ~= "string" then
				refuseReliable("lookup: expected string")
			end

			if #value < 1 or #value > 32 then
				refuseReliable("lookup: length out of range")
			end

			local valueId: number = internDictionary(value)

			if valueId == 0 then
				refuseReliable("lookup: dictionary full")
			end

			buffer.writeu16(out, offset, valueId)
			offset += 2
		end
	end

	trimReliable(offset)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x8E079DB0,
	scope = "Dictionary",
	side = "server",
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
		[1] = { name = "lookup", kind = "call", rate = 60, read = readlookup, reply = writelookup },
	},

	outgoing = {
		[1] = { name = "picked", kind = "event", reliable = true, minBytes = 5, maxBytes = 5 },
		[2] = { name = "stock", kind = "event", reliable = true, minBytes = 2, maxBytes = 82 },
		[3] = { name = "lookup", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
refuseReliable = runtime.reliable.refuse
internDictionary = runtime.intern

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	picked = table.freeze({
		fire = function (player: Player | Bot, item: Item, title: Title)
			if (before[1] == nil or before[1](player, item, title)) and runtime:target(player) then
				writepicked(item, title)
			end
		end,

		fireAll = function (item: Item, title: Title)
			runtime:broadcast(1, nil, nil, writepicked, item, title)
		end,

		fireList = function (players: { Player | Bot }, item: Item, title: Title)
			runtime:broadcast(1, players, nil, writepicked, item, title)
		end,

		fireExcept = function (player: Player | Bot, item: Item, title: Title)
			runtime:broadcast(1, nil, player, writepicked, item, title)
		end,

		fireSet = function (players: { [Player | Bot]: true }, item: Item, title: Title)
			runtime:broadcast(1, players, nil, writepicked, item, title)
		end,
	}) :: ServerEvent<(Item, Title)>,

	stock = table.freeze({
		fire = function (player: Player | Bot, value: { [Item]: Slot })
			if (before[2] == nil or before[2](player, value)) and runtime:target(player) then
				writestock(value)
			end
		end,

		fireAll = function (value: { [Item]: Slot })
			runtime:broadcast(2, nil, nil, writestock, value)
		end,

		fireList = function (players: { Player | Bot }, value: { [Item]: Slot })
			runtime:broadcast(2, players, nil, writestock, value)
		end,

		fireExcept = function (player: Player | Bot, value: { [Item]: Slot })
			runtime:broadcast(2, nil, player, writestock, value)
		end,

		fireSet = function (players: { [Player | Bot]: true }, value: { [Item]: Slot })
			runtime:broadcast(2, players, nil, writestock, value)
		end,
	}) :: ServerEvent<({ [Item]: Slot })>,

	lookup = table.freeze({
		on = function (handler: (player: Player | Bot, value: number) -> (Item?)): () -> ()
			return runtime:handle(1, handler)
		end,
	}) :: ServerFunction<(number), (Item?)>,

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

	budget = function (bytesPerSecond: number?)
		runtime:budget(bytesPerSecond)
	end,

	isBot = runtime.isBot,
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
