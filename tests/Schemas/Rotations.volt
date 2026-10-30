option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

event Turn {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: QuaternionCFrame, b: QuaternionCFrame<q16(-512..512)>, c: struct { at: QuaternionCFrame<i16(-1000..1000)> }[0..8]),
}
