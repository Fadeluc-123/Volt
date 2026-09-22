option clientOutput = "../../place/Client.luau"
option serverOutput = "../../place/Server.luau"

event Ping {
	from: Client, type: Reliable, call: SingleAsync,
	data: u8,
}

event Move {
	from: Client, type: Unreliable, call: SingleSync,
	data: (x: f32, y: f32),
}

event Mark {
	from: Client, type: Reliable, call: SingleAsync,
	data: Instance,
}

event Pong {
	from: Server, type: Reliable, call: SingleAsync,
	data: u8,
}

event Moved {
	from: Server, type: Unreliable, call: SingleSync,
	data: (x: f32, y: f32),
}

function Echo {
	data: string(0..32),
	return: string(0..32),
}
