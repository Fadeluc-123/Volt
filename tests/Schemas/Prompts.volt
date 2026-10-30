option clientOutput = "Client.luau"
option serverOutput = "Server.luau"
option promise = "ReplicatedStorage.Packages.Promise"

-- What a client's handler fires at the server before it answers
event Progress {
	from: Client,
	type: Reliable,
	call: ManySync,
	data: u8,
}

function Confirm {
	from: Server,
	timeout: 2,
	data: (title: string(1..64), seconds: u8),
	return: (accepted: boolean, note: string(0..64)?),
}

function Poke {
	from: Server,
}

namespace Camera {
	function Aim {
		from: Server,
		yield: Promise,
		return: Vector3,
	}
}
