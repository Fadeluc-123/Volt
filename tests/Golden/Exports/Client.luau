--[[
    The client module Volt 0.1.0 generated from Exports.volt: a writer per
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
export type Inventory_Kind = "Bag" | "Chest"

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)

local INVENTORY_KIND: { string } = { "Bag", "Chest" }

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

local function readSave(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 4 > length then
		error("Save: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local version: number = buffer.readu16(packet, cursor + 1)
	local namesLength: number = buffer.readu8(packet, cursor + 3)

	if namesLength > 4 then
		error("Save.names: length out of range")
	end

	local owner
	cursor += 4

	if cursor + namesLength > length then
		error("Save.names: truncated")
	end

	local names = table.create(namesLength)

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

local function readInventory_Kind(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Inventory.Kind: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local value: string? = INVENTORY_KIND[bit32.extract(flags, 0, 1) + 1]

	if not value then
		error("Inventory.Kind: out of range")
	end

	cursor += 1

	return cursor, sideCursor, value
end

local function writePing()
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 1)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x4EA0F775,
	scope = "Exports",
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

	messages = {},

	outgoing = {
		[1] = { name = "Ping", kind = "event", reliable = true, minBytes = 1, maxBytes = 1 },
	},
})

beginReliable = runtime.reliable.begin

local before: { [number]: Volt.Hook } = runtime.before

local net = {
	Save = table.freeze({
		write = function (value: Save): (buffer, { any }?)
			return runtime:encode("Save", writeSave, value)
		end,

		read = function (packet: buffer, side: { any }?): Save
			return runtime:decode(readSave, packet, side)
		end,
	}),

	Inventory = table.freeze({
		Kind = table.freeze({
			write = function (value: Inventory_Kind): (buffer, { any }?)
				return runtime:encode("Inventory.Kind", writeInventory_Kind, value)
			end,

			read = function (packet: buffer, side: { any }?): Inventory_Kind
				return runtime:decode(readInventory_Kind, packet, side)
			end,
		}),
	}),

	Ping = table.freeze({
		fire = function ()
			if before[1] == nil or before[1](nil) then
				writePing()
			end
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
	["Ping"] = net.Ping,
})

net.functions = table.freeze({})

net.exports = table.freeze({
	["Save"] = net.Save,
	["Inventory.Kind"] = net.Inventory.Kind,
})

return table.freeze(net)
