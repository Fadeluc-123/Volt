--[[
    Types shared across the runtime: the transport a runtime drives, the
    schema table a generated module hands to Volt.start, the failure
    handler, the hooks, a bot, the limits and buckets, a waiting message,
    and the runtime's instance type, its fields and each file's methods
--]]

--!strict
local Send = require("./Send")

-- The send side's own, named here too for every file that reaches them through the runtime's types
export type Fire = Send.Fire
export type Record = Send.Record
export type Send = Send.Send
export type State = Send.State
export type Stats = Send.Stats

export type Bot = { Name: string } -- A connection a harness adds that the server treats as a player; no UserId and no Kick
export type Handler = (player: any, packet: buffer, side: { any }?) -> ()
export type Spawn = (callback: (...any) -> (), ...any) -> ...any
export type Failure = (player: (Player | Bot)?, kind: string, detail: string) -> () -- Nil on the client
export type Hook = (target: any, ...any) -> boolean -- Before a send with its target, or after a receive with the player; false vetoes
export type Limit = { rate: number, burst: number } -- What a player is allowed a second, and the most they may save up
export type Reader = (
	player: any,
	packet: buffer,
	cursor: number,
	side: { any },
	sideCursor: number,
	length: number
) -> (number, number)

-- The MicroProfiler's two calls, debug's in a game, which a module compiled with labels hands the runtime
export type Profiler = { profilebegin: (label: string) -> (), profileend: () -> () }

export type Transport = {
	reliable: Fire,
	unreliable: Fire,
	receive: (handler: Handler) -> (),
	heartbeat: (callback: () -> ()) -> (),
	spawn: Spawn,
	inert: boolean?, -- Outside a running game, where nothing is sent or heard
	players: (() -> { any })?, -- The server's transport carries the player list and its two signals
	playerAdded: ((callback: (player: any) -> ()) -> ())?,
	playerRemoving: ((callback: (player: any) -> ()) -> ())?,
	present: ((player: any) -> boolean)?, -- Whether a player is listed, so a fire before Volt's own join can set them up
	traffic: ((player: any) -> Record)?, -- The player's byte count, one per VM, from the hub that serves the transport
	now: (() -> number)?, -- The server's clock, which a stamped server's packets carry
	reference: ((instance: Instance) -> number)?, -- The server's id for an instance a message names, kept for its life
	resolve: ((id: number) -> Instance?)?, -- The client's instance for an id, or nil while it has not arrived
	resolved: ((callback: (id: number) -> ()) -> ())?, -- Calls back on the client with each id whose instance arrives
}

export type Message = {
	name: string,
	kind: string, -- event, call or reply, or on a client with a dictionary the dictionary message
	mode: string?, -- An event's call mode
	queue: number?, -- An event's queue depth
	rate: number?, -- What the server allows a player a second; absent for unlimited, and on the client
	timeout: number?, -- A reply's: the seconds a call waits for it; an awaited event's: those its message waits
	promise: any?, -- A reply's: the promise library, when the function yields one
	fields: { string }?, -- A @delta event's top-level fields in declaration order, field i's bit 2^(i - 1)
	read: Reader,
	reply: ((slot: number, status: number, ...any) -> ())?, -- A call's: what writes its reply
}

export type Outgoing = {
	name: string,
	kind: string, -- event, call or reply
	reliable: boolean,
	stream: number?, -- An event on a channel: the channel's number, which picks its send
	sequence: number?, -- An ordered event: where its sequence sits in the message, after its id
	fields: { string }?, -- A @delta event's top-level fields in declaration order, field i's bit 2^(i - 1)
	minBytes: number,
	maxBytes: number,
}

export type Schema = {
	version: string,
	hash: number,
	scope: string,
	side: string, -- client or server
	idBytes: number, -- How wide an incoming message id is
	stamp: boolean?, -- Whether every server packet opens with the server time
	streams: { string }?, -- The channels' labels, by number, when the schema declares any
	dictionary: number?, -- With a @dictionary type: how wide a server-to-client id is, which the dictionary message takes
	promise: any?, -- The promise library, on a client with a function that yields one
	profiler: Profiler?, -- Only in a module compiled with labels: what each packet and each Heartbeat is labelled with
	options: { [string]: any },
	messages: { [number]: Message },
	outgoing: { [number]: Outgoing },
}

export type Bucket = { tokens: number, last: number } -- What a player spends one of per packet or message, refilled at the rate a second

export type Callback = (player: any) -> () -- What a game or a package hears a join, a leave or a handshake on

-- A call in flight: when it fails, and what settles it, gone once it has been settled
export type Pending = { deadline: number, settle: ((ok: boolean, ...any) -> ())? }

-- One caller's calls in flight through one function: by slot, the slots freed for reuse and the highest given
export type Slots = { pending: { [number]: Pending }, free: { number }, last: number }

-- What a side keeps per function it calls: its name, how long a call waits, and on the client its one slot table
export type Call = {
	name: string,
	timeout: number,
	promise: any?, -- The promise library, when the function yields one
	slots: Slots?, -- Nil on the server, which keeps a slot table per player instead
}

-- What the server keeps per player or bot: their send states, counters, rate buckets, handshake and the calls to them
export type Joined = {
	reliable: State,
	unreliable: State,
	streams: { State }, -- Their state in each channel's send, by the channel's number
	stats: Stats,
	packets: Bucket,
	buckets: { [number]: Bucket },
	sequences: { [number]: number }, -- The last sequence taken from them for each ordered event, by id
	handshaken: boolean,
	warned: { [string]: number },
	calls: { [number]: Slots },
	sent: { [number]: any }?, -- The value last written to them through each @delta event, by id, made at the first
	known: number, -- How many dictionary entries they have been sent
}

-- A queued message: the player, then its values, and the stamp of the packet it came in
export type Entry = { n: number, stamp: number, [number]: any }

-- A message waiting for an instance it names: a copy of its own bytes and slots, read again once its ids have arrived
export type Waiter = {
	id: number,
	packet: buffer,
	side: { any },
	deadline: number, -- The clock past which it is dropped as a resolve failure
	ids: { number }, -- The ids it still waits on, in the order it read them
	stamp: number, -- The server time of the packet it came in, which serverTime reads while it is delivered
}

-- What the receive side keeps per event: how it is delivered, its listeners and the queue it waits in
export type Channel = {
	name: string,
	kind: string, -- sync, async or polling
	single: boolean, -- Whether one listener is the most the event allows
	depth: number, -- How many messages the queue holds before the oldest is dropped
	listeners: { (...any) -> () },
	queue: { Entry },
	head: number,
	tail: number,
	warned: boolean, -- An overflow is reported once per event
}

export type Fields = {
	reliable: Send.Send,
	unreliable: Send.Send,
	streams: { Send.Send },
	frame: number,
	before: { [number]: Hook? },
	beforeSend: (name: string, hook: Hook?) -> (),
	afterReceive: (name: string?, hook: Hook?) -> (),
	rate: (name: string, perSecond: number, burst: number?) -> (),
	instanceId: (instance: Instance) -> number,
	instanceById: (id: number) -> Instance?,
	intern: (value: string) -> number,
	dictionary: { string },
	_messages: { [number]: Message },
	_outgoing: { [number]: Outgoing },
	_checked: boolean,
	_server: boolean,
	_idBytes: number,
	_readId: (packet: buffer, offset: number) -> number,
	_hash: number,
	_maxPacket: number,
	_maxPackets: number,
	_spawn: Spawn,
	_inert: boolean,
	_now: number,
	_reading: number?,
	_players: { [any]: Joined },
	_left: { [any]: boolean },
	_present: ((player: any) -> boolean)?,
	_record: (player: any) -> Record,
	_joins: { [{}]: Callback },
	_leaves: { [{}]: Callback },
	_handshakes: { [{}]: Callback },
	_accepted: { any },
	_handlers: { [number]: (...any) -> ...any },
	_failure: Failure,
	_stats: Stats,
	_warned: { [string]: number },
	_channels: { [number]: Channel },
	_calls: { [number]: Call },
	_limits: { [number]: Limit },
	_after: { [number]: Hook? },
	_hooked: boolean,
	_lastStream: number?,
	_stamped: boolean,
	_clock: (() -> number)?,
	_stamp: number,
	_newest: number,
	_sequences: { [number]: number },
	_resolve: ((id: number) -> Instance?)?,
	_waiters: { Waiter },
	_awaited: { [number]: { Waiter } },
	_missing: { number },
	_replaying: Waiter?,
	_ids: { [string]: number },
	_owed: { [number]: buffer },
	_owedTo: number,
	_dictionaryBytes: number?,
	_baselines: { [number]: { [string]: any } },
	_profiler: Profiler?,
}

export type Own = {
	flush: (self: Runtime) -> (),
	_piled: (self: Runtime, bytes: number) -> boolean,
}

export type Awaited = {
	arrivals: (self: Runtime, messages: { [number]: Message }, resolved: ((callback: (id: number) -> ()) -> ())?) -> (),

	await: (
		self: Runtime,
		id: number,
		packet: buffer,
		start: number,
		cursor: number,
		side: { any },
		sideStart: number,
		sideCursor: number,
		...any
	) -> (number, number),

	_lookup: (self: Runtime, id: number) -> Instance?,
	_arrive: (self: Runtime, id: number) -> (),
	_replay: (self: Runtime, waiter: Waiter) -> (),
	_expire: (self: Runtime) -> (),
}

export type Delta = {
	delta: (
		self: Runtime,
		id: number,
		player: any,
		targets: { [any]: any }?,
		except: any?,
		write: (mask: number, value: any) -> (),
		value: any
	) -> (),

	merge: (self: Runtime, id: number, mask: number, partial: { [string]: any }) -> { [string]: any },
	_forget: (self: Runtime, player: any) -> (),
}

export type Dictionary = {
	hear: (self: Runtime) -> (),
	_intern: (self: Runtime, value: string) -> number,
	_lead: (self: Runtime, target: any) -> (),
	_learn: (self: Runtime, packet: buffer, cursor: number, length: number) -> number,
}

export type Fires = {
	write: (self: Runtime, id: number, write: (...any) -> (), ...any) -> (),
	broadcast: (self: Runtime, id: number, targets: { [any]: any }?, except: any?, write: (...any) -> (), ...any) -> (),
}

export type Calls = {
	functions: (self: Runtime, messages: { [number]: Message }) -> (),
	invoke: (self: Runtime, id: number, write: (slot: number, ...any) -> (), ...any) -> ...any,
	_slots: (self: Runtime, id: number, player: any, open: boolean) -> Slots?,
	_release: (self: Runtime, id: number, player: any, slot: number, ok: boolean, ...any) -> (),
	_sweep: (self: Runtime) -> (),
	_abandon: (self: Runtime, state: Joined) -> (),

	reply: (
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
		player: any,
		slot: number,
		status: number,
		packet: buffer,
		cursor: number,
		sideCursor: number,
		length: number
	) -> (number, number),
}

export type Handlers = {
	handle: (self: Runtime, id: number, handler: (...any) -> ...any) -> () -> (),
	handled: (self: Runtime, id: number) -> boolean,
	_serve: (self: Runtime, id: number, player: any, slot: number, handler: (...any) -> ...any, ...any) -> (),
	_reply: (self: Runtime, id: number, player: any, slot: number, status: number, ...any) -> (),

	call: (
		self: Runtime,
		id: number,
		player: any,
		slot: number,
		cursor: number,
		sideCursor: number,
		...any
	) -> (number, number),
}

export type Limits = {
	fresh: () -> Stats,
	limits: (self: Runtime, messages: { [number]: Message }) -> (),
	handshake: (self: Runtime, hash: number) -> (),
	admit: (self: Runtime, player: any, packet: buffer) -> number?,
	allow: (self: Runtime, player: any, id: number, limit: Limit) -> boolean,
	stats: (self: Runtime, player: any) -> Stats,
	fail: (self: Runtime, player: any, kind: string, detail: string, name: string?) -> (),
	onFailure: (self: Runtime, handler: Failure) -> Failure,
	_limited: (self: Runtime, player: any, name: string, limit: Limit) -> (),
	_count: (self: Runtime, player: any, key: string, amount: number) -> (),
	_report: (self: Runtime, player: any, kind: string, detail: string) -> (),
}

export type Players = {
	isBot: (value: any) -> boolean,
	target: (self: Runtime, player: any, stream: number?) -> boolean,
	onJoin: (self: Runtime, callback: Callback) -> () -> (),
	onLeave: (self: Runtime, callback: Callback) -> () -> (),
	onHandshake: (self: Runtime, callback: Callback) -> () -> (),
	traffic: (self: Runtime, player: any) -> (number, number),
	_join: (self: Runtime, player: any) -> (),
	_leave: (self: Runtime, player: any) -> (),
	_setUp: (self: Runtime, targets: { [any]: any }?) -> (),
	_announce: (self: Runtime, bucket: { [{}]: Callback }, player: any) -> (),
}

export type Receive = {
	channels: (self: Runtime, messages: { [number]: Message }) -> (),
	packet: (self: Runtime, player: any, packet: any, side: any) -> (),
	deliver: (self: Runtime, id: number, player: any, cursor: number, sideCursor: number, ...any) -> (number, number),

	ordered: (
		self: Runtime,
		id: number,
		sequence: number,
		player: any,
		cursor: number,
		sideCursor: number,
		...any
	) -> (number, number),

	on: (self: Runtime, id: number, listener: (...any) -> ()) -> () -> (),
	iter: (self: Runtime, id: number) -> () -> ...any,
	serverTime: (self: Runtime) -> number,
	_trace: (message: any) -> string,
	_labelled: (profiler: Profiler, label: string, callback: (...any) -> ()) -> (...any) -> (),
	_undecoded: (self: Runtime, player: any, id: number, problem: any) -> (),
	_push: (self: Runtime, channel: Channel, player: any, ...any) -> (),
}

export type Wrapper = {
	guard: (self: Runtime, id: number, player: any, ...any) -> boolean,
	encode: (self: Runtime, name: string, write: (...any) -> (), value: any) -> (buffer, { any }?),
	decode: (self: Runtime, read: (...any) -> (number, number, any), packet: buffer, side: { any }?) -> any,
	_beforeSend: (self: Runtime, name: string, hook: Hook?) -> (),
	_afterReceive: (self: Runtime, name: string?, hook: Hook?) -> (),
	_rate: (self: Runtime, name: string, perSecond: number, burst: number?) -> (),
	budget: (self: Runtime, bytesPerSecond: number?) -> (),
}

export type Runtime =
	Fields
	& Own
	& Awaited
	& Calls
	& Delta
	& Dictionary
	& Fires
	& Handlers
	& Limits
	& Players
	& Receive
	& Wrapper

return {}
