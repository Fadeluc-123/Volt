--[[
    The Volt runtime: the engine every generated module drives. It moves
    bytes between the send states and the transport, hands each incoming
    message to its reader and its listeners, and knows nothing about any
    type; the schema table a module hands to start tells it the rest
--]]

--!strict
local Runtime = {} :: any
Runtime.__index = Runtime

local Calls = require("@self/Calls")
local Mock = require("@self/Mock")
local Receive = require("@self/Receive")
local Remotes = require("@self/Remotes")
local Send = require("@self/Send")
local Types = require("@self/Config/Types/Runtime")

local SERVER: string = "server" -- The one target a client's sends go to

export type Mock = Mock.Mock
export type Schema = Types.Schema
export type Spawn = Types.Spawn
export type Transport = Types.Transport
export type Failure = (player: any, kind: string, detail: string) -> ()

export type Runtime = {
	reliable: Send.Send,
	unreliable: Send.Send,
	frame: number,
	target: (self: Runtime, player: any) -> boolean,
	deliver: (self: Runtime, id: number, player: any, cursor: number, sideCursor: number, ...any) -> (number, number),
	on: (self: Runtime, id: number, listener: (...any) -> ()) -> () -> (),
	iter: (self: Runtime, id: number) -> () -> ...any,
	invoke: (self: Runtime, id: number, write: (slot: number, ...any) -> (), ...any) -> ...any,
	handle: (self: Runtime, id: number, handler: (...any) -> ...any) -> () -> (),
	reply: (self: Runtime, id: number, slot: number, cursor: number, sideCursor: number, ...any) -> (number, number),
	
	call: (
		self: Runtime,
		id: number,
		player: any,
		slot: number,
		cursor: number,
		sideCursor: number,
		...any
	) -> (number, number),
	
	refused: (
		self: Runtime,
		id: number,
		slot: number,
		packet: buffer,
		cursor: number,
		sideCursor: number,
		length: number
	) -> (number, number),

	packet: (self: Runtime, player: any, packet: any, side: any) -> (),
	flush: (self: Runtime) -> (),
	fail: (self: Runtime, player: any, kind: string, detail: string) -> (),
	onFailure: (self: Runtime, handler: Failure) -> (),
}

type State = Send.State

local Volt = {
	version = "0.1.0", -- Shared with the compiler; a schema from another major or minor is refused at start
}

-- The failure handler a runtime starts with: a warning per failure, except a fire at a player who left
local function report(player: any, kind: string, detail: string)
	if kind == "departed" then
		return
	end

	local from: string = player and ` from {player.Name}` or ""
	warn(`Volt: {kind} failure{from}: {detail}`)
end

--[[
    Starts a runtime for a generated module's schema table over the real
    remotes, or over the transport handed in, which is how the mock and
    the tests drive it. A schema from another compiler version is refused
    here rather than on the wire
--]]

function Volt.start(schema: Schema, transport: Transport?): Runtime
	local compiled: string? = schema.version:match("^%d+%.%d+")
	local expected: string? = Volt.version:match("^%d+%.%d+")

	assert(
		compiled == expected,
		`Volt: the schema was compiled by Volt {schema.version} and the runtime is {Volt.version}`
	)

	local options: { [string]: any } = schema.options
	local server: boolean = schema.side == "server"
	local live: Transport = transport or Remotes.open(schema.scope, server)

	local self = setmetatable({
		reliable = Send.new(live.reliable),
		unreliable = Send.new(live.unreliable, options.unreliableBudget),
		frame = 0, -- Counts Heartbeats, which is how a sync listener that yields across one is caught
		_messages = schema.messages,
		_idBytes = schema.idBytes,
		_readId = schema.idBytes == 2 and buffer.readu16 or buffer.readu8,
		_spawn = live.spawn,
		_inert = live.inert == true, -- Outside a running game, where a call would never be answered
		_players = {} :: { [any]: { reliable: State, unreliable: State } },
		_handlers = {} :: { [number]: (...any) -> ...any }, -- The server's handler per function, by the call's id
		_failure = report :: Failure,
	}, Runtime)

	self:channels(schema.messages)
	self:functions(schema.messages)

	if server then
		local players, added, removing = live.players, live.playerAdded, live.playerRemoving

		assert(players and added and removing, "Volt: a server runtime needs a transport with players")

		-- Players present before the module loaded get their states like everyone who joins after
		for _, player in players() do
			self:_join(player)
		end

		added(function (player: any)
			self:_join(player)
		end)

		removing(function (player: any)
			self:_leave(player)
		end)
	else
		self.reliable.current = self.reliable:add(SERVER)
		self.unreliable.current = self.unreliable:add(SERVER)
	end

	live.receive(function (player: any, packet: buffer, side: { any }?)
		self:packet(player, packet, side)
	end)

	-- Every frame counts for the yield check; every flush-th one sends, unless the game flushes by hand
	local every: number = options.flush
	local manual: boolean = options.manualReplication

	live.heartbeat(function ()
		self.frame += 1

		if not manual and self.frame % every == 0 then
			self:flush()
		end
	end)

	return self :: any
end

-- An in-memory transport pair for tests, over the scheduler handed in
function Volt.mock(spawn: Spawn): Mock
	return Mock.new(spawn)
end

--[[
    Points both sends at a player's states before a fire writes, or at
    the scratch states when no player is given, which is where a
    broadcast is written before it is copied. False for a player who has
    left, so the fire writes nothing and nothing is kept for them
--]]

function Runtime:target(player: any): boolean
	if player == nil then
		self.reliable.current = self.reliable.scratch
		self.unreliable.current = self.unreliable.scratch
		return true
	end

	local states = self._players[player]
	if not states then
		self:fail(player, "departed", "fired at a player who has left")
		return false
	end

	self.reliable.current = states.reliable
	self.unreliable.current = states.unreliable

	return true
end

-- Fails the calls past their deadline, then sends every target's accumulated bytes; the Heartbeat does this every flush-th frame
function Runtime:flush()
	self:_sweep()
	self.reliable:flush()
	self.unreliable:flush()
end

function Runtime:fail(player: any, kind: string, detail: string)
	self._failure(player, kind, detail)
end

-- Replaces the failure handler for every kind; the one a runtime starts with warns
function Runtime:onFailure(handler: Failure)
	self._failure = handler
end

-- States for a player who joined; one already known keeps what they have
function Runtime:_join(player: any)
	if self._players[player] then
		return
	end

	self._players[player] = { reliable = self.reliable:add(player), unreliable = self.unreliable:add(player) }
end

-- Frees a player's states, so nothing is sent to or kept for a player who left
function Runtime:_leave(player: any)
	self._players[player] = nil
	self.reliable:remove(player)
	self.unreliable:remove(player)
end

-- The receive side and the calls are the methods of one sibling each, and a name defined twice is a bug
for _, part in { Calls, Receive } do
	for name: string, method in part do
		assert(Runtime[name] == nil, `Runtime.{name} is defined twice`)
		Runtime[name] = method
	end
end

return Volt
