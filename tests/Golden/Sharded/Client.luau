--[[
    The client module Volt 0.1.0 generated from Sharded.volt, as an entry
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
local Shard1 = require("./ClientShard1")
local Shard2 = require("./ClientShard2")
local Shard3 = require("./ClientShard3")

export type Team = "Red" | "Blue"
export type Stack = { item: string, quantity: number }
export type Save = { version: number, stacks: { Stack } }

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

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x6F746C80,
	scope = "Sharded",
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
		[1] = { name = "Sync", kind = "event", mode = "SingleSync", queue = 64, read = Shard2.readSync },
		[2] = { name = "Inventory.Patch", kind = "event", mode = "SingleAsync", queue = 64, read = Shard2.readInventory_Patch },
		[3] = { name = "Inventory.Transfer", kind = "reply", timeout = 10, read = Shard2.readInventory_Transfer },
		[4] = { name = "Echo", kind = "reply", timeout = 10, read = Shard3.readEcho },
	},

	outgoing = {
		[1] = { name = "Input", kind = "event", reliable = false, minBytes = 3, maxBytes = 3 },
		[2] = { name = "Ready", kind = "event", reliable = true, minBytes = 1, maxBytes = 1 },
		[3] = { name = "Sync", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[4] = { name = "Inventory.Transfer", kind = "call", reliable = true, minBytes = 8, maxBytes = 39 },
		[5] = { name = "Inventory.Picked", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[6] = { name = "Echo", kind = "call", reliable = true, minBytes = 4, maxBytes = 4 },
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
