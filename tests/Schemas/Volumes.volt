option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

event Volumes {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: Ray, b: Ray<i16(-2048..2048), q16(-512..512)>, c: Region3, d: Region3<q16(-4096..4096)>),
}
