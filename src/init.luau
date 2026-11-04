--[[
    Volt's root: start, which every generated module begins its runtime
    with, the members a game or a test calls, and the Runtime class that
    every sibling file's methods merge onto
--]]

--!strict
local Runtime = {}
Runtime.__index = Runtime

local Awaited = require("@self/Awaited")
local Calls = require("@self/Calls")
local Config = require("@self/Config/Runtime")
local Contract = require("@self/Config/Types/Contract")
local Delta = require("@self/Delta")
local Dictionary = require("@self/Dictionary")
local Fires = require("@self/Fires")
local Flushes = require("@self/Flushes")
local Handlers = require("@self/Handlers")
local Limits = require("@self/Limits")
local Mock = require("@self/Mock")
local Players = require("@self/Players")
local Receive = require("@self/Receive")
local Remotes = require("@self/Remotes")
local Send = require("@self/Send")
local Traffic = require("@self/Traffic")
local Types = require("@self/Config/Types/Runtime")
local Wrapper = require("@self/Wrapper")

local CHANNEL_BYTES: number = Config.channelBytes
local CLIENT_FLUSHES: number = Config.clientFlushes
local FLUSH_EARLY: number = Config.flushEarly

local SERVER: string = "server" -- The one target a client's sends go to
local MAX_OUTGOING: string = "maxOutgoing" -- The caps a dropped message's failure names
local MAX_PACKET: string = "maxPacket"
local DEFAULT_STREAM: number = 0 -- The byte the default reliable stream's and every unreliable packet open with

export type Bot = Types.Bot
export type Failure = Types.Failure
export type Hook = Types.Hook
export type Mock = Mock.Mock
export type Schema = Types.Schema
export type Spawn = Types.Spawn
export type Stats = Types.Stats
export type Transport = Types.Transport
export type Runtime = Contract.Runtime

type Call = Types.Call
type Callback = Types.Callback
type Channel = Types.Channel
type Fields = Types.Fields
type Fire = Types.Fire
type Joined = Types.Joined
type Limit = Types.Limit
type Profiler = Types.Profiler
type Self = Types.Runtime
type Waiter = Types.Waiter

--- @class Volt
--- The runtime every generated module drives. A module hands its schema
--- table to start and makes every call into the runtime it gets back, so
--- a game or a test reaches Volt itself for the version, the mock that
--- runs generated modules without Studio, and the bots a server adds

local Volt = {
	--- @prop version string
	--- @within Volt
	--- Volt's version, shared with the compiler. A schema compiled by
	--- another major or minor version is refused at start
	version = "0.1.0",
}

-- What a server writer of an awaited instance meets on a transport that keeps no instance references
local function unreferenced(_: Instance): number
	error("Volt: this transport carries no instance references", 0)
end

--- Starts a runtime for a generated module's schema table over the real
--- remotes, or over the transport handed in, which is how the mock, the
--- tests and a bot's client side drive it. A schema compiled by another
--- major or minor version of Volt errors here, named by its scope, rather
--- than failing on the wire
--- @function start
--- @within Volt
--- @param schema Schema -- The schema table a generated module hands over
--- @param transport Transport? -- In place of the real remotes: a mock's, or a bot's client side from connectBot
--- @return Runtime -- The runtime the generated module drives, which a game never calls by hand

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

	-- A message a target's frame has no room for is dropped and reported, their baselines cleared before the report;
	-- the client's one target is nobody to name
	local function dropping(cap: string): (target: any) -> ()
		local detail: string = `over {cap}, a message was dropped`

		return function (target: any)
			self:_forget(target)
			self:fail(server and target or nil, "outgoing", detail)
		end
	end

	-- In a schema with a dictionary, each packet of a player's default stream follows the entries they lack
	local fire: Fire = live.reliable

	if server and schema.dictionary then
		fire = function (target: any, packet: buffer, side: { any }?)
			self:_lead(target)
			live.reliable(target, packet, side)
		end
	end

	-- In a schema with a channel every packet opens with a byte naming its stream, and a stamped server's with the time
	local labels: { string }? = schema.streams
	local last: number? = labels and #labels -- The highest byte a packet may open with, or nil when none opens one
	local opening: number? = labels and DEFAULT_STREAM
	local stamped: boolean = schema.stamp == true
	local stamping: boolean = server and stamped
	local profiler: Profiler? = schema.profiler -- Only in a module compiled with labels

	-- The client's reliable frame, its channel byte counted, must also fit what the server reads, or it drops all of it
	local maxOutgoing: number = options.maxOutgoing
	local fits: number = options.maxPacket - (labels and CHANNEL_BYTES or 0)
	local reliableCap: number = server and maxOutgoing or math.min(maxOutgoing, fits)
	local reliableName: string = reliableCap < maxOutgoing and MAX_PACKET or MAX_OUTGOING
	local budget: number = options.unreliableBudget

	-- Each channel's own reliable send, by its number, opening its packets with that number
	local streams: { Send.Send } = {}

	for channel: number = 1, last or 0 do
		streams[channel] = Send.new(live.reliable, stats, dropping(reliableName), reliableCap, nil, channel, stamping)
	end

	local fields: Fields = {
		reliable = Send.new(fire, stats, dropping(reliableName), reliableCap, nil, opening, stamping),
		unreliable = Send.new(live.unreliable, stats, dropping(MAX_OUTGOING), maxOutgoing, budget, opening, stamping),
		streams = streams,
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

		-- What a server's writer names an awaited instance by and a client's reader finds it by, as plain functions too
		instanceId = live.reference or unreferenced,

		instanceById = function (id: number): Instance?
			return self:_lookup(id)
		end,

		-- What a server's writer takes a dictionary string's id from, a plain function too, and the entries by id
		intern = function (value: string): number
			return self:_intern(value)
		end,

		dictionary = {} :: { string }, -- The server's own, or on the client what the server has sent, never replaced

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
		_handlers = {} :: { [number]: (...any) -> ...any }, -- The handler per function this side answers, by id

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
		_lastStream = last,
		_stamped = stamped, -- Whether a server packet opens with the server time, after any channel byte
		_clock = stamping and live.now or nil, -- What a stamped server reads the time from, once per flush
		_stamp = 0, -- The server time of the packet holding the message being handled, or of the queued one handed out
		_newest = 0, -- The server time of the newest packet, which the stamp returns to once a queue is drained
		_sequences = {} :: { [number]: number }, -- On the client, the last sequence taken of each ordered event, by id
		_resolve = live.resolve, -- On the client, the instance an id names, or nil while it has not arrived
		_waiters = {} :: { Waiter }, -- The messages waiting for an instance they name, in the order they were read
		_awaited = {} :: { [number]: { Waiter } }, -- The messages waiting on each id, in the order they were read
		_missing = {} :: { number }, -- The ids the message being read found no instance for, or one held behind another
		_replaying = nil :: Waiter?, -- The waiting message being read again, which has waited its turn on every id
		_ids = {} :: { [string]: number }, -- On the server, each dictionary entry's id
		_owed = {} :: { [number]: buffer }, -- The dictionary message for each count of entries a player already holds
		_owedTo = 0, -- How many entries those messages run to, so they are built again once the dictionary grows
		_dictionaryBytes = schema.dictionary, -- How wide the dictionary message's id is, when the schema has one
		_baselines = {} :: { [number]: { [string]: any } }, -- On the client, the value each @delta event last delivered
		_profiler = profiler, -- What closes the label of a reader that raised, when the module labels its readers
	}

	-- Through a typed local, since a local assigned straight from a cast would be read as any from here on
	local runtime: Self = setmetatable(fields, Runtime) :: any
	self = runtime

	self:channels(schema.messages)
	self:functions(schema.messages)
	self:limits(schema.messages)
	self:arrivals(schema.messages, live.resolved)
	self:hear()

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

		for _, stream: Send.Send in streams do
			stream.current = stream:add(SERVER, Limits.fresh())
		end

		-- Only the default stream opens with it, and the flush sends that stream first
		self:handshake(schema.hash)
	end

	local function receive(player: any, packet: buffer, side: { any }?)
		self:packet(player, packet, side)
	end

	-- Every frame counts for the yield check. Every flush-th one sends unless the game flushes by hand, and so
	-- does any frame on which a target's unsent bytes have reached flushBytes, by hand or not. A client with a
	-- clock sends by time instead of frames, at most clientFlushes / flush times a second whatever its frame rate
	local every: number = options.flush
	local manual: boolean = options.manualReplication
	local threshold: number? = options.flushBytes
	local clock: (() -> number)? = not server and live.clock or nil -- A server counts frames, clock or not
	local interval: number = every / CLIENT_FLUSHES
	local due: number = 0 -- When the next paced flush falls due

	local function paced(): boolean
		if not clock then
			return self.frame % every == 0
		end

		local now: number = clock()
		if now < due - interval * FLUSH_EARLY then
			return false
		end

		due = math.max(due, now) + interval -- From now when late, so a hitch is followed by no burst

		return true
	end

	local function heartbeat()
		self.frame += 1

		if not manual and paced() or threshold and self:_piled(threshold) then
			self:flush()
		end
	end

	-- Labelled under the scope's name when the module asks, and otherwise handed over as they are, costing nothing
	live.receive(profiler and self._labelled(profiler, `Volt {schema.scope} receive`, receive) or receive)
	live.heartbeat(profiler and self._labelled(profiler, `Volt {schema.scope} flush`, heartbeat) or heartbeat)

	-- The public Runtime lists no fields, so neither checker takes the instance as one
	return self :: any
end

--- An in-memory transport pair for tests, which runs generated modules
--- end to end under Lune or in Studio with no remotes: its server
--- transport and each joined player's client transport are handed to
--- start, and each step delivers the queued packets in both directions
--- and then fires one Heartbeat on every runtime
--- @function mock
--- @within Volt
--- @param spawn Spawn -- The scheduler: Lune's task.spawn under the test runner, the engine's in Studio
--- @return Mock

function Volt.mock(spawn: Spawn): Mock
	return Mock.new(spawn)
end

--- Adds a bot, which every server runtime of the VM sets up as a player,
--- those started later included, and errors outside a running game. A
--- bot is a frozen table holding only its Name, with no UserId and no
--- Kick, so strict code narrows before it treats one as a Player; the
--- server module's isBot tells the two apart
--- @function addBot
--- @within Volt
--- @server
--- @param name string -- The bot's Name
--- @return Bot

function Volt.addBot(name: string): Bot
	return Remotes.hub():add(name)
end

--- Takes a bot away from every server runtime of the VM, each hearing it
--- leave as a player does, then stops its client sides and drops anything
--- queued for them or waiting from them
--- @function removeBot
--- @within Volt
--- @server
--- @param bot Bot -- A bot addBot made

function Volt.removeBot(bot: Bot)
	Remotes.hub():remove(bot)
end

--- The client side of one scope for a bot, which a harness starts a client
--- runtime on to send as the bot, through the same generated client
--- writers a player's client uses. Its fires reach the scope's server in
--- the same frame, or once that server starts when sent before it, and a
--- second connect of a bot to one scope errors
--- @function connectBot
--- @within Volt
--- @server
--- @param bot Bot -- A bot addBot made
--- @param scope string -- The scope whose server the bot's packets reach
--- @return Transport -- The bot's client transport for that scope, to hand to start

function Volt.connectBot(bot: Bot, scope: string): Transport
	return Remotes.hub():connect(bot, scope)
end

local _: Types.Awaited, _: Types.Calls, _: Types.Fires, _: Types.Flushes = Awaited, Calls, Fires, Flushes
local _: Types.Delta, _: Types.Dictionary = Delta, Dictionary
local _: Types.Handlers, _: Types.Limits, _: Types.Players = Handlers, Limits, Players
local _: Types.Receive, _: Types.Wrapper = Receive, Wrapper

-- The awaited instances, each side of a call, the baselines, the dictionary, the fires, the flush, the receive side,
-- the limits, the players and the wrapper's hooks are a sibling each, and a name defined twice is a bug
local parts: { any } =
	{ Awaited, Calls, Delta, Dictionary, Fires, Flushes, Handlers, Limits, Players, Receive, Wrapper }

for _, part in parts do
	for name: string, method in part do
		assert(Runtime[name] == nil, `Runtime.{name} is defined twice`)
		Runtime[name] = method
	end
end

return Volt
