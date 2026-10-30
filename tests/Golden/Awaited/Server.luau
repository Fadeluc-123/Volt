--[[
    The server module Volt 0.1.0 generated from Awaited.volt: a writer per
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
local allocateReliable: (number) -> (number, buffer)
local slotReliable: (any) -> ()
local refuseReliable: (string) -> never
local instanceId: (Instance) -> number

local function writeTracked(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(16)

	if type(value) ~= "table" then
		refuse("Tracked: expected table")
	end

	local part = value.part

	if typeof(part) ~= "Instance" or not (part :: Instance):IsA("BasePart") then
		refuse("Tracked.part: expected AwaitedInstance(BasePart)")
	end

	buffer.writeu32(out, offset, instanceId(part :: Instance))
	local at = value.at

	if typeof(at) ~= "Vector3" then
		refuse("Tracked.at: expected Vector3")
	end

	local atX = at.X

	if atX ~= atX then
		refuse("Tracked.at.X: expected f32")
	end

	buffer.writef32(out, offset + 4, atX)
	local atY = at.Y

	if atY ~= atY then
		refuse("Tracked.at.Y: expected f32")
	end

	buffer.writef32(out, offset + 8, atY)
	local atZ = at.Z

	if atZ ~= atZ then
		refuse("Tracked.at.Z: expected f32")
	end

	buffer.writef32(out, offset + 12, atZ)
end

local function writeWorld_Spawned(model: Model, health: number)
	local offset: number, out: buffer = beginReliable(7)
	buffer.writeu8(out, offset, 1)

	if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then
		refuseReliable("World.Spawned.model: expected AwaitedInstance(Model)")
	end

	buffer.writeu32(out, offset + 1, instanceId(model :: Instance))

	if type(health) ~= "number" or bit32.band(health, 65535) ~= health then
		refuseReliable("World.Spawned.health: expected u16")
	end

	buffer.writeu16(out, offset + 5, health)
end

local function writeWorld_Plain(value: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 2)

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseReliable("World.Plain: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function writeWorld_Group(members: { BasePart }, leader: Instance?)
	local offset: number, out: buffer = beginReliable(39)
	buffer.writeu8(out, offset, 3)
	local flags: number = 0

	if type(members) ~= "table" then
		refuseReliable("World.Group.members: expected table")
	end

	if #members > 8 then
		refuseReliable("World.Group.members: length out of range")
	end

	buffer.writeu8(out, offset + 2, #members)
	flags += leader ~= nil and 1 or 0
	buffer.writeu8(out, offset + 1, flags)
	offset += 3

	for index = 1, #members do
		local membersEntry = members[index]

		if typeof(membersEntry) ~= "Instance" or not (membersEntry :: Instance):IsA("BasePart") then
			refuseReliable("World.Group.members[]: expected AwaitedInstance(BasePart)")
		end

		buffer.writeu32(out, offset, instanceId(membersEntry :: Instance))
		offset += 4
	end

	if leader ~= nil then
		if typeof(leader) ~= "Instance" then
			refuseReliable("World.Group.leader: expected AwaitedInstance")
		end

		buffer.writeu32(out, offset, instanceId(leader :: Instance))
		offset += 4
	end

	trimReliable(offset)
end

local function writeWorld_Brief(value: BasePart)
	local offset: number, out: buffer = beginReliable(5)
	buffer.writeu8(out, offset, 4)

	if typeof(value) ~= "Instance" or not (value :: Instance):IsA("BasePart") then
		refuseReliable("World.Brief: expected AwaitedInstance(BasePart)")
	end

	buffer.writeu32(out, offset + 1, instanceId(value :: Instance))
end

local function writeWorld_Track(first: Tracked, second: Tracked)
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 5)
	writeTracked(allocateReliable, slotReliable, refuseReliable, first)
	writeTracked(allocateReliable, slotReliable, refuseReliable, second)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xA41A43AA,
	scope = "Awaited",
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

	messages = {},

	outgoing = {
		[1] = { name = "World.Spawned", kind = "event", reliable = true, minBytes = 7, maxBytes = 7 },
		[2] = { name = "World.Plain", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[3] = { name = "World.Group", kind = "event", reliable = true, minBytes = 3, maxBytes = 39 },
		[4] = { name = "World.Brief", kind = "event", reliable = true, minBytes = 5, maxBytes = 5 },
		[5] = { name = "World.Track", kind = "event", reliable = true, minBytes = 33, maxBytes = 33 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
allocateReliable = runtime.reliable.allocate
slotReliable = runtime.reliable.slot
refuseReliable = runtime.reliable.refuse
instanceId = runtime.instanceId

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	World = table.freeze({
		Spawned = table.freeze({
			fire = function (player: Player | Bot, model: Model, health: number)
				if (before[1] == nil or before[1](player, model, health)) and runtime:target(player) then
					writeWorld_Spawned(model, health)
				end
			end,

			fireAll = function (model: Model, health: number)
				runtime:broadcast(1, nil, nil, writeWorld_Spawned, model, health)
			end,

			fireList = function (players: { Player | Bot }, model: Model, health: number)
				runtime:broadcast(1, players, nil, writeWorld_Spawned, model, health)
			end,

			fireExcept = function (player: Player | Bot, model: Model, health: number)
				runtime:broadcast(1, nil, player, writeWorld_Spawned, model, health)
			end,

			fireSet = function (players: { [Player | Bot]: true }, model: Model, health: number)
				runtime:broadcast(1, players, nil, writeWorld_Spawned, model, health)
			end,
		}) :: ServerEvent<(Model, number)>,

		Plain = table.freeze({
			fire = function (player: Player | Bot, value: number)
				if (before[2] == nil or before[2](player, value)) and runtime:target(player) then
					writeWorld_Plain(value)
				end
			end,

			fireAll = function (value: number)
				runtime:broadcast(2, nil, nil, writeWorld_Plain, value)
			end,

			fireList = function (players: { Player | Bot }, value: number)
				runtime:broadcast(2, players, nil, writeWorld_Plain, value)
			end,

			fireExcept = function (player: Player | Bot, value: number)
				runtime:broadcast(2, nil, player, writeWorld_Plain, value)
			end,

			fireSet = function (players: { [Player | Bot]: true }, value: number)
				runtime:broadcast(2, players, nil, writeWorld_Plain, value)
			end,
		}) :: ServerEvent<(number)>,

		Group = table.freeze({
			fire = function (player: Player | Bot, members: { BasePart }, leader: Instance?)
				if (before[3] == nil or before[3](player, members, leader)) and runtime:target(player) then
					writeWorld_Group(members, leader)
				end
			end,

			fireAll = function (members: { BasePart }, leader: Instance?)
				runtime:broadcast(3, nil, nil, writeWorld_Group, members, leader)
			end,

			fireList = function (players: { Player | Bot }, members: { BasePart }, leader: Instance?)
				runtime:broadcast(3, players, nil, writeWorld_Group, members, leader)
			end,

			fireExcept = function (player: Player | Bot, members: { BasePart }, leader: Instance?)
				runtime:broadcast(3, nil, player, writeWorld_Group, members, leader)
			end,

			fireSet = function (players: { [Player | Bot]: true }, members: { BasePart }, leader: Instance?)
				runtime:broadcast(3, players, nil, writeWorld_Group, members, leader)
			end,
		}) :: ServerEvent<({ BasePart }, Instance?)>,

		Brief = table.freeze({
			fire = function (player: Player | Bot, value: BasePart)
				if (before[4] == nil or before[4](player, value)) and runtime:target(player) then
					writeWorld_Brief(value)
				end
			end,

			fireAll = function (value: BasePart)
				runtime:broadcast(4, nil, nil, writeWorld_Brief, value)
			end,

			fireList = function (players: { Player | Bot }, value: BasePart)
				runtime:broadcast(4, players, nil, writeWorld_Brief, value)
			end,

			fireExcept = function (player: Player | Bot, value: BasePart)
				runtime:broadcast(4, nil, player, writeWorld_Brief, value)
			end,

			fireSet = function (players: { [Player | Bot]: true }, value: BasePart)
				runtime:broadcast(4, players, nil, writeWorld_Brief, value)
			end,
		}) :: ServerEvent<(BasePart)>,

		Track = table.freeze({
			fire = function (player: Player | Bot, first: Tracked, second: Tracked)
				if (before[5] == nil or before[5](player, first, second)) and runtime:target(player) then
					writeWorld_Track(first, second)
				end
			end,

			fireAll = function (first: Tracked, second: Tracked)
				runtime:broadcast(5, nil, nil, writeWorld_Track, first, second)
			end,

			fireList = function (players: { Player | Bot }, first: Tracked, second: Tracked)
				runtime:broadcast(5, players, nil, writeWorld_Track, first, second)
			end,

			fireExcept = function (player: Player | Bot, first: Tracked, second: Tracked)
				runtime:broadcast(5, nil, player, writeWorld_Track, first, second)
			end,

			fireSet = function (players: { [Player | Bot]: true }, first: Tracked, second: Tracked)
				runtime:broadcast(5, players, nil, writeWorld_Track, first, second)
			end,
		}) :: ServerEvent<(Tracked, Tracked)>,
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
	["World.Spawned"] = Network.World.Spawned,
	["World.Plain"] = Network.World.Plain,
	["World.Group"] = Network.World.Group,
	["World.Brief"] = Network.World.Brief,
	["World.Track"] = Network.World.Track,
}) :: { [string]: any }

Network.functions = table.freeze({}) :: { [string]: any }
Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
