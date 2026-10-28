--[[
    The server module Volt 0.1.0 generated from Shared.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Kind = "Info" | "Warn" | "Error"
export type Commands = { { name: string, type: number } }

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
local allocateReliable: (number) -> (number, buffer)
local slotReliable: (any) -> ()
local refuseReliable: (string) -> never

local KIND: { "Info" | "Warn" | "Error" } = { "Info", "Warn", "Error" }

local function writeKind(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(1)
	local flags: number = 0
	local valueIndex: number = table.find(KIND, value) or 0

	if valueIndex == 0 then
		refuse("Kind: expected enum { Info, Warn, Error }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)
end

local function readCommands(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Commands)
	if cursor + 1 > length then
		error("Commands: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 8 then
		error("Commands: length out of range")
	end

	cursor += 1

	if cursor + 3 * valueLength > length then
		error("Commands: truncated")
	end

	local value: { { name: string, type: number } } = table.create(valueLength) :: { { name: string, type: number } }

	for index = 1, valueLength do
		if cursor + 2 > length then
			error("Commands: truncated")
		end

		local nameLength: number = 1 + buffer.readu8(packet, cursor)

		if nameLength > 16 then
			error("Commands[].name: length out of range")
		end

		local type_2: number = buffer.readu8(packet, cursor + 1)
		cursor += 2

		if cursor + nameLength > length then
			error("Commands[].name: truncated")
		end

		local name: string = buffer.readstring(packet, cursor, nameLength)
		cursor += nameLength
		local valueEntry = { name = name, type = type_2 }
		value[index] = valueEntry
	end

	return cursor, sideCursor, value
end

local function writeLine(kind: Kind, text: string)
	local offset: number, out: buffer = beginReliable(2)
	buffer.writeu8(out, offset, 1)

	if type(text) ~= "string" then
		refuseReliable("Line.text: expected string")
	end

	if #text > 64 then
		refuseReliable("Line.text: length out of range")
	end

	buffer.writeu8(out, offset + 1, #text)
	writeKind(allocateReliable, slotReliable, refuseReliable, kind)
	local textOffset: number, textOut: buffer = allocateReliable(#text)
	buffer.writestring(textOut, textOffset, text)
end

local function readSubmit(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	local value: Commands
	cursor, sideCursor, value = readCommands(packet, cursor, side, sideCursor, length)

	return runtime:deliver(1, player, cursor, sideCursor, value)
end

local function readRun(player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 2 > length then
		error("Run: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local value: Commands
	cursor += 2
	cursor, sideCursor, value = readCommands(packet, cursor, side, sideCursor, length)

	return runtime:call(2, player, slot, cursor, sideCursor, value)
end

local function writeRun(slot: number, status: number, kind: Kind, text: string)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)

	if status == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)

		if type(text) ~= "string" then
			refuseReliable("Run.text: expected string")
		end

		if #text > 64 then
			refuseReliable("Run.text: length out of range")
		end

		buffer.writeu8(out_2, offset_2, #text)
		writeKind(allocateReliable, slotReliable, refuseReliable, kind)
		local textOffset: number, textOut: buffer = allocateReliable(#text)
		buffer.writestring(textOut, textOffset, text)
	end
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0xCA88011D,
	scope = "Shared",
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
		[1] = { name = "Submit", kind = "event", mode = "SingleSync", queue = 64, rate = 120, read = readSubmit },
		[2] = { name = "Run", kind = "call", rate = 60, read = readRun, reply = writeRun },
	},

	outgoing = {
		[1] = { name = "Line", kind = "event", reliable = true, minBytes = 3, maxBytes = 67 },
		[2] = { name = "Run", kind = "reply", reliable = true, minBytes = 6, maxBytes = 262 },
	},
})

beginReliable = runtime.reliable.begin
allocateReliable = runtime.reliable.allocate
slotReliable = runtime.reliable.slot
refuseReliable = runtime.reliable.refuse

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Line = table.freeze({
		fire = function (player: Player | Bot, kind: Kind, text: string)
			if (before[1] == nil or before[1](player, kind, text)) and runtime:target(player) then
				writeLine(kind, text)
			end
		end,

		fireAll = function (kind: Kind, text: string)
			runtime:broadcast(1, nil, nil, writeLine, kind, text)
		end,

		fireList = function (players: { Player | Bot }, kind: Kind, text: string)
			runtime:broadcast(1, players, nil, writeLine, kind, text)
		end,

		fireExcept = function (player: Player | Bot, kind: Kind, text: string)
			runtime:broadcast(1, nil, player, writeLine, kind, text)
		end,

		fireSet = function (players: { [Player | Bot]: true }, kind: Kind, text: string)
			runtime:broadcast(1, players, nil, writeLine, kind, text)
		end,
	}) :: ServerEvent<(Kind, string)>,

	Submit = table.freeze({
		on = function (listener: (player: Player | Bot, value: Commands) -> ()): () -> ()
			return runtime:on(1, listener)
		end,

		iter = function (): () -> (number, Player | Bot, Commands)
			return runtime:iter(1)
		end,
	}) :: ServerListener<(Commands)>,

	Run = table.freeze({
		on = function (handler: (player: Player | Bot, value: Commands) -> (Kind, string)): () -> ()
			return runtime:handle(2, handler)
		end,
	}) :: ServerFunction<(Commands), (Kind, string)>,

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

	isBot = runtime.isBot,
}

Network.events = table.freeze({
	["Line"] = Network.Line,
	["Submit"] = Network.Submit,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Run"] = Network.Run,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
