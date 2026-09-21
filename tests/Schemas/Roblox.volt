option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

event Vectors {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: Vector3, b: Vector3<i16(-1000..1000)>, c: Vector2<q8(0..1)>, d: Vector3<u8>),
}

event Colours {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: Color3, b: BrickColor, c: DateTime, d: DateTimeMillis),
}
