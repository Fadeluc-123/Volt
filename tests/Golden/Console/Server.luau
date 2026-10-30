--[[
    The server module Volt 0.1.0 generated from Console.volt: a writer per
    message this side sends, a reader per message it hears, the schema
    table the runtime starts from and the API a game calls. Generated code:
    change the schema and run volt again rather than editing this file
--]]

--!strict
--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Volt = require(ReplicatedStorage.Packages.Volt)

export type Decree_Kind = "Info" | "Warn" | "Error"
type Decree_Line = string

type Bot = Volt.Bot

type ServerEvent<A...> = {
	fire: (player: Player | Bot, A...) -> (),
	fireAll: (A...) -> (),
	fireList: (players: { Player | Bot }, A...) -> (),
	fireExcept: (player: Player | Bot, A...) -> (),
	fireSet: (players: { [Player | Bot]: true }, A...) -> (),
}

type ServerListener<A...> = {
	on: (listener: (player: Player | Bot, A...) -> ()) -> () -> (),
	iter: () -> () -> (number, Player | Bot, A...),
}

type ServerPolling<A...> = { iter: () -> () -> (number, Player | Bot, A...) }

type ServerFunction<A..., R...> = {
	on: (handler: (player: Player | Bot, A...) -> R...) -> () -> (),
}

type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

local runtime: Volt.Runtime
local beginReliable: (number) -> (number, buffer)
local allocateReliable: (number) -> (number, buffer)
local slotReliable: (any) -> ()
local refuseReliable: (string) -> never

local DECREE_KIND: { "Info" | "Warn" | "Error" } = { "Info", "Warn", "Error" }

local function writeDecree_Line(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(2)

	if type(value) ~= "string" then
		refuse("Decree.Line: expected string")
	end

	if #value > 16384 then
		refuse("Decree.Line: length out of range")
	end

	buffer.writeu16(out, offset, #value)

	if utf8.len(value) == nil then
		refuse("Decree.Line: invalid UTF-8")
	end

	local valueOffset: number, valueOut: buffer = allocate(#value)
	buffer.writestring(valueOut, valueOffset, value)
end

local function writeDecree_Kind(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(1)
	local flags: number = 0
	local valueIndex: number = table.find(DECREE_KIND, value) or 0

	if valueIndex == 0 then
		refuse("Decree.Kind: expected enum { Info, Warn, Error }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)
end

local function writeDecree_line(text: Decree_Line, kind: Decree_Kind)
	local offset: number, out: buffer = beginReliable(1)
	buffer.writeu8(out, offset, 1)
	writeDecree_Line(allocateReliable, slotReliable, refuseReliable, text)
	writeDecree_Kind(allocateReliable, slotReliable, refuseReliable, kind)
end

local function readDecree_run(player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
	if cursor + 4 > length then
		error("Decree.run: truncated")
	end

	local slot: number = buffer.readu16(packet, cursor)
	local textLength: number = 1 + buffer.readu16(packet, cursor + 2)

	if textLength > 4096 then
		error("Decree.run.text: length out of range")
	end

	cursor += 4

	if cursor + textLength > length then
		error("Decree.run.text: truncated")
	end

	local text: string = buffer.readstring(packet, cursor, textLength)
	cursor += textLength

	if utf8.len(text) == nil then
		error("Decree.run.text: invalid UTF-8")
	end

	return runtime:call(1, player, slot, cursor, sideCursor, text)
end

local function writeDecree_run(slot: number, status: number, text: Decree_Line, kind: Decree_Kind)
	local offset: number, out: buffer = beginReliable(4)
	buffer.writeu8(out, offset, 2)
	buffer.writeu16(out, offset + 1, slot)
	buffer.writeu8(out, offset + 3, status)

	if status == 0 then
		writeDecree_Line(allocateReliable, slotReliable, refuseReliable, text)
		writeDecree_Kind(allocateReliable, slotReliable, refuseReliable, kind)
	end
end

runtime = Volt.start({
	version = "0.1.0",
	hash = 0x72A12928,
	scope = "Console",
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
		[1] = { name = "Decree.run", kind = "call", rate = 60, read = readDecree_run, reply = writeDecree_run },
	},

	outgoing = {
		[1] = { name = "Decree.line", kind = "event", reliable = true, minBytes = 4, maxBytes = 16388 },
		[2] = { name = "Decree.run", kind = "reply", reliable = true, minBytes = 6, maxBytes = 16391 },
	},
})

beginReliable = runtime.reliable.begin
allocateReliable = runtime.reliable.allocate
slotReliable = runtime.reliable.slot
refuseReliable = runtime.reliable.refuse

local before: { [number]: Volt.Hook } = runtime.before

local Network = {
	Decree = table.freeze({
		line = table.freeze({
			fire = function (player: Player | Bot, text: Decree_Line, kind: Decree_Kind)
				if (before[1] == nil or before[1](player, text, kind)) and runtime:target(player) then
					writeDecree_line(text, kind)
				end
			end,

			fireAll = function (text: Decree_Line, kind: Decree_Kind)
				runtime:broadcast(1, nil, nil, writeDecree_line, text, kind)
			end,

			fireList = function (players: { Player | Bot }, text: Decree_Line, kind: Decree_Kind)
				runtime:broadcast(1, players, nil, writeDecree_line, text, kind)
			end,

			fireExcept = function (player: Player | Bot, text: Decree_Line, kind: Decree_Kind)
				runtime:broadcast(1, nil, player, writeDecree_line, text, kind)
			end,

			fireSet = function (players: { [Player | Bot]: true }, text: Decree_Line, kind: Decree_Kind)
				runtime:broadcast(1, players, nil, writeDecree_line, text, kind)
			end,
		}) :: ServerEvent<(Decree_Line, Decree_Kind)>,

		run = table.freeze({
			on = function (handler: (player: Player | Bot, text: string) -> (Decree_Line, Decree_Kind)): () -> ()
				return runtime:handle(1, handler)
			end,
		}) :: ServerFunction<(string), (Decree_Line, Decree_Kind)>,
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
	["Decree.line"] = Network.Decree.line,
}) :: { [string]: any }

Network.functions = table.freeze({
	["Decree.run"] = Network.Decree.run,
}) :: { [string]: any }

Network.exports = table.freeze({}) :: { [string]: any }

return table.freeze(Network)
