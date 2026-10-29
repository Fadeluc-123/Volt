--[[
    The Volt runtime: the engine every generated module drives. It moves
    bytes between the send states and the transport, hands each incoming
    message to its reader and its listeners, and knows nothing about any
    type; the schema table a module hands to start tells it the rest
--]]

--!strict
local Runtime = {}
Runtime.__index = Runtime

local Calls = require("@self/Calls")
local Limits = require("@self/Limits")
local Mock = require("@self/Mock")
local Players = require("@self/Players")
local Receive = require("@self/Receive")
local Remotes = require("@self/Remotes")
local Send = require("@self/Send")
local Traffic = require("@self/Traffic")
local Types = require("@self/Config/Types/Runtime")
local Wrapper = require("@self/Wrapper")

local SERVER: string = "server" -- The one target a client's sends go to
local MAX_OUTGOING: string = "maxOutgoing" -- The caps a dropped message's failure names
local MAX_PACKET: string = "maxPacket"

export type Bot = Types.Bot
export type Failure = Types.Failure
export type Hook = Types.Hook
export type Mock = Mock.Mock
export type Schema = Types.Schema
export type Spawn = Types.Spawn
export type Stats = Types.Stats
export type Transport = Types.Transport

export type Runtime = {
	reliable: Send.Send,
	unreliable: Send.Send,
	frame: number,
	before: { [number]: Hook }, -- The hook before a send, by the id of the message sent
	beforeSend: (name: string, hook: Hook?) -> (),
	afterReceive: (name: string?, hook: Hook?) -> (),
	rate: (name: string, perSecond: number, burst: number?) -> (),
	isBot: (value: any) -> boolean,
	target: (self: Runtime, player: any) -> boolean,
	write: (self: Runtime, id: number, write: (...any) -> (), ...any) -> (),
	broadcast: (self: Runtime, id: number, targets: { [any]: any }?, except: any?, write: (...any) -> (), ...any) -> (),
	encode: (self: Runtime, name: string, write: (...any) -> (), value: any) -> (buffer, { any }?),
	decode: (self: Runtime, read: (...any) -> (number, number, any), packet: buffer, side: { any }?) -> any,
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
	fail: (self: Runtime, player: any, kind: string, detail: string, name: string?) -> (),
	onFailure: (self: Runtime, handler: Failure) -> Failure,
	stats: (self: Runtime, player: any) -> Stats,
	onJoin: (self: Runtime, callback: (player: any) -> ()) -> () -> (),
	onLeave: (self: Runtime, callback: (player: any) -> ()) -> () -> (),
	onHandshake: (self: Runtime, callback: (player: any) -> ()) -> () -> (),
	traffic: (self: Runtime, player: any) -> (number, number),
}

type Call = Types.Call
type Callback = Types.Callback
type Channel = Types.Channel
type Fields = Types.Fields
type Joined = Types.Joined
type Limit = Types.Limit
type Outgoing = Types.Outgoing
type Self = Types.Runtime

local Volt = {
	version = "0.1.0", -- Shared with the compiler; a schema from another major or minor is refused at start
}

--[[
    Starts a runtime for a generated module's schema table over the real
    remotes, or over the transport handed in, which is how the mock and
    the tests drive it. A schema from another compiler version is refused
    here, named by its scope, rather than on the wire
--]]

function Volt.start(schema: Schema, transport: Transport?): Runtime
	local compiled: string? = schema.version:match("^%d+%.%d+")
	local expected: string? = Volt.version:match("^%d+%.%d+")

	if compiled ~= expected then
		error(
			`Volt: {schema.scope}'s schema was compiled by Volt {schema.version} and the runtime is {Volt.version}`,
			0
		)
	end

	local options: { [string]: any } = schema.options
	local server: boolean = schema.side == "server"
	local live: Transport = transport or Remotes.open(schema.scope, server)
	local stats: Stats = Limits.fresh()
	local self: Self -- The runtime, which the closures below call into once it is made

	-- A message a target's frame has no room for is dropped and reported; the client's one target is nobody to name
	local function dropping(cap: string): (target: any) -> ()
		local detail: string = `over {cap}, a message was dropped`

		return function (target: any)
			self:fail(server and target or nil, "outgoing", detail)
		end
	end

	-- The client's reliable frame must also fit what the server reads, or the server drops all of it
	local maxOutgoing: number = options.maxOutgoing
	local reliableCap: number = server and maxOutgoing or math.min(maxOutgoing, options.maxPacket)
	local reliableName: string = reliableCap < maxOutgoing and MAX_PACKET or MAX_OUTGOING

	local fields: Fields = {
		reliable = Send.new(live.reliable, stats, dropping(reliableName), reliableCap),
		unreliable = Send.new(live.unreliable, stats, dropping(MAX_OUTGOING), maxOutgoing, options.unreliableBudget),
		frame = 0, -- Counts Heartbeats, which is how a sync listener that yields across one is caught
		before = {} :: { [number]: Hook? }, -- The hook before a send, by the id of the message sent

		-- What a game registers hooks and rates through: plain functions, as the generated API hands them out
		beforeSend = function (name: string, hook: Hook?)
			self:_beforeSend(name, hook)
		end,

		afterReceive = function (name: string?, hook: Hook?)
			self:_afterReceive(name, hook)
		end,

		rate = function (name: string, perSecond: number, burst: number?)
			self:_rate(name, perSecond, burst)
		end,

		_messages = schema.messages,
		_outgoing = schema.outgoing,
		_checked = options.writeValidation ~= false, -- Whether the module's writers check their values before a byte is written
		_server = server,
		_idBytes = schema.idBytes,
		_readId = schema.idBytes == 2 and buffer.readu16 or buffer.readu8,
		_hash = schema.hash,
		_maxPacket = options.maxPacket,
		_maxPackets = options.maxPacketsPerSecond,
		_spawn = live.spawn,
		_inert = live.inert == true, -- Outside a running game, where a call would never be answered
		_now = 0, -- The clock when the last packet arrived, which the buckets its messages spend from refill to
		_reading = nil :: number?, -- The id of the message the receive loop is on, which names a decode failure
		_players = {} :: { [any]: Joined },
		_left = setmetatable({}, { __mode = "k" }) :: any, -- Players this runtime let go, never set up again
		_present = live.present, -- Whether the transport lists a player, which a fire before Volt's own join reads
		_record = live.traffic or Traffic.records(), -- Each player's byte count, the VM's when a hub serves the transport
		_joins = {} :: { [{}]: Callback }, -- The callbacks of each kind a game or a package subscribed, by a token each
		_leaves = {} :: { [{}]: Callback },
		_handshakes = {} :: { [{}]: Callback },
		_accepted = {} :: { any }, -- Whose handshakes were accepted and not yet announced, in the order read
		_handlers = {} :: { [number]: (...any) -> ...any }, -- The server's handler per function, by the call's id

		-- The runtime's own failure handler until a game replaces it, a plain function so onFailure can hand it on
		_failure = function (player: any, kind: string, detail: string)
			self:_report(player, kind, detail)
		end,

		_stats = stats,
		_warned = {} :: { [string]: number }, -- When the runtime's own handler last warned of each kind on the client
		_channels = {} :: { [number]: Channel }, -- The dispatch state of every incoming event, by id
		_calls = {} :: { [number]: Call }, -- Every function this side calls, by the id its replies arrive with
		_limits = {} :: { [number]: Limit }, -- The limit of every incoming message that has one, which rate may change
		_after = {} :: { [number]: Hook? }, -- The hook after a receive, by id, and over every message at 0
		_hooked = false, -- Whether any hook is registered on the receive side, so an unhooked receive asks nothing
	}

	-- Through a typed local, since a local assigned straight from a cast would be read as any from here on
	local runtime: Self = setmetatable(fields, Runtime) :: any
	self = runtime

	self:channels(schema.messages)
	self:functions(schema.messages)
	self:limits(schema.messages)

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
		self.reliable.current = self.reliable:add(SERVER, Limits.fresh())
		self.unreliable.current = self.unreliable:add(SERVER, Limits.fresh())

		self:handshake(schema.hash)
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

	-- The public Runtime lists no fields, so neither checker takes the instance as one
	return self :: any
end

-- An in-memory transport pair for tests, over the scheduler handed in
function Volt.mock(spawn: Spawn): Mock
	return Mock.new(spawn)
end

-- A bot that every server runtime of the VM sets up as a player, those started later included; never on a client
function Volt.addBot(name: string): Bot
	return Remotes.hub():add(name)
end

-- Takes a bot away from every runtime, each hearing it leave as a player does
function Volt.removeBot(bot: Bot)
	Remotes.hub():remove(bot)
end

-- The client side of one scope for a bot, which a harness starts a client runtime on to send as the bot
function Volt.connectBot(bot: Bot, scope: string): Transport
	return Remotes.hub():connect(bot, scope)
end

--[[
    Fires a message the way a module built without write validation does:
    its writer runs under pcall, so a value that raises part way through,
    in a buffer write or a field of the wrong kind, leaves nothing of its
    message behind and reaches whoever fired named for the message
--]]

function Runtime.write(self: Self, id: number, write: (...any) -> (), ...: any)
	local ok: boolean, message: any = pcall(write, ...)
	if ok then
		return
	end

	local row: Outgoing = self._outgoing[id]
	local send: Send.Send = row.reliable and self.reliable or self.unreliable

	error(send:undo(row.name, message), 0)
end

--[[
    Writes a message once, to the scratch states, and copies it to every
    target, or to those listed or set, or to all but one, unless the hook
    before its send vetoes it. Every broadcast variant of the generated
    API is this one call with the message's writer and its arguments
--]]

function Runtime.broadcast(
	self: Self,
	id: number,
	targets: { [any]: any }?,
	except: any?,
	write: (...any) -> (),
	...: any
)
	local hook: Hook? = self.before[id]
	if hook and not hook(targets, ...) then
		return
	end

	-- One listed or set whom the transport lists and this runtime has not set up yet is set up first, as a fire does
	local present: ((player: any) -> boolean)? = self._present

	if targets and present then
		for key: any, value: any in targets do
			local player: any = typeof(key) == "number" and value or key

			if not self._players[player] and present(player) then
				self:_join(player)
			end
		end
	end

	self:target(nil)

	-- An unchecked writer that raised would leave the scratch state dirty for the next broadcast
	if self._checked then
		write(...)
	else
		self:write(id, write, ...)
	end

	local send: Send.Send = self._outgoing[id].reliable and self.reliable or self.unreliable
	send:broadcast(targets, except)
end

--[[
    Fails the calls past their deadline, sends every target's accumulated
    bytes with each send's drops reported, then announces every handshake
    accepted before it began, in the order read, for each player still
    here; the Heartbeat does this every flush-th frame
--]]

function Runtime.flush(self: Self)
	local accepted: { any }? = nil

	-- Taken first, so a handshake accepted while this runs is left for a later flush and nobody is announced twice
	if self._accepted[1] ~= nil then
		accepted = self._accepted
		self._accepted = {}
	end

	self:_sweep()
	self.reliable:flush()
	self.unreliable:flush()

	if accepted then
		for _, player: any in accepted do
			if self._players[player] then
				self:_announce(self._handshakes, player)
			end
		end
	end
end

local _: Types.Own, _: Types.Calls, _: Types.Limits, _: Types.Players, _: Types.Receive, _: Types.Wrapper =
	Runtime, Calls, Limits, Players, Receive, Wrapper

-- The receive side, the calls, the limits, the players and the wrapper's hooks are a sibling each; a name defined twice is a bug
local parts: { any } = { Calls, Limits, Players, Receive, Wrapper }

for _, part in parts do
	for name: string, method in part do
		assert(Runtime[name] == nil, `Runtime.{name} is defined twice`)
		Runtime[name] = method
	end
end

return Volt
