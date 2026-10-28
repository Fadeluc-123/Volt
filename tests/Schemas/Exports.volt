option clientOutput = "Client.luau"
option serverOutput = "Server.luau"
option typesOutput = "Types.luau"

export struct Save { version: u16, names: string(0..16)[0..4], owner: Instance? }
export struct Hit { part: Instance(BasePart), model: StreamedInstance(Model) }

namespace Inventory {
	export enum Kind { Bag, Chest }
}

event Ping {
	from: Client, type: Reliable, call: SingleSync,
}
