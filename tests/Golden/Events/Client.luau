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

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local allocateReliable: (number) -> (number, buffer)
local slotReliable: (any) -> ()
local refuseReliable: (string) -> ()
local beginUnreliable: (number) -> (number, buffer)
local refuseUnreliable: (string) -> ()
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

local function readDamage(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Damage: truncated")
	end

	local target: number = buffer.readu16(packet, cursor)
	local amount: number = buffer.readu8(packet, cursor + 2)
	cursor += 3
	local value = { target = target, amount = amount }

	return runtime:deliver(1, player, cursor, sideCursor, value)
end

local function readSpray(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Spray: truncated")
	end

	local x: number = buffer.readu8(packet, cursor)
	local y: number = buffer.readu8(packet, cursor + 1)
	cursor += 2

	return runtime:deliver(2, player, cursor, sideCursor, x, y)
end

local function writeSync(value: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 6)

	if typeof(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
		refuseReliable("Sync: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function readSync(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Sync: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(3, player, cursor, sideCursor, value)
end

local function readMatch_Start(player: Player?, _, cursor: number, _, sideCursor: number, _): (number, number)
	return runtime:deliver(4, player, cursor, sideCursor)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x4692C530,
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
		[1] = { name = "Damage", kind = "event", mode = "SingleSync", queue = 64, read = readDamage },
		[2] = { name = "Spray", kind = "event", mode = "ManyAsync", queue = 64, read = readSpray },
		[3] = { name = "Sync", kind = "event", mode = "SingleSync", queue = 64, read = readSync },
		[4] = { name = "Match.Start", kind = "event", mode = "Polling", queue = 64, read = readMatch_Start },
	},

	outgoing = {
		[1] = { name = "Input", reliable = false, minBytes = 3, maxBytes = 3 },
		[2] = { name = "Chat", reliable = true, minBytes = 2, maxBytes = 66 },
		[3] = { name = "Ready", reliable = true, minBytes = 1, maxBytes = 1 },
		[4] = { name = "Grab", reliable = true, minBytes = 1, maxBytes = 1 },
		[5] = { name = "Ping", reliable = true, minBytes = 5, maxBytes = 5 },
		[6] = { name = "Sync", reliable = true, minBytes = 2, maxBytes = 2 },
	},
})

beginReliable = runtime.reliable.begin
allocateReliable = runtime.reliable.allocate
slotReliable = runtime.reliable.slot
refuseReliable = runtime.reliable.refuse
beginUnreliable = runtime.unreliable.begin
refuseUnreliable = runtime.unreliable.refuse
markUnreliable = runtime.unreliable.mark

local net = table.freeze({
	Input = table.freeze({
		fire = writeInput,
	}),

	Chat = table.freeze({
		fire = writeChat,
	}),

	Ready = table.freeze({
		fire = writeReady,
	}),

	Grab = table.freeze({
		fire = writeGrab,
	}),

	Ping = table.freeze({
		fire = writePing,
	}),

	Damage = table.freeze({
		on = function (listener: (value: any) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, any)
			return runtime:iter(1)
		end,
	}),

	Spray = table.freeze({
		on = function (listener: (x: number, y: number) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, number, number)
			return runtime:iter(2)
		end,
	}),

	Sync = table.freeze({
		fire = writeSync,

		on = function (listener: (value: number) -> ()): () -> ()
			return runtime:on(3, listener)
		end,

		iter = function (): () -> (number, number)
			return runtime:iter(3)
		end,
	}),

	Match = table.freeze({
		Start = table.freeze({
			iter = function (): () -> (number)
				return runtime:iter(4)
			end,
		}),
	}),

	flush = function ()
		runtime:flush()
	end,

	onFailure = function (handler: Volt.Failure)
		runtime:onFailure(handler)
	end,

	stats = function (player: Player?): Volt.Stats
		return runtime:stats(player)
	end,
})

return net
