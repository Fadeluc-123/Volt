option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

export struct Stack { item: string(1..8), quantity: u16(1..999), properties: unknown? }

export enum Team { Red, Blue }

event Unions {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: u8 | string(0..4) | boolean, b: Vector3 | Stack, c: Color3 | u8[0..3] | Team),
}
