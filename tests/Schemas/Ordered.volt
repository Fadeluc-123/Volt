option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

-- Each message carries a sequence after its id, so one older than the last heard from its sender is dropped
event Aim {
	from: Both, type: OrderedUnreliable, call: SingleSync,
	data: (yaw: q16(-3.2..3.2), pitch: q16(-1.6..1.6)),
}

event Spray {
	from: Server, type: Unreliable, call: ManyAsync,
	data: u8,
}
