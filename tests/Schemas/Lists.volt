option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

export struct Stack { item: string(1..8), quantity: u16(1..999), properties: unknown? }

event Lists {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: u8[0..8], b: string(0..4)[2], c: boolean[8], d: boolean[0..20], e: Stack[0..2], f: u8[]),
}
