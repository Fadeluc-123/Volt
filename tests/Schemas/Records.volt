option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

struct Stack { item: string(1..8), quantity: u16(1..999), properties: unknown? }

export struct Save { version: u16, stacks: Stack[0..4] }

event Records {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: struct { x: u8, y: string(0..4), z: boolean }, b: struct {}, c: Stack, d: Save),
}
