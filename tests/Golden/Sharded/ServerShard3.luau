--[[
    Shard 3 of 3 of the server module Volt 0.1.0 generated from Sharded.volt:
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
local allocateReliable: (number) -> (number, buffer)
local refuseReliable: (string) -> never

local TEAM: { "Red" | "Blue" } = { "Red", "Blue" }

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

local function readInventory_Picked(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	local value: Team
	cursor, sideCursor, value = readTeam(packet, cursor, side, sideCursor, length)

	return runtime:deliver(5, player, cursor, sideCursor, value)
end

local function readEcho(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Echo: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local value: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	return runtime:call(6, player, slot, cursor, sideCursor, value)
end

local function writeEcho(slot: number, status: number, value: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 4)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)

	if status == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)

		if type(value) ~= "number" or bit32.band(value, 255) ~= value then
			refuseReliable("Echo: expected u8")
		end

		buffer.writeu8(out_2, offset_2, value)
	end
end

return {
	bind = function (started: Volt.Runtime)
		runtime = started
		beginReliable = runtime.reliable.begin
		allocateReliable = runtime.reliable.allocate
		refuseReliable = runtime.reliable.refuse
	end,

	readInventory_Picked = readInventory_Picked,
	readEcho = readEcho,
	writeEcho = writeEcho,

	handles = {
		["Inventory.Picked"] = table.freeze({
			on = function (listener: (player: Player | Bot, value: Team) -> ()): () -> ()
				return runtime:on(5, listener)
			end,

			iter = function (): () -> (number, Player | Bot, Team)
				return runtime:iter(5)
			end,
		}) :: ServerListener<(Team)>,

		["Echo"] = table.freeze({
			on = function (handler: (player: Player | Bot, value: number) -> (number)): () -> ()
				return runtime:handle(6, handler)
			end,
		}) :: ServerFunction<(number), (number)>,
	},
}
