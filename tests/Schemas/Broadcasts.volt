option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

struct Hit { target: u16, amount: u8 }

event Damage {
	from: Server, type: Reliable, call: SingleSync,
	data: Hit,
}

event Spray {
	from: Server, type: Unreliable, call: ManyAsync,
	data: (x: u8, y: u8),
}

namespace Match {
	event Start {
		from: Server, type: Reliable, call: Polling,
	}
}
