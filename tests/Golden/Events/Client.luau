--[[
    The client module Volt 0.1.0 generated from Events.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type ClientEvent<A...> = { fire: (A...) -> () }

export type ClientListener<A...> = {
	on: (listener: (A...) -> ()) -> () -> (),
	iter: () -> () -> (number, A...),
}

export type ClientFunction<A..., R...> = { invoke: (A...) -> (boolean, R...) }

export type ClientPromise<A...> = { invoke: (A...) -> any }

export type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local allocateReliable: (number) -> (number, buffer)
local slotReliable: (any) -> ()
local refuseReliable: (string) -> never
local beginUnreliable: (number) -> (number, buffer)
local refuseUnreliable: (string) -> never
local markUnreliable: () -> ()

local function writeInput(dir: number, jump: boolean)
	local offset: number, out: buffer = beginUnreliable(3)
	buffer.writeu8(out, offset, 1)
	local flags: number = 0

	if typeof(dir) ~= "number" or dir % 1 ~= 0 or dir < 0 or dir > 8 then
		refuseUnreliable("Input.dir: expected u8(0..8)")
	end

	buffer.writeu8(out, offset + 2, dir)

	if typeof(jump) ~= "boolean" then
		refuseUnreliable("Input.jump: expected boolean")
	end

	flags += jump and 1 or 0
	buffer.writeu8(out, offset + 1, flags)
	markUnreliable()
end

local function writeChat(value: string)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 2)

	if typeof(value) ~= "string" then
		refuseReliable("Chat: expected string")
	end

	if #value > 64 then
		refuseReliable("Chat: length out of range")
	end

	buffer.writeu8(out, offset + 1, #value)
	local valueOffset: number, valueOut: buffer = allocateReliable(#value)
	buffer.writestring(valueOut, valueOffset, value)
end

local function writeReady()
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 3)
end

local function writeGrab(value: Instance)
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 4)

	if typeof(value) ~= "Instance" then
		refuseReliable("Grab: expected Instance")
	end

	slotReliable(value)
end

local function writePing(value: number)
	local offset: number, out: buffer = beginReliable(5)
	buffer.writeu8(out, offset, 5)

	if typeof(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 4294967295 then
		refuseReliable("Ping: expected u32")
	end

	buffer.writeu32(out, offset + 1, value)
end

local function writeSync(value: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 6)

	if typeof(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
		refuseReliable("Sync: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function readSync(player: Player?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Sync: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(1, player, cursor, sideCursor, value)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x88701285,
	scope = "Events",
	side = "client",
	idBytes = 1,
	options = {
		flush = 1,
		manualReplication = false,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
	},

	messages = {
		[1] = { name = "Sync", kind = "event", mode = "SingleSync", queue = 64, read = readSync },
	},

	outgoing = {
		[1] = { name = "Input", kind = "event", reliable = false, minBytes = 3, maxBytes = 3 },
		[2] = { name = "Chat", kind = "event", reliable = true, minBytes = 2, maxBytes = 66 },
		[3] = { name = "Ready", kind = "event", reliable = true, minBytes = 1, maxBytes = 1 },
		[4] = { name = "Grab", kind = "event", reliable = true, minBytes = 1, maxBytes = 1 },
		[5] = { name = "Ping", kind = "event", reliable = true, minBytes = 5, maxBytes = 5 },
		[6] = { name = "Sync", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
	},
})

beginReliable = runtime.reliable.begin
allocateReliable = runtime.reliable.allocate
slotReliable = runtime.reliable.slot
refuseReliable = runtime.reliable.refuse
beginUnreliable = runtime.unreliable.begin
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark

local before: { [number]: Volt.Hook } = runtime.before

local net = {
	Input = table.freeze({
		fire = function (dir: number, jump: boolean)
			if before[1] == nil or before[1](nil, dir, jump) then
				writeInput(dir, jump)
			end
		end,
	}),

	Chat = table.freeze({
		fire = function (value: string)
			if before[2] == nil or before[2](nil, value) then
				writeChat(value)
			end
		end,
	}),

	Ready = table.freeze({
		fire = function ()
			if before[3] == nil or before[3](nil) then
				writeReady()
			end
		end,
	}),

	Grab = table.freeze({
		fire = function (value: Instance)
			if before[4] == nil or before[4](nil, value) then
				writeGrab(value)
			end
		end,
	}),

	Ping = table.freeze({
		fire = function (value: number)
			if before[5] == nil or before[5](nil, value) then
				writePing(value)
			end
		end,
	}),

	Sync = table.freeze({
		fire = function (value: number)
			if before[6] == nil or before[6](nil, value) then
				writeSync(value)
			end
		end,

		on = function (listener: (value: number) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, number)
			return runtime:iter(1)
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
	["Input"] = net.Input,
	["Chat"] = net.Chat,
	["Ready"] = net.Ready,
	["Grab"] = net.Grab,
	["Ping"] = net.Ping,
	["Sync"] = net.Sync,
})

net.functions = table.freeze({})
net.exports = table.freeze({})

return table.freeze(net)
