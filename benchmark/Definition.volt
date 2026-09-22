option clientOutput = "Generated/Volt/Client.luau"
option serverOutput = "Generated/Volt/Server.luau"
option maxPacket = 1048576
option maxPacketsPerSecond = 100000

-- The two payloads of Blink's published benchmark, then a mixed struct and a small unreliable input
struct Entity { id: u8, x: u8, y: u8, z: u8, orientation: u8, animation: u8 }
struct Snapshot { position: Vector3, yaw: f32, health: u8, name: string(0..32), target: u16? }
struct Controls { dir: u8, jump: boolean }

event Entities {
	from: Client, type: Reliable, call: SingleSync,
	data: Entity[0..1000],
	rate: unlimited,
}

event Booleans {
	from: Client, type: Reliable, call: SingleSync,
	data: boolean[0..1000],
	rate: unlimited,
}

event Snapshots {
	from: Client, type: Reliable, call: SingleSync,
	data: Snapshot[0..64],
	rate: unlimited,
}

event Input {
	from: Client, type: Unreliable, call: SingleSync,
	data: Controls,
	rate: unlimited,
}
