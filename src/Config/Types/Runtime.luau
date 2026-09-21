--[[
    Types shared across the runtime: the transport a runtime drives,
    which the real remotes and the mock both provide, the schema table a
    generated module hands to Volt.start, and the messages in it
--]]

--!strict
export type Fire = (target: any, packet: buffer, side: { any }?) -> ()
export type Handler = (player: any, packet: buffer, side: { any }?) -> ()
export type Spawn = (callback: (...any) -> (), ...any) -> ...any
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
}

export type Message = {
	name: string,
	kind: string, -- event, call or reply
	mode: string?, -- An event's call mode
	queue: number?, -- An event's queue depth
	rate: number?,
	timeout: number?, -- A reply's: the seconds a call waits for it
	promise: any?, -- A reply's: the promise library, when the function yields one
	read: Reader,
	reply: ((slot: number, status: number, ...any) -> ())?, -- A call's: what writes its reply
}

export type Outgoing = {
	name: string,
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

return {}
