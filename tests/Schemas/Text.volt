option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

-- An unbounded text reaches past the default maxPacket, which a client's reliable message must fit
option maxPacket = 131072

-- Text in a struct named twice, so its shared pair checks it for every message that carries one
struct Note { title: string.utf8(1..16), body: string.utf8(0..64) }

event Text {
	from: Client, type: Reliable, call: SingleSync,
	data: (short: string.utf8(1..4), exact: string.utf8(4), free: string.utf8),
}

event Notes {
	from: Client, type: Reliable, call: SingleSync,
	data: (tags: { [string.utf8(1..8)]: u8 }(0..4), first: Note, second: Note),
}
