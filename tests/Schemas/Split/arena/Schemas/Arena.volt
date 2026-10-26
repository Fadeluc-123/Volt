option clientOutput = "../Network/Client.luau"
option serverOutput = "../Network/Server.luau"
option typesOutput = "../Network/Types.luau"

namespace Arena {
	event Ready {
		from: Client, type: Reliable, call: SingleSync,
	}
}
