--[[
    The send side's types: the fire a packet goes out through, the counters
    and the byte count a send state counts into, the state of one target,
    and the send's instance type, its fields and the methods each of its
    files defines, one part per file
--]]

--!strict
export type Fire = (target: any, packet: buffer, side: { any }?) -> ()

-- One player's byte count, shared by every runtime of a VM: the bytes sent in each slice of the last second, and their states
export type Record = {
	slices: { number },
	stamps: { number }, -- Which slice of time each slice was last counted in
	states: { [any]: boolean }, -- The player's send states in every runtime, whose cursors are what is not yet flushed
}

export type Stats = {
	packetsIn: number,
	bytesIn: number,
	messagesIn: number,
	packetsOut: number,
	bytesOut: number,
	messagesOut: number,
	rejected: number, -- Messages a hook vetoed
	failures: { [string]: number }, -- By kind, from the first time it happens
}

export type State = {
	out: buffer,
	cursor: number,
	side: { any },
	sideCursor: number,
	marks: { number }, -- The cursor after each message, where a packet may be split
	sideMarks: { number }, -- The side cursor after each message
	committed: number, -- The cursor where the last message began, which a refusal or a drop returns to
	sideCommitted: number, -- The side cursor where it began
	target: any, -- Who the state's bytes go to; nil for the scratch state
	stats: Stats?, -- The target's counters; the scratch state has none, since a broadcast counts once per target
	record: Record?, -- The target's byte count across the VM, for a player or a bot
	held: boolean, -- Until the player's handshake: a flush keeps reliable bytes and drops unreliable ones
	refused: boolean, -- After a failed handshake: nothing is written or kept for the player again
}

export type Fields = {
	begin: (bytes: number) -> (number, buffer),
	trim: (offset: number) -> (),
	allocate: (bytes: number) -> (number, buffer),
	slot: (value: any) -> (),
	refuse: (message: string) -> never,
	mark: () -> (),
	current: State,
	scratch: State,
	_fire: Fire,
	_total: Stats,
	_dropped: (target: any) -> (),
	_cap: number,
	_budget: number,
	_keeps: boolean,
	_states: { [any]: State },
	_drops: { any },
}

export type Own = {
	add: (self: Send, target: any, stats: Stats, record: Record?, held: boolean?) -> State,
	remove: (self: Send, target: any) -> (),
	undo: (self: Send, name: string, message: any) -> string,
	drop: (self: Send) -> boolean,
}

export type Broadcast = {
	broadcast: (self: Send, targets: { [any]: any }?, except: any?) -> (),
	take: (self: Send) -> (buffer, { any }?),
	_copy: (self: Send, state: State?) -> (),
}

export type Flush = {
	flush: (self: Send) -> (),
	_discard: (self: Send, state: State) -> (),
	_tell: (self: Send) -> (),
	_send: (self: Send, target: any, state: State) -> (),
	_packet: (self: Send, target: any, state: State, from: number, to: number, sideFrom: number, sideTo: number) -> (),
}

export type Send = Fields & Own & Broadcast & Flush

return {}
