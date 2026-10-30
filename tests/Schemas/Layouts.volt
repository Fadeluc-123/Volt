option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

event Layouts {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: UDim2, b: UDim2<q16(0..1), i16>, c: NumberRange, d: NumberRange<u8(0..100)>, e: Rect, f: Rect<q16(0..1)>),
}
