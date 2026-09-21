option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

event Integers {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: u8, b: u16(1..999), c: u24, d: u32, e: u48, f: u64, g: i8(-5..5), h: i16, i: i24, j: i32, k: i48, l: i64),
}

event Floats {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: f16, b: f32, c: f64(0..1), d: q8(0..1), e: q16(-3.2..3.2)),
}
