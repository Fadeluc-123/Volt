option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

type Health = u8(0..100)

event Flags {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: boolean, b: u8, c: boolean, d: boolean),
}

event Bytes {
	from: Client, type: Reliable, call: SingleSync,
	data: (name: string(1..32), tag: string(4), raw: buffer(0..1024), fixed: buffer(2), free: string, health: Health),
}

event Value {
	from: Client, type: Reliable, call: SingleSync,
	data: u16,
}

event Empty {
	from: Client, type: Reliable, call: SingleSync,
}
