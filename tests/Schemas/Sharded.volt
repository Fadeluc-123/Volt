option clientOutput = "Client.luau"
option serverOutput = "Server.luau"
option typesOutput = "Types.luau"
option shardSize = 3

-- Eight entries three to a shard, so Inventory spans two shards and Stack and Team are reached from two
enum Team { Red, Blue }
struct Stack { item: string(1..32), quantity: u16 }
export struct Save { version: u16, stacks: Stack[0..8] }

event Input { from: Client, type: Unreliable, call: SingleSync, data: (dir: u8(0..8), jump: boolean) }
event Ready { from: Client, type: Reliable, call: ManySync }
event Sync { from: Both, type: Reliable, call: SingleSync, data: u8 }

namespace Inventory {
	event Patch { from: Server, type: Reliable, call: SingleAsync, data: Stack[0..16] }
	function Transfer { data: (item: Stack, team: Team), return: (ok: boolean, reason: string(0..64)?) }
	event Picked { from: Client, type: Reliable, call: ManyAsync, data: Team }
}

function Echo { data: u8, return: u8 }
