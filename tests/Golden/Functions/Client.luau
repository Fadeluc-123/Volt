--[[
    The client module Volt 0.1.0 generated from Functions.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)
local Promise: any = require(ReplicatedStorage.Packages.Promise)

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
local beginReliable: (number) -> (number, buffer)
local refuseReliable: (string) -> never

local function writeEcho(slot: number, value: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 1)
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

		return runtime:reply(1, player, slot, cursor, sideCursor, value)
	end

	return runtime:refused(1, player, slot, status, packet, cursor, sideCursor, length)
end

local function writePing(slot: number)
	local offset: number, out: buffer = beginReliable(3)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)
end

local function readPing(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Ping: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		return runtime:reply(2, player, slot, cursor, sideCursor)
	end

	return runtime:refused(2, player, slot, status, packet, cursor, sideCursor, length)
end

local function writeDivide(slot: number, dividend: number, divisor: number)
	local offset: number, out: buffer = beginReliable(19)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)

	if type(dividend) ~= "number" or dividend ~= dividend then
		refuseReliable("Divide.dividend: expected f64")
	end

	buffer.writef64(out, offset + 3, dividend)

	if type(divisor) ~= "number" or divisor ~= divisor then
		refuseReliable("Divide.divisor: expected f64")
	end

	buffer.writef64(out, offset + 11, divisor)
end

local function readDivide(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Divide: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("Divide: truncated")
		end

		local flags: number = buffer.readu8(packet, cursor)
		local quotient: number?
		cursor += 1

		if bit32.btest(flags, 2) then
			if cursor + 8 > length then
				error("Divide.quotient: truncated")
			end

			local quotient_2: number = buffer.readf64(packet, cursor)

			if quotient_2 ~= quotient_2 then
				error("Divide.quotient: out of range")
			end

			cursor += 8
			quotient = quotient_2
		end

		return runtime:reply(3, player, slot, cursor, sideCursor, bit32.btest(flags, 1), quotient)
	end

	return runtime:refused(3, player, slot, status, packet, cursor, sideCursor, length)
end

local function writeInventory_Transfer(slot: number, source: number, destination: number, quantity: number)
	local offset: number, out: buffer = beginReliable(7)
	buffer.writeu8(out, offset, 4)
	buffer.writeu16(out, offset + 1, slot)

	if type(source) ~= "number" or bit32.band(source, 255) ~= source then
		refuseReliable("Inventory.Transfer.source: expected u8")
	end

	buffer.writeu8(out, offset + 3, source)

	if type(destination) ~= "number" or bit32.band(destination, 255) ~= destination then
		refuseReliable("Inventory.Transfer.destination: expected u8")
	end

	buffer.writeu8(out, offset + 4, destination)

	if type(quantity) ~= "number" or bit32.band(quantity, 65535) ~= quantity then
		refuseReliable("Inventory.Transfer.quantity: expected u16")
	end

	buffer.writeu16(out, offset + 5, quantity)
end

local function readInventory_Transfer(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Inventory.Transfer: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("Inventory.Transfer: truncated")
		end

		local flags: number = buffer.readu8(packet, cursor)
		local reason: string?
		cursor += 1

		if bit32.btest(flags, 2) then
			if cursor + 1 > length then
				error("Inventory.Transfer.reason: truncated")
			end

			local reasonLength: number = buffer.readu8(packet, cursor)

			if reasonLength > 64 then
				error("Inventory.Transfer.reason: length out of range")
			end

			cursor += 1

			if cursor + reasonLength > length then
				error("Inventory.Transfer.reason: truncated")
			end

			local reason_2: string = buffer.readstring(packet, cursor, reasonLength)
			cursor += reasonLength
			reason = reason_2
		end

		return runtime:reply(4, player, slot, cursor, sideCursor, bit32.btest(flags, 1), reason)
	end

	return runtime:refused(4, player, slot, status, packet, cursor, sideCursor, length)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x16939E15,
	scope = "Functions",
	side = "client",
	idBytes = 1,
	promise = Promise,
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
		[1] = { name = "Echo", kind = "reply", timeout = 10, read = readEcho },
		[2] = { name = "Ping", kind = "reply", timeout = 10, read = readPing },
		[3] = { name = "Divide", kind = "reply", timeout = 2, read = readDivide },
		[4] = { name = "Inventory.Transfer", kind = "reply", timeout = 10, promise = Promise, read = readInventory_Transfer },
	},

	outgoing = {
		[1] = { name = "Echo", kind = "call", reliable = true, minBytes = 4, maxBytes = 4 },
		[2] = { name = "Ping", kind = "call", reliable = true, minBytes = 3, maxBytes = 3 },
		[3] = { name = "Divide", kind = "call", reliable = true, minBytes = 19, maxBytes = 19 },
		[4] = { name = "Inventory.Transfer", kind = "call", reliable = true, minBytes = 7, maxBytes = 7 },
	},
})

beginReliable = runtime.reliable.begin
refuseReliable = runtime.reliable.refuse

local Network = {
	Echo = table.freeze({
		invoke = function (value: number): (boolean, number)
			return runtime:invoke(1, writeEcho, value)
		end,
	}) :: ClientFunction<(number), (number)>,

	Ping = table.freeze({
		invoke = function (): (boolean)
			return runtime:invoke(2, writePing)
		end,
	}) :: ClientFunction<(), ()>,

	Divide = table.freeze({
		invoke = function (dividend: number, divisor: number): (boolean, boolean, number?)
			return runtime:invoke(3, writeDivide, dividend, divisor)
		end,
	}) :: ClientFunction<(number, number), (boolean, number?)>,

	Inventory = table.freeze({
		Transfer = table.freeze({
			invoke = function (source: number, destination: number, quantity: number)
				return runtime:invoke(4, writeInventory_Transfer, source, destination, quantity)
			end,
		}) :: ClientPromise<(number, number, number)>,
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

Network.events = table.freeze({}) :: { [string]: any }

Network.functions = table.freeze({
	["Echo"] = Network.Echo,
	["Ping"] = Network.Ping,
	["Divide"] = Network.Divide,
	["Inventory.Transfer"] = Network.Inventory.Transfer,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
