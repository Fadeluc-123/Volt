option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

type Health = u8(0..100)

event Integers {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: u8, b: u16(1..999), c: u24, d: u32, e: u48, f: u64, g: i8(-5..5), h: i16, i: i24, j: i32, k: i48, l: i64),
}

event Floats {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: f16, b: f32, c: f64(0..1), d: q8(0..1), e: q16(-3.2..3.2)),
}

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
