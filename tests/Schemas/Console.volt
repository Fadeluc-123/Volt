option clientOutput = "Client.luau"
option serverOutput = "Server.luau"
option typesOutput = "Types.luau"
option promise = "ReplicatedStorage.Packages.Promise"

-- Decree's contract: a printed line and a command's reply carry text of one private type, which the event walks first
namespace Decree {
	enum Kind { Info, Warn, Error }

	@private type Line = string.utf8(0..16384)

	event line {
		from: Server, type: Reliable, call: SingleSync,
		data: (text: Line, kind: Kind),
	}

	function run {
		yield: Promise,
		data: (text: string.utf8(1..4096)),
		return: (text: Line, kind: Kind),
	}
}
