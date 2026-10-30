--[[
    The server module Volt 0.1.0 generated from Functions.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

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
local refuseReliable: (string) -> never

local function readEcho(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Echo: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local value: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	return runtime:call(1, player, slot, cursor, sideCursor, value)
end

local function writeEcho(slot: number, status: number, value: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 1)
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

local function readPing(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Ping: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	cursor += 2

	return runtime:call(2, player, slot, cursor, sideCursor)
end

local function writePing(slot: number, status: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)
end

local function readDivide(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 18 > length then
		error("Divide: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local dividend: number = buffer.readf64(packet, cursor + 2)

	if dividend ~= dividend then
		error("Divide.dividend: out of range")
	end

	local divisor: number = buffer.readf64(packet, cursor + 10)

	if divisor ~= divisor then
		error("Divide.divisor: out of range")
	end

	cursor += 18

	return runtime:call(3, player, slot, cursor, sideCursor, dividend, divisor)
end

local function writeDivide(slot: number, status: number, ok: boolean, quotient: number?)
	local offset: number, out: buffer = beginReliable(13)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)
	offset += 4

	if status == 0 then
		local flags: number = 0

		if type(ok) ~= "boolean" then
			refuseReliable("Divide.ok: expected boolean")
		end

		flags += ok and 1 or 0
		flags += quotient ~= nil and 2 or 0
		buffer.writeu8(out, offset, flags)
		offset += 1

		if quotient ~= nil then
			if type(quotient) ~= "number" or quotient ~= quotient then
				refuseReliable("Divide.quotient: expected f64")
			end

			buffer.writef64(out, offset, quotient)
			offset += 8
		end
	end

	trimReliable(offset)
end

local function readInventory_Transfer(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 6 > length then
		error("Inventory.Transfer: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local source: number = buffer.readu8(packet, cursor + 2)
	local destination: number = buffer.readu8(packet, cursor + 3)
	local quantity: number = buffer.readu16(packet, cursor + 4)
	cursor += 6

	return runtime:call(4, player, slot, cursor, sideCursor, source, destination, quantity)
end

local function writeInventory_Transfer(slot: number, status: number, ok: boolean, reason: string?)
	local offset: number, out: buffer = beginReliable(70)
	buffer.writeu8(out, offset, 4)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)
	offset += 4

	if status == 0 then
		local flags: number = 0

		if type(ok) ~= "boolean" then
			refuseReliable("Inventory.Transfer.ok: expected boolean")
		end

		flags += ok and 1 or 0
		flags += reason ~= nil and 2 or 0
		buffer.writeu8(out, offset, flags)
		offset += 1

		if reason ~= nil then
			if type(reason) ~= "string" then
				refuseReliable("Inventory.Transfer.reason: expected string")
			end

			if #reason > 64 then
				refuseReliable("Inventory.Transfer.reason: length out of range")
			end

			buffer.writeu8(out, offset, #reason)
			offset += 1
			buffer.writestring(out, offset, reason)
			offset += #reason
		end
	end

	trimReliable(offset)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x16939E15,
	scope = "Functions",
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
		[1] = { name = "Echo", kind = "call", rate = 60, read = readEcho, reply = writeEcho },
		[2] = { name = "Ping", kind = "call", rate = 60, read = readPing, reply = writePing },
		[3] = { name = "Divide", kind = "call", rate = 60, read = readDivide, reply = writeDivide },
		[4] = { name = "Inventory.Transfer", kind = "call", read = readInventory_Transfer, reply = writeInventory_Transfer },
	},

	outgoing = {
		[1] = { name = "Echo", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
		[2] = { name = "Ping", kind = "reply", reliable = true, minBytes = 4, maxBytes = 262 },
		[3] = { name = "Divide", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
		[4] = { name = "Inventory.Transfer", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
allocateReliable = runtime.reliable.allocate
refuseReliable = runtime.reliable.refuse

local Network = {
	Echo = table.freeze({
		on = function (handler: (player: Player | Bot, value: number) -> (number)): () -> ()
			return runtime:handle(1, handler)
		end,
	}) :: ServerFunction<(number), (number)>,

	Ping = table.freeze({
		on = function (handler: (player: Player | Bot) -> ()): () -> ()
			return runtime:handle(2, handler)
		end,
	}) :: ServerFunction<(), ()>,

	Divide = table.freeze({
		on = function (handler: (player: Player | Bot, dividend: number, divisor: number) -> (boolean, number?)): () -> ()
			return runtime:handle(3, handler)
		end,
	}) :: ServerFunction<(number, number), (boolean, number?)>,

	Inventory = table.freeze({
		Transfer = table.freeze({
			on = function (handler: (player: Player | Bot, source: number, destination: number, quantity: number) -> (boolean, string?)): () -> ()
				return runtime:handle(4, handler)
			end,
		}) :: ServerFunction<(number, number, number), (boolean, string?)>,
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

Network.events = table.freeze({}) :: { [string]: any }

Network.functions = table.freeze({
	["Echo"] = Network.Echo,
	["Ping"] = Network.Ping,
	["Divide"] = Network.Divide,
	["Inventory.Transfer"] = Network.Inventory.Transfer,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
