option clientOutput = "Client.luau"
option serverOutput = "Server.luau"
option promise = "ReplicatedStorage.Packages.Promise"

function Echo {
	data: u8,
	return: u8,
}

function Ping {
}

function Divide {
	timeout: 2,
	data: (dividend: f64, divisor: f64),
	return: (ok: boolean, quotient: f64?),
}

namespace Inventory {
	function Transfer {
		yield: Promise,
		rate: unlimited,
		data: (source: u8, destination: u8, quantity: u16),
		return: (ok: boolean, reason: string(0..64)?),
	}
}
