--[[
    Types shared across the runtime: the transport a runtime drives, the
    schema table a generated module hands to Volt.start, the failure
    handler, the hooks, a bot, the limits and buckets, and the runtime's
    instance type, its fields and the methods each of its files defines
--]]

--!strict
local Send = require("./Send")

type State = Send.State

-- The send side's own, named here too for every file that reaches them through the runtime's types
export type Fire = Send.Fire
export type Record = Send.Record
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
}

export type Message = {
	name: string,
	kind: string, -- event, call or reply
	mode: string?, -- An event's call mode
	queue: number?, -- An event's queue depth
	rate: number?, -- What the server allows a player a second; absent for unlimited, and on the client
	timeout: number?, -- A reply's: the seconds a call waits for it
	promise: any?, -- A reply's: the promise library, when the function yields one
	read: Reader,
	reply: ((slot: number, status: number, ...any) -> ())?, -- A call's: what writes its reply
}

export type Outgoing = {
	name: string,
	kind: string, -- event, call or reply
	reliable: boolean,
	minBytes: number,
	maxBytes: number,
}

export type Schema = {
	version: string,
	hash: number,
	scope: string,
	side: string, -- client or server
	idBytes: number, -- How wide an incoming message id is
	promise: any?, -- The promise library, on a client with a function that yields one
	options: { [string]: any },
	messages: { [number]: Message },
	outgoing: { [number]: Outgoing },
}

export type Bucket = { tokens: number, last: number } -- What a player spends one of per packet or message, refilled at the rate a second

export type Callback = (player: any) -> () -- What a game or a package hears a join, a leave or a handshake on

-- What the server keeps per player or bot: their send states, counters and rate buckets, whether they have handshaken
export type Joined = {
	reliable: State,
	unreliable: State,
	stats: Stats,
	packets: Bucket,
	buckets: { [number]: Bucket },
	handshaken: boolean,
	warned: { [string]: number },
}

export type Entry = { n: number, [number]: any } -- A queued message: the player, then its values

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

-- A call in flight: when it fails, and what settles it, gone once it has been settled
export type Pending = { deadline: number, settle: ((ok: boolean, ...any) -> ())? }

-- What the client keeps per function: its calls in flight by slot, the slots freed for reuse and the highest given
export type Call = {
	name: string,
	timeout: number,
	promise: any?, -- The promise library, when the function yields one
	pending: { [number]: Pending },
	free: { number },
	last: number,
}

export type Fields = {
	reliable: Send.Send,
	unreliable: Send.Send,
	frame: number,
	before: { [number]: Hook? },
	beforeSend: (name: string, hook: Hook?) -> (),
	afterReceive: (name: string?, hook: Hook?) -> (),
	rate: (name: string, perSecond: number, burst: number?) -> (),
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
}

export type Own = {
	write: (self: Runtime, id: number, write: (...any) -> (), ...any) -> (),
	broadcast: (self: Runtime, id: number, targets: { [any]: any }?, except: any?, write: (...any) -> (), ...any) -> (),
	flush: (self: Runtime) -> (),
}

export type Calls = {
	functions: (self: Runtime, messages: { [number]: Message }) -> (),
	invoke: (self: Runtime, id: number, write: (slot: number, ...any) -> (), ...any) -> ...any,
	reply: (self: Runtime, id: number, slot: number, cursor: number, sideCursor: number, ...any) -> (number, number),
	handle: (self: Runtime, id: number, handler: (...any) -> ...any) -> () -> (),
	_serve: (self: Runtime, id: number, player: any, slot: number, handler: (...any) -> ...any, ...any) -> (),
	_reply: (self: Runtime, id: number, player: any, slot: number, status: number, ...any) -> (),
	_release: (self: Runtime, id: number, slot: number, ok: boolean, ...any) -> (),
	_sweep: (self: Runtime) -> (),

	refused: (
		self: Runtime,
		id: number,
		slot: number,
		packet: buffer,
		cursor: number,
		sideCursor: number,
		length: number
	) -> (number, number),

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
	target: (self: Runtime, player: any) -> boolean,
	onJoin: (self: Runtime, callback: Callback) -> () -> (),
	onLeave: (self: Runtime, callback: Callback) -> () -> (),
	onHandshake: (self: Runtime, callback: Callback) -> () -> (),
	traffic: (self: Runtime, player: any) -> (number, number),
	_join: (self: Runtime, player: any) -> (),
	_leave: (self: Runtime, player: any) -> (),
	_announce: (self: Runtime, bucket: { [{}]: Callback }, player: any) -> (),
}

export type Receive = {
	channels: (self: Runtime, messages: { [number]: Message }) -> (),
	packet: (self: Runtime, player: any, packet: any, side: any) -> (),
	deliver: (self: Runtime, id: number, player: any, cursor: number, sideCursor: number, ...any) -> (number, number),
	on: (self: Runtime, id: number, listener: (...any) -> ()) -> () -> (),
	iter: (self: Runtime, id: number) -> () -> ...any,
	_trace: (message: any) -> string,
	_push: (self: Runtime, channel: Channel, player: any, ...any) -> (),
}

export type Wrapper = {
	guard: (self: Runtime, id: number, player: any, ...any) -> boolean,
	encode: (self: Runtime, name: string, write: (...any) -> (), value: any) -> (buffer, { any }?),
	decode: (self: Runtime, read: (...any) -> (number, number, any), packet: buffer, side: { any }?) -> any,
	_beforeSend: (self: Runtime, name: string, hook: Hook?) -> (),
	_afterReceive: (self: Runtime, name: string?, hook: Hook?) -> (),
	_rate: (self: Runtime, name: string, perSecond: number, burst: number?) -> (),
}

export type Runtime = Fields & Own & Calls & Limits & Players & Receive & Wrapper

return {}
