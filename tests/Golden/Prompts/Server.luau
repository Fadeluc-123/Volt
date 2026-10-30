--[[
    The server module Volt 0.1.0 generated from Prompts.volt: a writer per
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

export type ServerInvoke<A..., R...> = {
	invoke: (player: Player | Bot, A...) -> (boolean, R...),
}

export type ServerPromise<A...> = { invoke: (player: Player | Bot, A...) -> any }

export type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local trimReliable: (number) -> ()
local refuseReliable: (string) -> never

local function readProgress(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 1 > length then
		error("Progress: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	cursor += 1

	return runtime:deliver(1, player, cursor, sideCursor, value)
end

local function writeConfirm(slot: number, title: string, seconds: number)
	local offset: number, out: buffer = beginReliable(69)
	buffer.writeu8(out, offset, 1)
	buffer.writeu16(out, offset + 1, slot)

	if type(title) ~= "string" then
		refuseReliable("Confirm.title: expected string")
	end

	if #title < 1 or #title > 64 then
		refuseReliable("Confirm.title: length out of range")
	end

	buffer.writeu8(out, offset + 3, #title - 1)

	if type(seconds) ~= "number" or bit32.band(seconds, 255) ~= seconds then
		refuseReliable("Confirm.seconds: expected u8")
	end

	buffer.writeu8(out, offset + 4, seconds)
	offset += 5
	buffer.writestring(out, offset, title)
	offset += #title
	trimReliable(offset)
end

local function readConfirm(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Confirm: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 1 > length then
			error("Confirm: truncated")
		end

		local flags: number = buffer.readu8(packet, cursor)
		local note: string?
		cursor += 1

		if bit32.btest(flags, 2) then
			if cursor + 1 > length then
				error("Confirm.note: truncated")
			end

			local noteLength: number = buffer.readu8(packet, cursor)

			if noteLength > 64 then
				error("Confirm.note: length out of range")
			end

			cursor += 1

			if cursor + noteLength > length then
				error("Confirm.note: truncated")
			end

			local note_2: string = buffer.readstring(packet, cursor, noteLength)
			cursor += noteLength
			note = note_2
		end

		return runtime:reply(2, player, slot, cursor, sideCursor, bit32.btest(flags, 1), note)
	end

	return runtime:refused(2, player, slot, status, packet, cursor, sideCursor, length)
end

local function writePoke(slot: number)
	local offset: number, out: buffer = beginReliable(3)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)
end

local function readPoke(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Poke: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		return runtime:reply(3, player, slot, cursor, sideCursor)
	end

	return runtime:refused(3, player, slot, status, packet, cursor, sideCursor, length)
end

local function writeCamera_Aim(slot: number)
	local offset: number, out: buffer = beginReliable(3)
	buffer.writeu8(out, offset, 3)
	buffer.writeu16(out, offset + 1, slot)
end

local function readCamera_Aim(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 3 > length then
		error("Camera.Aim: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local status: number = buffer.readu8(packet, cursor + 2)
	cursor += 3

	if status == 0 then
		if cursor + 12 > length then
			error("Camera.Aim: truncated")
		end

		local valueX: number = buffer.readf32(packet, cursor)

		if valueX ~= valueX then
			error("Camera.Aim.X: out of range")
		end

		local valueY: number = buffer.readf32(packet, cursor + 4)

		if valueY ~= valueY then
			error("Camera.Aim.Y: out of range")
		end

		local valueZ: number = buffer.readf32(packet, cursor + 8)

		if valueZ ~= valueZ then
			error("Camera.Aim.Z: out of range")
		end

		local value: Vector3 = Vector3.new(valueX, valueY, valueZ)
		cursor += 12

		return runtime:reply(4, player, slot, cursor, sideCursor, value)
	end

	return runtime:refused(4, player, slot, status, packet, cursor, sideCursor, length)
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xE2BDCD27,
	scope = "Prompts",
	side = "server",
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
		[1] = { name = "Progress", kind = "event", mode = "ManySync", queue = 64, rate = 120, read = readProgress },
		[2] = { name = "Confirm", kind = "reply", timeout = 2, read = readConfirm },
		[3] = { name = "Poke", kind = "reply", timeout = 10, read = readPoke },
		[4] = { name = "Camera.Aim", kind = "reply", timeout = 10, promise = Promise, read = readCamera_Aim },
	},

	outgoing = {
		[1] = { name = "Confirm", kind = "call", reliable = true, minBytes = 6, maxBytes = 69 },
		[2] = { name = "Poke", kind = "call", reliable = true, minBytes = 3, maxBytes = 3 },
		[3] = { name = "Camera.Aim", kind = "call", reliable = true, minBytes = 3, maxBytes = 3 },
	},
})

beginReliable = runtime.reliable.begin
trimReliable = runtime.reliable.trim
refuseReliable = runtime.reliable.refuse

local Network = {
	Progress = table.freeze({
		on = function (listener: (player: Player | Bot, value: number) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player | Bot, number)
			return runtime:iter(1)
		end,
	}) :: ServerListener<(number)>,

	Confirm = table.freeze({
		invoke = function (player: Player | Bot, title: string, seconds: number): (boolean, boolean, string?)
			return runtime:invoke(2, writeConfirm, player, title, seconds)
		end,
	}) :: ServerInvoke<(string, number), (boolean, string?)>,

	Poke = table.freeze({
		invoke = function (player: Player | Bot): (boolean)
			return runtime:invoke(3, writePoke, player)
		end,
	}) :: ServerInvoke<(), ()>,

	Camera = table.freeze({
		Aim = table.freeze({
			invoke = function (player: Player | Bot)
				return runtime:invoke(4, writeCamera_Aim, player)
			end,
		}) :: ServerPromise<()>,
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
