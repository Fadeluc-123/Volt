option clientOutput = "Client.luau"
option serverOutput = "Server.luau"
option stamp = true

-- A stream of its own on the scope's Reliable remote, so every packet opens with the byte naming its stream
channel Bulk

event Chat {
	from: Both, type: Reliable, call: ManySync, channel: Bulk,
	data: string(0..200),
}

-- On the default stream, as a function's call and reply are
event Notice {
	from: Server, type: Reliable, call: ManySync,
	data: u8,
}

event Tick {
	from: Server, type: Unreliable, call: Polling,
	data: u16,
}

function Ask {
	data: u8,
	return: u8,
}
