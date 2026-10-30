option clientOutput = "Client.luau"
option serverOutput = "Server.luau"
option typesOutput = "Types.luau"

-- Each field a block of its own, sent only to a player whose last vitals held another value there
struct Vitals {
	health: u8,
	stamina: u8(0..100),
	title: string(0..16),
	held: u16?,
	gear: struct { shield: boolean, boots: boolean },
}

@delta event vitals {
	from: Server, type: Reliable, call: SingleAsync,
	data: Vitals,
}

-- Polled, with its struct written in place
@delta event zone {
	from: Server, type: Reliable, call: Polling,
	data: struct { id: u16, safe: boolean },
}
