--[[
    The runtime as a generated module sees it, the members the contract
    between the two names: the sends, the hooks and plain functions a
    module captures as locals, and the methods its readers, fires and API
    call. It lists no private field, so no module can reach one
--]]

--!strict
local Types = require("./Runtime")

type Failure = Types.Failure
type Hook = Types.Hook
type Send = Types.Send
type Stats = Types.Stats

export type Runtime = {
	reliable: Send,
	unreliable: Send,
	streams: { Send }, -- Each channel's reliable send, by the channel's number
	frame: number,
	before: { [number]: Hook }, -- The hook before a send, by the id of the message sent
	beforeSend: (name: string, hook: Hook?) -> (),
	afterReceive: (name: string?, hook: Hook?) -> (),
	rate: (name: string, perSecond: number, burst: number?) -> (),
	isBot: (value: any) -> boolean,
	instanceId: (instance: Instance) -> number, -- A server writer's id for an awaited instance
	instanceById: (id: number) -> Instance?, -- A client reader's awaited instance, nil while the message must wait
	intern: (value: string) -> number, -- A server writer's dictionary id for a string, or 0 when the dictionary is full
	dictionary: { string }, -- The dictionary's entries in id order, which a client reader indexes
	target: (self: Runtime, player: any, stream: number?) -> boolean,
	write: (self: Runtime, id: number, write: (...any) -> (), ...any) -> (),
	broadcast: (self: Runtime, id: number, targets: { [any]: any }?, except: any?, write: (...any) -> (), ...any) -> (),

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
	encode: (self: Runtime, name: string, write: (...any) -> (), value: any) -> (buffer, { any }?),
	decode: (self: Runtime, read: (...any) -> (number, number, any), packet: buffer, side: { any }?) -> any,
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

	on: (self: Runtime, id: number, listener: (...any) -> ()) -> () -> (),
	iter: (self: Runtime, id: number) -> () -> ...any,
	serverTime: (self: Runtime) -> number,
	invoke: (self: Runtime, id: number, write: (slot: number, ...any) -> (), ...any) -> ...any,
	handle: (self: Runtime, id: number, handler: (...any) -> ...any) -> () -> (),
	handled: (self: Runtime, id: number) -> boolean,

	call: (
		self: Runtime,
		id: number,
		player: any,
		slot: number,
		cursor: number,
		sideCursor: number,
		...any
	) -> (number, number),

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

return {}
