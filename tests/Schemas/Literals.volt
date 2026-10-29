option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

-- Literals in a struct named twice, so its shared pair reads them back into a table typed as the struct
struct Hit { kind: "melee", damage: u16, version: 2, critical: boolean, ranked: true }

event Hits {
	from: Client, type: Reliable, call: SingleSync,
	data: (first: Hit, second: Hit),
}

-- An optional literal is one presence bit, and a literal member one value of its union's tag
event Choices {
	from: Client, type: Reliable, call: SingleSync,
	data: (tag: "melee"?, reason: u8 | "none"),
}
