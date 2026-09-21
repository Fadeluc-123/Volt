option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

enum Team { Red, Blue }

event Enums {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: Team, b: enum { X }, c: enum "kind" { Move { dx: i8, dy: i8 }, Stop, Say { text: string(0..16) } }, d: Team | enum { Green }),
}
