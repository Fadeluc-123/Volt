--[[
    The client module Volt 0.1.0 generated from Prompts.volt: a writer per
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

export type ClientEvent<A...> = { fire: (A...) -> () }

export type ClientListener<A...> = {
	on: (listener: (A...) -> ()) -> () -> (),
	iter: () -> () -> (number, A...),
}

export type ClientPolling<A...> = { iter: () -> () -> (number, A...) }

export type ClientFunction<A..., R...> = { invoke: (A...) -> (boolean, R...) }

export type ClientPromise<A...> = { invoke: (A...) -> any }

export type ClientHandler<A..., R...> = {
	on: (handler: (A...) -> R...) -> () -> (),
	connected: () -> boolean,
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

local function writeProgress(value: number)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 1)

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseReliable("Progress: expected u8")
	end

	buffer.writeu8(out, offset + 1, value)
end

local function readConfirm(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 4 > length then
		error("Confirm: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local titleLength: number = 1 + buffer.readu8(packet, cursor + 2)

	if titleLength > 64 then
		error("Confirm.title: length out of range")
	end

	local seconds: number = buffer.readu8(packet, cursor + 3)
	cursor += 4

	if cursor + titleLength > length then
		error("Confirm.title: truncated")
	end

	local title: string = buffer.readstring(packet, cursor, titleLength)
	cursor += titleLength

	return runtime:call(1, player, slot, cursor, sideCursor, title, seconds)
end

local function writeConfirm(slot: number, status: number, accepted: boolean, note: string?)
	local offset: number, out: buffer = beginReliable(70)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)
	offset += 4

	if status == 0 then
		local flags: number = 0

		if type(accepted) ~= "boolean" then
			refuseReliable("Confirm.accepted: expected boolean")
		end

		flags += accepted and 1 or 0
		flags += note ~= nil and 2 or 0
		buffer.writeu8(out, offset, flags)
		offset += 1

		if note ~= nil then
			if type(note) ~= "string" then
				refuseReliable("Confirm.note: expected string")
			end

			if #note > 64 then
				refuseReliable("Confirm.note: length out of range")
			end

			buffer.writeu8(out, offset, #note)
			offset += 1
			buffer.writestring(out, offset, note)
			offset += #note
		end
	end

	trimReliable(offset)
end

local function readPoke(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Poke: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	cursor += 2

	return runtime:call(2, player, slot, cursor, sideCursor)
end

local function writePoke(slot: number, status: number)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)
end

local function readCamera_Aim(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Camera.Aim: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	cursor += 2

	return runtime:call(3, player, slot, cursor, sideCursor)
end

local function writeCamera_Aim(slot: number, status: number, value: Vector3)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 4)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)

	if status == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(12)

		if typeof(value) ~= "Vector3" then
			refuseReliable("Camera.Aim: expected Vector3")
		end

		local valueX = value.X

		if valueX ~= valueX then
			refuseReliable("Camera.Aim.X: expected f32")
		end

		buffer.writef32(out_2, offset_2, valueX)
		local valueY = value.Y

		if valueY ~= valueY then
			refuseReliable("Camera.Aim.Y: expected f32")
		end

		buffer.writef32(out_2, offset_2 + 4, valueY)
		local valueZ = value.Z

		if valueZ ~= valueZ then
			refuseReliable("Camera.Aim.Z: expected f32")
		end

		buffer.writef32(out_2, offset_2 + 8, valueZ)
	end
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xE2BDCD27,
	scope = "Prompts",
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
		[1] = { name = "Confirm", kind = "call", read = readConfirm, reply = writeConfirm },
		[2] = { name = "Poke", kind = "call", read = readPoke, reply = writePoke },
		[3] = { name = "Camera.Aim", kind = "call", read = readCamera_Aim, reply = writeCamera_Aim },
	},

	outgoing = {
		[1] = { name = "Progress", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
		[2] = { name = "Confirm", kind = "reply", reliable = true, minBytes = 5, maxBytes = 262 },
		[3] = { name = "Poke", kind = "reply", reliable = true, minBytes = 4, maxBytes = 262 },
		[4] = { name = "Camera.Aim", kind = "reply", reliable = true, minBytes = 6, maxBytes = 262 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
allocateReliable = runtime.reliable.allocate
refuseReliable = runtime.reliable.refuse

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Progress = table.freeze({
		fire = function (value: number)
			if before[1] == nil or before[1](nil, value) then
				writeProgress(value)
			end
		end,
	}) :: ClientEvent<(number)>,

	Confirm = table.freeze({
		on = function (handler: (title: string, seconds: number) -> (boolean, string?)): () -> ()
			return runtime:handle(1, handler)
		end,

		connected = function (): boolean
			return runtime:handled(1)
		end,
	}) :: ClientHandler<(string, number), (boolean, string?)>,

	Poke = table.freeze({
		on = function (handler: () -> ()): () -> ()
			return runtime:handle(2, handler)
		end,

		connected = function (): boolean
			return runtime:handled(2)
		end,
	}) :: ClientHandler<(), ()>,

	Camera = table.freeze({
		Aim = table.freeze({
			on = function (handler: () -> (Vector3)): () -> ()
				return runtime:handle(3, handler)
			end,

			connected = function (): boolean
				return runtime:handled(3)
			end,
		}) :: ClientHandler<(), (Vector3)>,
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

Network.events = table.freeze({
	["Progress"] = Network.Progress,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Confirm"] = Network.Confirm,
	["Poke"] = Network.Poke,
	["Camera.Aim"] = Network.Camera.Aim,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
