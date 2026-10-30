--[[
    Shard 3 of 3 of the client module Volt 0.1.0 generated from Sharded.volt:
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

local function writeInventory_Picked(value: Team)
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 5)
	writeTeam(allocateReliable, slotReliable, refuseReliable, value)
end

local function writeEcho(slot: number, value: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 6)
	buffer.writeu16(out, offset + 1, slot)

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseReliable("Echo: expected u8")
	end

	buffer.writeu8(out, offset + 3, value)
end

local function readEcho(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Echo: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("Echo: truncated")
		end

		local value: number = buffer.readu8(packet, cursor)
		cursor += 1

		return runtime:reply(4, player, slot, cursor, sideCursor, value)
	end

	return runtime:refused(4, player, slot, status, packet, cursor, sideCursor, length)
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

	readEcho = readEcho,

	handles = {
		["Inventory.Picked"] = table.freeze({
			fire = function (value: Team)
				if before[5] == nil or before[5](nil, value) then
					writeInventory_Picked(value)
				end
			end,
		}) :: ClientEvent<(Team)>,

		["Echo"] = table.freeze({
			invoke = function (value: number): (boolean, number)
				return runtime:invoke(4, writeEcho, value)
			end,
		}) :: ClientFunction<(number), (number)>,
	},
}
