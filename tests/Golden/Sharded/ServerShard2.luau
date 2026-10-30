--[[
    Shard 2 of 3 of the server module Volt 0.1.0 generated from Sharded.volt:
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
local beginReliable: (number) -> (number, buffer)
local trimReliable: (number) -> ()
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

local function readTeam(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Team)
	if cursor + 1 > length then
		error("Team: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local value: ("Red" | "Blue")? = TEAM[bit32.extract(flags, 0, 1) + 1]

	if not value then
		error("Team: out of range")
	end

	cursor += 1

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
	if cursor + 1 > length then
		error("Sync: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(3, player, cursor, sideCursor, value)
end

local function writeInventory_Patch(value: { Stack })
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 2)

	if type(value) ~= "table" then
		refuseReliable("Inventory.Patch: expected table")
	end

	if #value > 16 then
		refuseReliable("Inventory.Patch: length out of range")
	end

	buffer.writeu8(out, offset + 1, #value)

	for index = 1, #value do
		writeStack(allocateReliable, slotReliable, refuseReliable, value[index])
	end
end

local function readInventory_Transfer(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Inventory.Transfer: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local item: Stack
	local team: Team
	cursor += 2
	cursor, sideCursor, item = readStack(packet, cursor, side, sideCursor, length)
	cursor, sideCursor, team = readTeam(packet, cursor, side, sideCursor, length)

	return runtime:call(4, player, slot, cursor, sideCursor, item, team)
end

local function writeInventory_Transfer(slot: number, status: number, ok: boolean, reason: string?)
	local offset: number, out: buffer = beginReliable(70)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)
	offset += 4

	if status == 0 then
		local flags: number = 0

		if type(ok) ~= "boolean" then
			refuseReliable("Inventory.Transfer.ok: expected boolean")
		end

		flags += ok and 1 or 0
		flags += reason ~= nil and 2 or 0
		buffer.writeu8(out, offset, flags)
		offset += 1

		if reason ~= nil then
			if type(reason) ~= "string" then
				refuseReliable("Inventory.Transfer.reason: expected string")
			end

			if #reason > 64 then
				refuseReliable("Inventory.Transfer.reason: length out of range")
			end

			buffer.writeu8(out, offset, #reason)
			offset += 1
			buffer.writestring(out, offset, reason)
			offset += #reason
		end
	end

	trimReliable(offset)
end

return {
	bind = function (started: Volt.Runtime)
		runtime = started
		beginReliable = runtime.reliable.begin
		trimReliable = runtime.reliable.trim
		allocateReliable = runtime.reliable.allocate
		slotReliable = runtime.reliable.slot
		refuseReliable = runtime.reliable.refuse
		before = runtime.before
	end,

	readSync = readSync,
	readInventory_Transfer = readInventory_Transfer,
	writeInventory_Transfer = writeInventory_Transfer,

	handles = {
		["Sync"] = table.freeze({
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
				return runtime:on(3, listener)
			end,

			iter = function (): () -> (number, Player | Bot, number)
				return runtime:iter(3)
			end,
		}) :: ServerEvent<(number)> & ServerListener<(number)>,

		["Inventory.Patch"] = table.freeze({
			fire = function (player: Player | Bot, value: { Stack })
				if (before[2] == nil or before[2](player, value)) and runtime:target(player) then
					writeInventory_Patch(value)
				end
			end,

			fireAll = function (value: { Stack })
				runtime:broadcast(2, nil, nil, writeInventory_Patch, value)
			end,

			fireList = function (players: { Player | Bot }, value: { Stack })
				runtime:broadcast(2, players, nil, writeInventory_Patch, value)
			end,

			fireExcept = function (player: Player | Bot, value: { Stack })
				runtime:broadcast(2, nil, player, writeInventory_Patch, value)
			end,

			fireSet = function (players: { [Player | Bot]: true }, value: { Stack })
				runtime:broadcast(2, players, nil, writeInventory_Patch, value)
			end,
		}) :: ServerEvent<({ Stack })>,

		["Inventory.Transfer"] = table.freeze({
			on = function (handler: (player: Player | Bot, item: Stack, team: Team) -> (boolean, string?)): () -> ()
				return runtime:handle(4, handler)
			end,
		}) :: ServerFunction<(Stack, Team), (boolean, string?)>,
	},
}
