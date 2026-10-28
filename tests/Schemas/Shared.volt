option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

enum Kind { Info, Warn, Error }

type Commands = struct { name: string(1..16), type: u8 }[0..8]

event Line {
	from: Server, type: Reliable, call: SingleSync,
	data: (kind: Kind, text: string(0..64)),
}

event Submit {
	from: Client, type: Reliable, call: SingleSync,
	data: Commands,
}

function Run {
	data: Commands,
	return: (kind: Kind, text: string(0..64)),
}
