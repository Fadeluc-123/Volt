--[[
    The server module Volt 0.1.0 generated from Events.volt: a writer per
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
local allocateReliable: (number) -> (number, buffer)
local allocateUnreliable: (number) -> (number, buffer)
local markUnreliable: () -> ()

local function readInput(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Input: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local dir: number = buffer.readu8(packet, cursor + 1)

	if dir > 8 then
		error("Input.dir: out of range")
	end

	cursor += 2

	return runtime:deliver(1, player, cursor, sideCursor, dir, bit32.btest(flags, 1))
end

local function readChat(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Chat: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 64 then
		error("Chat: length out of range")
	end

	cursor += 1

	if cursor + valueLength > length then
		error("Chat: truncated")
	end

	local value: string = buffer.readstring(packet, cursor, valueLength)
	cursor += valueLength

	return runtime:deliver(2, player, cursor, sideCursor, value)
end

local function readReady(player: Player?, _, cursor: number, _, sideCursor: number, _): (number, number)
	return runtime:deliver(3, player, cursor, sideCursor)
end

local function readGrab(player: Player?, _, cursor: number, side: { any }, sideCursor: number, _): (number, number)
	local value: Instance? = side[sideCursor]
	sideCursor += 1

	if typeof(value) ~= "Instance" then
		error("Grab: expected Instance")
	end

	return runtime:deliver(4, player, cursor, sideCursor, value)
end

local function readPing(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
	if cursor + 4 > length then
		error("Ping: truncated")
	end

	local value: number = buffer.readu32(packet, cursor)
	cursor += 4

	return runtime:deliver(5, player, cursor, sideCursor, value)
end

local function writeDamage(value: any)
	local offset: number, out: buffer = allocateReliable(4)
	buffer.writeu8(out, offset, 1)

	if typeof(value) ~= "table" then
		error("Damage: expected table")
	end

	if typeof(value.target) ~= "number" or value.target % 1 ~= 0 or value.target < 0 or value.target > 65535 then
		error("Damage.target: expected u16")
	end

	buffer.writeu16(out, offset + 1, value.target)

	if typeof(value.amount) ~= "number" or value.amount % 1 ~= 0 or value.amount < 0 or value.amount > 255 then
		error("Damage.amount: expected u8")
	end

	buffer.writeu8(out, offset + 3, value.amount)
end

local function writeSpray(x: number, y: number)
	local offset: number, out: buffer = allocateUnreliable(3)
	buffer.writeu8(out, offset, 2)

	if typeof(x) ~= "number" or x % 1 ~= 0 or x < 0 or x > 255 then
		error("Spray.x: expected u8")
	end

	buffer.writeu8(out, offset + 1, x)

	if typeof(y) ~= "number" or y % 1 ~= 0 or y < 0 or y > 255 then
		error("Spray.y: expected u8")
	end

	buffer.writeu8(out, offset + 2, y)
	markUnreliable()
end

local function writeSync(value: number)
	local offset: number, out: buffer = allocateReliable(2)
	buffer.writeu8(out, offset, 3)

	if typeof(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
		error("Sync: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function readSync(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Sync: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(6, player, cursor, sideCursor, value)
end

local function writeMatch_Start()
	local offset: number, out: buffer = allocateReliable(1)
	buffer.writeu8(out, offset, 4)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x4692C530,
	scope = "Events",
	side = "server",
	idBytes = 1,
	options = {
		flush = 1,
		manualReplication = false,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
	},

	messages = {
		[1] = { name = "Input", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readInput },
		[2] = { name = "Chat", kind = "event", mode = "SingleAsync", queue = 64, rate = 120, read = readChat },
		[3] = { name = "Ready", kind = "event", mode = "ManySync", queue = 64, rate = 120, read = readReady },
		[4] = { name = "Grab", kind = "event", mode = "ManyAsync", queue = 64, rate = 120, read = readGrab },
		[5] = { name = "Ping", kind = "event", mode = "Polling", queue = 64, read = readPing },
		[6] = { name = "Sync", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readSync },
	},

	outgoing = {
		[1] = { name = "Damage", reliable = true, minBytes = 4, maxBytes = 4 },
		[2] = { name = "Spray", reliable = false, minBytes = 3, maxBytes = 3 },
		[3] = { name = "Sync", reliable = true, minBytes = 2, maxBytes = 2 },
		[4] = { name = "Match.Start", reliable = true, minBytes = 1, maxBytes = 1 },
	},
})

allocateReliable = runtime.reliable.allocate
allocateUnreliable = runtime.unreliable.allocate
markUnreliable = runtime.unreliable.mark

local net = table.freeze({
	Input = table.freeze({
		on = function (listener: (player: Player, dir: number, jump: boolean) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player, number, boolean)
			return runtime:iter(1)
		end,
	}),

	Chat = table.freeze({
		on = function (listener: (player: Player, value: string) -> ()): () -> ()
			return runtime:on(2, listener)
		end,

		iter = function (): () -> (number, Player, string)
			return runtime:iter(2)
		end,
	}),

	Ready = table.freeze({
		on = function (listener: (player: Player) -> ()): () -> ()
			return runtime:on(3, listener)
		end,

		iter = function (): () -> (number, Player)
			return runtime:iter(3)
		end,
	}),

	Grab = table.freeze({
		on = function (listener: (player: Player, value: Instance) -> ()): () -> ()
			return runtime:on(4, listener)
		end,

		iter = function (): () -> (number, Player, Instance)
			return runtime:iter(4)
		end,
	}),

	Ping = table.freeze({
		iter = function (): () -> (number, Player, number)
			return runtime:iter(5)
		end,
	}),

	Damage = table.freeze({
		fire = function (player: Player, value: any)
			if runtime:target(player) then
				writeDamage(value)
			end
		end,

		fireAll = function (value: any)
			runtime:target(nil)
			writeDamage(value)
			runtime.reliable:broadcast()
		end,

		fireList = function (players: { Player }, value: any)
			runtime:target(nil)
			writeDamage(value)
			runtime.reliable:broadcast(players)
		end,

		fireExcept = function (player: Player, value: any)
			runtime:target(nil)
			writeDamage(value)
			runtime.reliable:broadcast(nil, player)
		end,

		fireSet = function (players: { [Player]: true }, value: any)
			runtime:target(nil)
			writeDamage(value)
			runtime.reliable:broadcast(players)
		end,
	}),

	Spray = table.freeze({
		fire = function (player: Player, x: number, y: number)
			if runtime:target(player) then
				writeSpray(x, y)
			end
		end,

		fireAll = function (x: number, y: number)
			runtime:target(nil)
			writeSpray(x, y)
			runtime.unreliable:broadcast()
		end,

		fireList = function (players: { Player }, x: number, y: number)
			runtime:target(nil)
			writeSpray(x, y)
			runtime.unreliable:broadcast(players)
		end,

		fireExcept = function (player: Player, x: number, y: number)
			runtime:target(nil)
			writeSpray(x, y)
			runtime.unreliable:broadcast(nil, player)
		end,

		fireSet = function (players: { [Player]: true }, x: number, y: number)
			runtime:target(nil)
			writeSpray(x, y)
			runtime.unreliable:broadcast(players)
		end,
	}),

	Sync = table.freeze({
		fire = function (player: Player, value: number)
			if runtime:target(player) then
				writeSync(value)
			end
		end,

		fireAll = function (value: number)
			runtime:target(nil)
			writeSync(value)
			runtime.reliable:broadcast()
		end,

		fireList = function (players: { Player }, value: number)
			runtime:target(nil)
			writeSync(value)
			runtime.reliable:broadcast(players)
		end,

		fireExcept = function (player: Player, value: number)
			runtime:target(nil)
			writeSync(value)
			runtime.reliable:broadcast(nil, player)
		end,

		fireSet = function (players: { [Player]: true }, value: number)
			runtime:target(nil)
			writeSync(value)
			runtime.reliable:broadcast(players)
		end,

		on = function (listener: (player: Player, value: number) -> ()): () -> ()
			return runtime:on(6, listener)
		end,

		iter = function (): () -> (number, Player, number)
			return runtime:iter(6)
		end,
	}),

	Match = table.freeze({
		Start = table.freeze({
			fire = function (player: Player)
				if runtime:target(player) then
					writeMatch_Start()
				end
			end,

			fireAll = function ()
				runtime:target(nil)
				writeMatch_Start()
				runtime.reliable:broadcast()
			end,

			fireList = function (players: { Player })
				runtime:target(nil)
				writeMatch_Start()
				runtime.reliable:broadcast(players)
			end,

			fireExcept = function (player: Player)
				runtime:target(nil)
				writeMatch_Start()
				runtime.reliable:broadcast(nil, player)
			end,

			fireSet = function (players: { [Player]: true })
				runtime:target(nil)
				writeMatch_Start()
				runtime.reliable:broadcast(players)
			end,
		}),
	}),

	flush = function ()
		runtime:flush()
	end,

	onFailure = function (handler: Volt.Failure)
		runtime:onFailure(handler)
	end,
})

return net
