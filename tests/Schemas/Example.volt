option clientOutput = "../src/Client/Net.luau"
option serverOutput = "../src/Server/Net.luau"
option typesOutput = "../src/Shared/Config/Types/Net.luau"
option yield = promise
option promise = "ReplicatedStorage.Packages.Promise"

type Reference = string(1..64)
struct Stack { item: string(1..32), quantity: u16(1..999), properties: unknown? }
enum Team { Red, Blue }

export struct Save { version: u16, stacks: Stack[0..256] }

event Input {
	from: Client, type: Unreliable, call: SingleSync,
	data: (dir: u8(0..8), jump: boolean, look: q16(-3.2..3.2)),
	rate: 120,
}

namespace Inventory {
	event Patch {
		from: Server, type: Reliable, call: SingleAsync,
		data: struct { version: u32, set: { [u8]: Stack }(0..64), cleared: u8[0..64] },
	}

	function Transfer {
		timeout: 5,
		data: (source: Reference, destination: Reference, slot: u8, quantity: u16),
		return: (ok: boolean, reason: string(0..128)?),
	}
}
