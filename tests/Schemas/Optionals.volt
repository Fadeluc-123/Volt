option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

type Reference = string(1..8)

export enum Team { Red, Blue }

event Optionals {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: u8?, b: string(0..8)?, c: struct { n: u8 }?, d: boolean?, e: Reference?),
}

event Nested {
	from: Client, type: Reliable, call: SingleSync,
	data: struct { grid: u8[2][2], slots: struct { id: u8, tag: Team? }[0..3]? },
}
