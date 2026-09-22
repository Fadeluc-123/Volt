option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

event Input {
	from: Client, type: Unreliable, call: SingleSync,
	data: (dir: u8(0..8), jump: boolean),
}

event Chat {
	from: Client, type: Reliable, call: SingleAsync,
	data: string(0..64),
}

event Ready {
	from: Client, type: Reliable, call: ManySync,
}

event Grab {
	from: Client, type: Reliable, call: ManyAsync,
	data: Instance,
}

event Ping {
	from: Client, type: Reliable, call: Polling,
	data: u32,
	rate: unlimited,
}

event Sync {
	from: Both, type: Reliable, call: SingleSync,
	data: u8,
}
