--[[
    The server module Volt 0.1.0 generated from Exports.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Save = { version: number, names: { string }, owner: Instance? }
export type Hit = { part: BasePart, model: Model? }
export type Inventory_Kind = "Bag" | "Chest"

type Bot = Volt.Bot

type ServerEvent<A...> = {
	fire: (player: Player | Bot, A...) -> (),
	fireAll: (A...) -> (),
	fireList: (players: { Player | Bot }, A...) -> (),
	fireExcept: (player: Player | Bot, A...) -> (),
	fireSet: (players: { [Player | Bot]: true }, A...) -> (),
}

type ServerListener<A...> = {
	on: (listener: (player: Player | Bot, A...) -> ()) -> () -> (),
	iter: () -> () -> (number, Player | Bot, A...),
}

type ServerPolling<A...> = { iter: () -> () -> (number, Player | Bot, A...) }

type ServerFunction<A..., R...> = {
	on: (handler: (player: Player | Bot, A...) -> R...) -> () -> (),
}

type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime

local INVENTORY_KIND: { "Bag" | "Chest" } = { "Bag", "Chest" }

local function writeSave(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(4)
	local flags: number = 0

	if type(value) ~= "table" then
		refuse("Save: expected table")
	end

	local version = value.version

	if type(version) ~= "number" or bit32.band(version, 65535) ~= version then
		refuse("Save.version: expected u16")
	end

	buffer.writeu16(out, offset + 1, version)
	local names = value.names

	if type(names) ~= "table" then
		refuse("Save.names: expected table")
	end

	if #names > 4 then
		refuse("Save.names: length out of range")
	end

	buffer.writeu8(out, offset + 3, #names)
	local owner = value.owner
	flags += owner ~= nil and 1 or 0
	buffer.writeu8(out, offset, flags)

	for index = 1, #names do
		local offset_2: number, out_2: buffer = allocate(1)
		local namesEntry = names[index]

		if type(namesEntry) ~= "string" then
			refuse("Save.names[]: expected string")
		end

		if #namesEntry > 16 then
			refuse("Save.names[]: length out of range")
		end

		buffer.writeu8(out_2, offset_2, #namesEntry)
		local namesEntryOffset: number, namesEntryOut: buffer = allocate(#namesEntry)
		buffer.writestring(namesEntryOut, namesEntryOffset, namesEntry)
	end

	if owner ~= nil then
		if typeof(owner) ~= "Instance" then
			refuse("Save.owner: expected Instance")
		end

		slot(owner)
	end
end

local function readSave(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number, Save)
	if cursor + 4 > length then
		error("Save: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local version: number = buffer.readu16(packet, cursor + 1)
	local namesLength: number = buffer.readu8(packet, cursor + 3)

	if namesLength > 4 then
		error("Save.names: length out of range")
	end

	local owner: Instance?
	cursor += 4

	if cursor + namesLength > length then
		error("Save.names: truncated")
	end

	local names: { string } = table.create(namesLength) :: { string }

	for index = 1, namesLength do
		if cursor + 1 > length then
			error("Save.names: truncated")
		end

		local namesEntryLength: number = buffer.readu8(packet, cursor)

		if namesEntryLength > 16 then
			error("Save.names[]: length out of range")
		end

		cursor += 1

		if cursor + namesEntryLength > length then
			error("Save.names[]: truncated")
		end

		local namesEntry: string = buffer.readstring(packet, cursor, namesEntryLength)
		cursor += namesEntryLength
		names[index] = namesEntry
	end

	if bit32.btest(flags, 1) then
		local owner_2: Instance? = side[sideCursor]
		sideCursor += 1

		if typeof(owner_2) ~= "Instance" then
			error("Save.owner: expected Instance")
		end

		owner = owner_2
	end

	local value = { version = version, names = names, owner = owner }

	return cursor, sideCursor, value
end

local function writeHit(_: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any)
	if type(value) ~= "table" then
		refuse("Hit: expected table")
	end

	local part = value.part

	if typeof(part) ~= "Instance" or not (part :: Instance):IsA("BasePart") then
		refuse("Hit.part: expected Instance(BasePart)")
	end

	slot(part)
	local model = value.model

	if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then
		refuse("Hit.model: expected StreamedInstance(Model)")
	end

	slot(model)
end

local function readHit(_: buffer, cursor: number, side: { any }, sideCursor: number, _: number): (number, number, Hit)
	local part: BasePart? = side[sideCursor]
	sideCursor += 1

	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		error("Hit.part: expected Instance(BasePart)")
	end

	local model: Model? = side[sideCursor]
	sideCursor += 1

	if model ~= nil and not model:IsA("Model") then
		error("Hit.model: expected StreamedInstance(Model)")
	end

	local value = { part = part, model = model }

	return cursor, sideCursor, value
end

local function writeInventory_Kind(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(1)
	local flags: number = 0
	local valueIndex: number = table.find(INVENTORY_KIND, value) or 0

	if valueIndex == 0 then
		refuse("Inventory.Kind: expected enum { Bag, Chest }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)
end

local function readInventory_Kind(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Inventory_Kind)
	if cursor + 1 > length then
		error("Inventory.Kind: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local value: ("Bag" | "Chest")? = INVENTORY_KIND[bit32.extract(flags, 0, 1) + 1]

	if not value then
		error("Inventory.Kind: out of range")
	end

	cursor += 1

	return cursor, sideCursor, value
end

local function readPing(player: (Player | Bot)?, _: buffer, cursor: number, _: { any }, sideCursor: number, _: number): (number, number)
	return runtime:deliver(1, player, cursor, sideCursor)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x0BD2572B,
	scope = "Exports",
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
		[1] = { name = "Ping", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readPing },
	},

	outgoing = {},
})

local Network = {
	Save = table.freeze({
		write = function (value: Save): (buffer, { any }?)
			return runtime:encode("Save", writeSave, value)
		end,

		read = function (packet: buffer, side: { any }?): Save
			return runtime:decode(readSave, packet, side)
		end,
	}) :: Exported<Save>,

	Hit = table.freeze({
		write = function (value: Hit): (buffer, { any }?)
			return runtime:encode("Hit", writeHit, value)
		end,

		read = function (packet: buffer, side: { any }?): Hit
			return runtime:decode(readHit, packet, side)
		end,
	}) :: Exported<Hit>,

	Inventory = table.freeze({
		Kind = table.freeze({
			write = function (value: Inventory_Kind): (buffer, { any }?)
				return runtime:encode("Inventory.Kind", writeInventory_Kind, value)
			end,

			read = function (packet: buffer, side: { any }?): Inventory_Kind
				return runtime:decode(readInventory_Kind, packet, side)
			end,
		}) :: Exported<Inventory_Kind>,
	}),

	Ping = table.freeze({
		on = function (listener: (player: Player | Bot) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player | Bot)
			return runtime:iter(1)
		end,
	}) :: ServerListener<()>,

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
	["Ping"] = Network.Ping,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }

Network.exports = table.freeze({
	["Save"] = Network.Save,
	["Hit"] = Network.Hit,
	["Inventory.Kind"] = Network.Inventory.Kind,
}) :: { [string]: any }

return table.freeze(Network)
