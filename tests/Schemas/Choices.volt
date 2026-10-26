option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

export enum Team { Red, Blue }
struct Loadout { perks: set<u8>(0..2), team: Team }

event Variants {
	from: Client, type: Reliable, call: SingleSync,
	data: enum "kind" { Join { team: Team, perks: set<u8>(0..2), floor: Enum.Material, loadout: Loadout }, Leave },
}

event Members {
	from: Client, type: Reliable, call: SingleSync,
	data: u8 | struct { team: Team, perks: set<u8>(0..2), floor: Enum.Material, loadout: Loadout },
}
