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
local Promise = require(ReplicatedStorage.Packages.Promise)

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local refuseReliable: (string) -> ()

local function writeEcho(slot: number, value: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 1)
	buffer.writeu16(out, offset + 1, slot)

	if typeof(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
		refuseReliable("Echo: expected u8")
	end

	buffer.writeu8(out, offset + 3, value)
end

local function readEcho(_, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
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

		return runtime:reply(1, slot, cursor, sideCursor, value)
	end

	return runtime:refused(1, slot, packet, cursor, sideCursor, length)
end

local function writePing(slot: number)
	local offset: number, out: buffer = beginReliable(3)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)
end

local function readPing(_, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Ping: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		return runtime:reply(2, slot, cursor, sideCursor)
	end

	return runtime:refused(2, slot, packet, cursor, sideCursor, length)
end

local function writeDivide(slot: number, dividend: number, divisor: number)
	local offset: number, out: buffer = beginReliable(19)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)

	if typeof(dividend) ~= "number" or dividend ~= dividend then
		refuseReliable("Divide.dividend: expected f64")
	end

	buffer.writef64(out, offset + 3, dividend)

	if typeof(divisor) ~= "number" or divisor ~= divisor then
		refuseReliable("Divide.divisor: expected f64")
	end

	buffer.writef64(out, offset + 11, divisor)
end

local function readDivide(_, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
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
		local quotient
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

		return runtime:reply(3, slot, cursor, sideCursor, bit32.btest(flags, 1), quotient)
	end

	return runtime:refused(3, slot, packet, cursor, sideCursor, length)
end

local function writeInventory_Transfer(slot: number, source: number, destination: number, quantity: number)
	local offset: number, out: buffer = beginReliable(7)
	buffer.writeu8(out, offset, 4)
	buffer.writeu16(out, offset + 1, slot)

	if typeof(source) ~= "number" or source % 1 ~= 0 or source < 0 or source > 255 then
		refuseReliable("Inventory.Transfer.source: expected u8")
	end

	buffer.writeu8(out, offset + 3, source)

	if typeof(destination) ~= "number" or destination % 1 ~= 0 or destination < 0 or destination > 255 then
		refuseReliable("Inventory.Transfer.destination: expected u8")
	end

	buffer.writeu8(out, offset + 4, destination)

	if typeof(quantity) ~= "number" or quantity % 1 ~= 0 or quantity < 0 or quantity > 65535 then
		refuseReliable("Inventory.Transfer.quantity: expected u16")
	end

	buffer.writeu16(out, offset + 5, quantity)
end

local function readInventory_Transfer(_, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
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
		local reason
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

		return runtime:reply(4, slot, cursor, sideCursor, bit32.btest(flags, 1), reason)
	end

	return runtime:refused(4, slot, packet, cursor, sideCursor, length)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x2D03F5D0,
	scope = "Functions",
	side = "client",
	idBytes = 1,
	promise = Promise,
	options = {
		flush = 1,
		manualReplication = false,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		unreliableBudget = 900,
	},

	messages = {
		[1] = { name = "Echo", kind = "reply", timeout = 10, read = readEcho },
		[2] = { name = "Ping", kind = "reply", timeout = 10, read = readPing },
		[3] = { name = "Divide", kind = "reply", timeout = 2, read = readDivide },
		[4] = { name = "Inventory.Transfer", kind = "reply", timeout = 10, promise = Promise, read = readInventory_Transfer },
	},

	outgoing = {
		[1] = { name = "Echo", reliable = true, minBytes = 4, maxBytes = 4 },
		[2] = { name = "Ping", reliable = true, minBytes = 3, maxBytes = 3 },
		[3] = { name = "Divide", reliable = true, minBytes = 19, maxBytes = 19 },
		[4] = { name = "Inventory.Transfer", reliable = true, minBytes = 7, maxBytes = 7 },
	},
})

beginReliable = runtime.reliable.begin
refuseReliable = runtime.reliable.refuse

local net = table.freeze({
	Echo = table.freeze({
		invoke = function (value: number)
			return runtime:invoke(1, writeEcho, value)
		end,
	}),

	Ping = table.freeze({
		invoke = function ()
			return runtime:invoke(2, writePing)
		end,
	}),

	Divide = table.freeze({
		invoke = function (dividend: number, divisor: number)
			return runtime:invoke(3, writeDivide, dividend, divisor)
		end,
	}),

	Inventory = table.freeze({
		Transfer = table.freeze({
			invoke = function (source: number, destination: number, quantity: number)
				return runtime:invoke(4, writeInventory_Transfer, source, destination, quantity)
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
