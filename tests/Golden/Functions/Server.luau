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

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local allocateReliable: (number) -> (number, buffer)
local refuseReliable: (string) -> ()

local function readEcho(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
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

		if typeof(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
			refuseReliable("Echo: expected u8")
		end

		buffer.writeu8(out_2, offset_2, value)
	end
end

local function readPing(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
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

local function readDivide(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
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
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)

	if status == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)
		local flags: number = 0

		if typeof(ok) ~= "boolean" then
			refuseReliable("Divide.ok: expected boolean")
		end

		flags += ok and 1 or 0
		flags += quotient ~= nil and 2 or 0
		buffer.writeu8(out_2, offset_2, flags)

		if quotient ~= nil then
			local offset_3: number, out_3: buffer = allocateReliable(8)

			if typeof(quotient) ~= "number" or quotient ~= quotient then
				refuseReliable("Divide.quotient: expected f64")
			end

			buffer.writef64(out_3, offset_3, quotient)
		end
	end
end

local function readInventory_Transfer(player: Player?, packet: buffer, cursor: number, _, sideCursor: number, length: number): (number, number)
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
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 4)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)

	if status == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)
		local flags: number = 0

		if typeof(ok) ~= "boolean" then
			refuseReliable("Inventory.Transfer.ok: expected boolean")
		end

		flags += ok and 1 or 0
		flags += reason ~= nil and 2 or 0
		buffer.writeu8(out_2, offset_2, flags)

		if reason ~= nil then
			local offset_3: number, out_3: buffer = allocateReliable(1)

			if typeof(reason) ~= "string" then
				refuseReliable("Inventory.Transfer.reason: expected string")
			end

			if #reason > 64 then
				refuseReliable("Inventory.Transfer.reason: length out of range")
			end

			buffer.writeu8(out_3, offset_3, #reason)
			local reasonOffset: number, reasonOut: buffer = allocateReliable(#reason)
			buffer.writestring(reasonOut, reasonOffset, reason)
		end
	end
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x2D03F5D0,
	scope = "Functions",
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
		[1] = { name = "Echo", kind = "call", rate = 60, read = readEcho, reply = writeEcho },
		[2] = { name = "Ping", kind = "call", rate = 60, read = readPing, reply = writePing },
		[3] = { name = "Divide", kind = "call", rate = 60, read = readDivide, reply = writeDivide },
		[4] = { name = "Inventory.Transfer", kind = "call", read = readInventory_Transfer, reply = writeInventory_Transfer },
	},

	outgoing = {
		[1] = { name = "Echo", reliable = true, minBytes = 5, maxBytes = 262 },
		[2] = { name = "Ping", reliable = true, minBytes = 4, maxBytes = 262 },
		[3] = { name = "Divide", reliable = true, minBytes = 5, maxBytes = 262 },
		[4] = { name = "Inventory.Transfer", reliable = true, minBytes = 5, maxBytes = 262 },
	},
})

beginReliable = runtime.reliable.begin
allocateReliable = runtime.reliable.allocate
refuseReliable = runtime.reliable.refuse

local net = table.freeze({
	Echo = table.freeze({
		on = function (handler: (player: Player, value: number) -> (number)): () -> ()
			return runtime:handle(1, handler)
		end,
	}),

	Ping = table.freeze({
		on = function (handler: (player: Player) -> ()): () -> ()
			return runtime:handle(2, handler)
		end,
	}),

	Divide = table.freeze({
		on = function (handler: (player: Player, dividend: number, divisor: number) -> (boolean, number?)): () -> ()
			return runtime:handle(3, handler)
		end,
	}),

	Inventory = table.freeze({
		Transfer = table.freeze({
			on = function (handler: (player: Player, source: number, destination: number, quantity: number) -> (boolean, string?)): () -> ()
				return runtime:handle(4, handler)
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
