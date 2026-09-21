option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

struct Hit { target: u16, amount: u8 }

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

event Damage {
	from: Server, type: Reliable, call: SingleSync,
	data: Hit,
}

event Spray {
	from: Server, type: Unreliable, call: ManyAsync,
	data: (x: u8, y: u8),
}

event Sync {
	from: Both, type: Reliable, call: SingleSync,
	data: u8,
}

namespace Match {
	event Start {
		from: Server, type: Reliable, call: Polling,
	}
}
