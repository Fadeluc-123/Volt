option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

export enum Team { Red, Blue }

event Tables {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: { [u8]: string(0..4) }(0..8), b: set<string(1..4)>(0..8), c: { [Team]: u16 }(0..2), d: set<u8>(3)),
}
