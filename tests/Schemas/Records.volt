option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

struct Stack { item: string(1..8), quantity: u16(1..999), properties: unknown? }

export struct Save { version: u16, stacks: Stack[0..4] }

event Records {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: struct { x: u8, y: string(0..4), z: boolean }, b: struct {}, c: Stack, d: Save),
}

-- Records in a run a writer holds its largest size for, each entry a block of its own, beside a run of inline entries
event Rows {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: struct { id: u8, name: string(0..4), tag: u16? }[0..3], b: u8[0..4]),
}
