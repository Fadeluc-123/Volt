option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

-- Named twice by Track, so it is one shared pair whose reader looks its part up
struct Tracked { part: AwaitedInstance(BasePart), at: Vector3 }

namespace World {
	event Spawned {
		from: Server, type: Reliable, call: ManySync,
		data: (model: AwaitedInstance(Model), health: u16),
	}

	-- Carries no AwaitedInstance, so it is written and read as in any schema
	event Plain {
		from: Server, type: Reliable, call: ManySync,
		data: u8,
	}

	event Group {
		from: Server, type: Reliable, call: SingleAsync,
		data: (members: AwaitedInstance(BasePart)[0..8], leader: AwaitedInstance?),
	}

	event Brief {
		from: Server, type: Reliable, call: Polling,
		timeout: 0.001,
		data: AwaitedInstance(BasePart),
	}

	-- Reaches its AwaitedInstances only through Tracked's pair, and still waits for them
	event Track {
		from: Server, type: Reliable, call: ManySync,
		data: (first: Tracked, second: Tracked),
	}
}
