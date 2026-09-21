option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

event Frames {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: CFrame, b: CFrame<f32, i16>, c: AlignedCFrame<q16(-512..512)>, d: CFrame<i16(-1000..1000), q8(-3.2..3.2)>),
}
