--[[
    The client module Volt 0.1.0 generated from Awaited.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Tracked = { part: BasePart, at: Vector3 }

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
local instanceById: (number) -> Instance?

local function readTracked(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Tracked)
	if cursor + 16 > length then
		error("Tracked: truncated")
	end

	local part: BasePart? = instanceById(buffer.readu32(packet, cursor)) :: BasePart?

	if part ~= nil and not part:IsA("BasePart") then
		error("Tracked.part: expected AwaitedInstance(BasePart)")
	end

	local atX: number = buffer.readf32(packet, cursor + 4)

	if atX ~= atX then
		error("Tracked.at.X: out of range")
	end

	local atY: number = buffer.readf32(packet, cursor + 8)

	if atY ~= atY then
		error("Tracked.at.Y: out of range")
	end

	local atZ: number = buffer.readf32(packet, cursor + 12)

	if atZ ~= atZ then
		error("Tracked.at.Z: out of range")
	end

	local at: Vector3 = Vector3.new(atX, atY, atZ)
	cursor += 16
	local value = { part = part :: BasePart, at = at }

	return cursor, sideCursor, value
end

local function readWorld_Spawned(_: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	local start: number, sideStart: number = cursor, sideCursor

	if cursor + 6 > length then
		error("World.Spawned: truncated")
	end

	local model: Model? = instanceById(buffer.readu32(packet, cursor)) :: Model?

	if model ~= nil and not model:IsA("Model") then
		error("World.Spawned.model: expected AwaitedInstance(Model)")
	end

	local health: number = buffer.readu16(packet, cursor + 4)
	cursor += 6

	return runtime:await(1, packet, start, cursor, side, sideStart, sideCursor, model :: Model, health)
end

local function readWorld_Plain(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("World.Plain: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(2, player, cursor, sideCursor, value)
end

local function readWorld_Group(_: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	local start: number, sideStart: number = cursor, sideCursor

	if cursor + 2 > length then
		error("World.Group: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local membersLength: number = buffer.readu8(packet, cursor + 1)

	if membersLength > 8 then
		error("World.Group.members: length out of range")
	end

	local leader: Instance?
	cursor += 2

	if cursor + 4 * membersLength > length then
		error("World.Group.members: truncated")
	end

	local members: { BasePart } = table.create(membersLength) :: { BasePart }

	for index = 1, membersLength do
		local membersEntry: BasePart? = instanceById(buffer.readu32(packet, cursor)) :: BasePart?

		if membersEntry ~= nil and not membersEntry:IsA("BasePart") then
			error("World.Group.members[]: expected AwaitedInstance(BasePart)")
		end

		cursor += 4
		members[index] = membersEntry :: BasePart
	end

	if bit32.btest(flags, 1) then
		if cursor + 4 > length then
			error("World.Group.leader: truncated")
		end

		local leader_2: Instance? = instanceById(buffer.readu32(packet, cursor))
		cursor += 4
		leader = leader_2 :: Instance
	end

	return runtime:await(3, packet, start, cursor, side, sideStart, sideCursor, members, leader)
end

local function readWorld_Brief(_: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	local start: number, sideStart: number = cursor, sideCursor

	if cursor + 4 > length then
		error("World.Brief: truncated")
	end

	local value: BasePart? = instanceById(buffer.readu32(packet, cursor)) :: BasePart?

	if value ~= nil and not value:IsA("BasePart") then
		error("World.Brief: expected AwaitedInstance(BasePart)")
	end

	cursor += 4

	return runtime:await(4, packet, start, cursor, side, sideStart, sideCursor, value :: BasePart)
end

local function readWorld_Track(_: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	local start: number, sideStart: number = cursor, sideCursor
	local first: Tracked
	local second: Tracked
	cursor, sideCursor, first = readTracked(packet, cursor, side, sideCursor, length)
	cursor, sideCursor, second = readTracked(packet, cursor, side, sideCursor, length)

	return runtime:await(5, packet, start, cursor, side, sideStart, sideCursor, first, second)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xA41A43AA,
	scope = "Awaited",
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

	messages = {
		[1] = { name = "World.Spawned", kind = "event", mode = "ManySync", queue = 64, timeout = 10, read = readWorld_Spawned },
		[2] = { name = "World.Plain", kind = "event", mode = "ManySync", queue = 64, read = readWorld_Plain },
		[3] = { name = "World.Group", kind = "event", mode = "SingleAsync", queue = 64, timeout = 10, read = readWorld_Group },
		[4] = { name = "World.Brief", kind = "event", mode = "Polling", queue = 64, timeout = 0.001, read = readWorld_Brief },
		[5] = { name = "World.Track", kind = "event", mode = "ManySync", queue = 64, timeout = 10, read = readWorld_Track },
	},

	outgoing = {},
})

instanceById = runtime.instanceById

local Network = {
	World = table.freeze({
		Spawned = table.freeze({
			on = function (listener: (model: Model, health: number) -> ()): () -> ()
				return runtime:on(1, listener)
			end,

			iter = function (): () -> (number, Model, number)
				return runtime:iter(1)
			end,
		}) :: ClientListener<(Model, number)>,

		Plain = table.freeze({
			on = function (listener: (value: number) -> ()): () -> ()
				return runtime:on(2, listener)
			end,

			iter = function (): () -> (number, number)
				return runtime:iter(2)
			end,
		}) :: ClientListener<(number)>,

		Group = table.freeze({
			on = function (listener: (members: { BasePart }, leader: Instance?) -> ()): () -> ()
				return runtime:on(3, listener)
			end,

			iter = function (): () -> (number, { BasePart }, Instance?)
				return runtime:iter(3)
			end,
		}) :: ClientListener<({ BasePart }, Instance?)>,

		Brief = table.freeze({
			iter = function (): () -> (number, BasePart)
				return runtime:iter(4)
			end,
		}) :: ClientPolling<(BasePart)>,

		Track = table.freeze({
			on = function (listener: (first: Tracked, second: Tracked) -> ()): () -> ()
				return runtime:on(5, listener)
			end,

			iter = function (): () -> (number, Tracked, Tracked)
				return runtime:iter(5)
			end,
		}) :: ClientListener<(Tracked, Tracked)>,
	}),

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
	["World.Spawned"] = Network.World.Spawned,
	["World.Plain"] = Network.World.Plain,
	["World.Group"] = Network.World.Group,
	["World.Brief"] = Network.World.Brief,
	["World.Track"] = Network.World.Track,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
