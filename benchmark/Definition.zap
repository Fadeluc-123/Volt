opt client_output = "Generated/Zap/Client.luau"
opt server_output = "Generated/Zap/Server.luau"

-- The two payloads of Blink's published benchmark, then a mixed struct and a small unreliable input
type Entity = struct { id: u8, x: u8, y: u8, z: u8, orientation: u8, animation: u8 }
type Snapshot = struct { position: Vector3, yaw: f32, health: u8, name: string.binary(0..32), target: u16? }
type Controls = struct { dir: u8, jump: boolean }

event Entities = {
	from: Client, type: Reliable, call: SingleSync,
	data: Entity[0..1000],
}

event Booleans = {
	from: Client, type: Reliable, call: SingleSync,
	data: boolean[0..1000],
}

event Snapshots = {
	from: Client, type: Reliable, call: SingleSync,
	data: Snapshot[0..64],
}

event Input = {
	from: Client, type: Unreliable, call: SingleSync,
	data: Controls,
}
