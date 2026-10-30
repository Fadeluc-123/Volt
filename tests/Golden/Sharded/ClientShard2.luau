--[[
    Shard 2 of 3 of the client module Volt 0.1.0 generated from Sharded.volt:
    the writers and readers of some of its messages, with the handles its
    entry module builds the API from. Generated code: change the schema and
    run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

type Team = "Red" | "Blue"
type Stack = { item: string, quantity: number }
type Save = { version: number, stacks: { Stack } }

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
local allocateReliable: (number) -> (number, buffer)
local slotReliable: (any) -> ()
local refuseReliable: (string) -> never
local before: { [number]: Volt.Hook }

local TEAM: { "Red" | "Blue" } = { "Red", "Blue" }

local function writeStack(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(3)

	if type(value) ~= "table" then
		refuse("Stack: expected table")
	end

	local item = value.item

	if type(item) ~= "string" then
		refuse("Stack.item: expected string")
	end

	if #item < 1 or #item > 32 then
		refuse("Stack.item: length out of range")
	end

	buffer.writeu8(out, offset, #item - 1)
	local quantity = value.quantity

	if type(quantity) ~= "number" or bit32.band(quantity, 65535) ~= quantity then
		refuse("Stack.quantity: expected u16")
	end

	buffer.writeu16(out, offset + 1, quantity)
	local itemOffset: number, itemOut: buffer = allocate(#item)
	buffer.writestring(itemOut, itemOffset, item)
end

local function readStack(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Stack)
	if cursor + 3 > length then
		error("Stack: truncated")
	end

	local itemLength: number = 1 + buffer.readu8(packet, cursor)

	if itemLength > 32 then
		error("Stack.item: length out of range")
	end

	local quantity: number = buffer.readu16(packet, cursor + 1)
	cursor += 3

	if cursor + itemLength > length then
		error("Stack.item: truncated")
	end

	local item: string = buffer.readstring(packet, cursor, itemLength)
	cursor += itemLength
	local value = { item = item, quantity = quantity }

	return cursor, sideCursor, value
end

local function writeTeam(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(1)
	local flags: number = 0
	local valueIndex: number = table.find(TEAM, value) or 0

	if valueIndex == 0 then
		refuse("Team: expected enum { Red, Blue }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)
end

local function writeSync(value: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 3)

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseReliable("Sync: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function readSync(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Sync: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(1, player, cursor, sideCursor, value)
end

local function readInventory_Patch(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Inventory.Patch: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 16 then
		error("Inventory.Patch: length out of range")
	end

	cursor += 1

	if cursor + 4 * valueLength > length then
		error("Inventory.Patch: truncated")
	end

	local value: { Stack } = table.create(valueLength) :: { Stack }

	for index = 1, valueLength do
		local valueEntry: Stack
		cursor, sideCursor, valueEntry = readStack(packet, cursor, side, sideCursor, length)
		value[index] = valueEntry
	end

	return runtime:deliver(2, player, cursor, sideCursor, value)
end

local function writeInventory_Transfer(slot: number, item: Stack, team: Team)
	local offset: number, out: buffer = beginReliable(3)
	buffer.writeu8(out, offset, 4)
	buffer.writeu16(out, offset + 1, slot)
	writeStack(allocateReliable, slotReliable, refuseReliable, item)
	writeTeam(allocateReliable, slotReliable, refuseReliable, team)
end

local function readInventory_Transfer(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Inventory.Transfer: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("Inventory.Transfer: truncated")
		end

		local flags: number = buffer.readu8(packet, cursor)
		local reason: string?
		cursor += 1

		if bit32.btest(flags, 2) then
			if cursor + 1 > length then
				error("Inventory.Transfer.reason: truncated")
			end

			local reasonLength: number = buffer.readu8(packet, cursor)

			if reasonLength > 64 then
				error("Inventory.Transfer.reason: length out of range")
			end

			cursor += 1

			if cursor + reasonLength > length then
				error("Inventory.Transfer.reason: truncated")
			end

			local reason_2: string = buffer.readstring(packet, cursor, reasonLength)
			cursor += reasonLength
			reason = reason_2
		end

		return runtime:reply(3, player, slot, cursor, sideCursor, bit32.btest(flags, 1), reason)
	end

	return runtime:refused(3, player, slot, status, packet, cursor, sideCursor, length)
end

return {
	bind = function (started: Volt.Runtime)
		runtime = started
		beginReliable = runtime.reliable.begin
		allocateReliable = runtime.reliable.allocate
		slotReliable = runtime.reliable.slot
		refuseReliable = runtime.reliable.refuse
		before = runtime.before
	end,

	readSync = readSync,
	readInventory_Patch = readInventory_Patch,
	readInventory_Transfer = readInventory_Transfer,

	handles = {
		["Sync"] = table.freeze({
			fire = function (value: number)
				if before[3] == nil or before[3](nil, value) then
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

		["Inventory.Patch"] = table.freeze({
			on = function (listener: (value: { Stack }) -> ()): () -> ()
				return runtime:on(2, listener)
			end,

			iter = function (): () -> (number, { Stack })
				return runtime:iter(2)
			end,
		}) :: ClientListener<({ Stack })>,

		["Inventory.Transfer"] = table.freeze({
			invoke = function (item: Stack, team: Team): (boolean, boolean, string?)
				return runtime:invoke(3, writeInventory_Transfer, item, team)
			end,
		}) :: ClientFunction<(Stack, Team), (boolean, string?)>,
	},
}
