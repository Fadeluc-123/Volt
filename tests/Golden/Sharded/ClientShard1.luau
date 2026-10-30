--[[
    Shard 1 of 3 of the client module Volt 0.1.0 generated from Sharded.volt:
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
local beginUnreliable: (number) -> (number, buffer)
local refuseUnreliable: (string) -> never
local markUnreliable: () -> ()
local before: { [number]: Volt.Hook }

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

local function writeSave(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(3)

	if type(value) ~= "table" then
		refuse("Save: expected table")
	end

	local version = value.version

	if type(version) ~= "number" or bit32.band(version, 65535) ~= version then
		refuse("Save.version: expected u16")
	end

	buffer.writeu16(out, offset, version)
	local stacks = value.stacks

	if type(stacks) ~= "table" then
		refuse("Save.stacks: expected table")
	end

	if #stacks > 8 then
		refuse("Save.stacks: length out of range")
	end

	buffer.writeu8(out, offset + 2, #stacks)

	for index = 1, #stacks do
		writeStack(allocate, slot, refuse, stacks[index])
	end
end

local function readSave(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number, Save)
	if cursor + 3 > length then
		error("Save: truncated")
	end

	local version: number = buffer.readu16(packet, cursor)
	local stacksLength: number = buffer.readu8(packet, cursor + 2)

	if stacksLength > 8 then
		error("Save.stacks: length out of range")
	end

	cursor += 3

	if cursor + 4 * stacksLength > length then
		error("Save.stacks: truncated")
	end

	local stacks: { Stack } = table.create(stacksLength) :: { Stack }

	for index = 1, stacksLength do
		local stacksEntry: Stack
		cursor, sideCursor, stacksEntry = readStack(packet, cursor, side, sideCursor, length)
		stacks[index] = stacksEntry
	end

	local value = { version = version, stacks = stacks }

	return cursor, sideCursor, value
end

local function writeInput(dir: number, jump: boolean)
	local offset: number, out: buffer = beginUnreliable(3)
	buffer.writeu8(out, offset, 1)
	local flags: number = 0

	if type(dir) ~= "number" or bit32.band(dir, 255) ~= dir or dir > 8 then
		refuseUnreliable("Input.dir: expected u8(0..8)")
	end

	buffer.writeu8(out, offset + 2, dir)

	if type(jump) ~= "boolean" then
		refuseUnreliable("Input.jump: expected boolean")
	end

	flags += jump and 1 or 0
	buffer.writeu8(out, offset + 1, flags)
	markUnreliable()
end

local function writeReady()
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 2)
end

return {
	bind = function (started: Volt.Runtime)
		runtime = started
		beginReliable = runtime.reliable.begin
		beginUnreliable = runtime.unreliable.begin
		refuseUnreliable = runtime.unreliable.refuse
		markUnreliable = runtime.unreliable.mark
		before = runtime.before
	end,

	handles = {
		["Save"] = table.freeze({
			write = function (value: Save): (buffer, { any }?)
				return runtime:encode("Save", writeSave, value)
			end,

			read = function (packet: buffer, side: { any }?): Save
				return runtime:decode(readSave, packet, side)
			end,
		}) :: Exported<Save>,

		["Input"] = table.freeze({
			fire = function (dir: number, jump: boolean)
				if before[1] == nil or before[1](nil, dir, jump) then
					writeInput(dir, jump)
				end
			end,
		}) :: ClientEvent<(number, boolean)>,

		["Ready"] = table.freeze({
			fire = function ()
				if before[2] == nil or before[2](nil) then
					writeReady()
				end
			end,
		}) :: ClientEvent<()>,
	},
}
