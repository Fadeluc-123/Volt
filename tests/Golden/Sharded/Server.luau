--[[
    The server module Volt 0.1.0 generated from Sharded.volt, as an entry
    and 3 shards beside it: the schema table the runtime starts from and
    the API a game calls, built from the handles the shards hold beside
    each message's writer and reader. Generated code: change the schema
    and run volt again rather than editing these files
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)
local Shard1 = require("./ServerShard1")
local Shard2 = require("./ServerShard2")
local Shard3 = require("./ServerShard3")

export type Team = "Red" | "Blue"
export type Stack = { item: string, quantity: number }
export type Save = { version: number, stacks: { Stack } }

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

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x6F746C80,
	scope = "Sharded",
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
		[1] = { name = "Input", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = Shard1.readInput },
		[2] = { name = "Ready", kind = "event", mode = "ManySync", queue = 64, rate = 120, read = Shard1.readReady },
		[3] = { name = "Sync", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = Shard2.readSync },
		[4] = { name = "Inventory.Transfer", kind = "call", rate = 60, read = Shard2.readInventory_Transfer, reply = Shard2.writeInventory_Transfer },
		[5] = { name = "Inventory.Picked", kind = "event", mode = "ManyAsync", queue = 64, rate = 120, read = Shard3.readInventory_Picked },
		[6] = { name = "Echo", kind = "call", rate = 60, read = Shard3.readEcho, reply = Shard3.writeEcho },
	},

	outgoing = {
		[1] = { name = "Sync", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[2] = { name = "Inventory.Patch", kind = "event", reliable = true, minBytes = 2, maxBytes = 562 },
		[3] = { name = "Inventory.Transfer", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
		[4] = { name = "Echo", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
	},
})

Shard1.bind(runtime)
Shard2.bind(runtime)
Shard3.bind(runtime)

local Network = {
	Save = Shard1.handles["Save"],
	Input = Shard1.handles["Input"],
	Ready = Shard1.handles["Ready"],
	Sync = Shard2.handles["Sync"],

	Inventory = table.freeze({
		Patch = Shard2.handles["Inventory.Patch"],
		Transfer = Shard2.handles["Inventory.Transfer"],
		Picked = Shard3.handles["Inventory.Picked"],
	}),

	Echo = Shard3.handles["Echo"],
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
	["Input"] = Network.Input,
	["Ready"] = Network.Ready,
	["Sync"] = Network.Sync,
	["Inventory.Patch"] = Network.Inventory.Patch,
	["Inventory.Picked"] = Network.Inventory.Picked,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Inventory.Transfer"] = Network.Inventory.Transfer,
	["Echo"] = Network.Echo,
}) :: { [string]: any }

Network.exports = table.freeze({
	["Save"] = Network.Save,
}) :: { [string]: any }

return table.freeze(Network)
