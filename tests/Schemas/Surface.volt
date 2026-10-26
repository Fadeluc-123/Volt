option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

-- One event for every side it can come from and every call mode it can be heard in
event ClientSingleSync { from: Client, type: Reliable, call: SingleSync }
event ClientSingleAsync { from: Client, type: Reliable, call: SingleAsync }
event ClientManySync { from: Client, type: Reliable, call: ManySync }
event ClientManyAsync { from: Client, type: Reliable, call: ManyAsync }
event ClientPolling { from: Client, type: Reliable, call: Polling }

event ServerSingleSync { from: Server, type: Reliable, call: SingleSync }
event ServerSingleAsync { from: Server, type: Reliable, call: SingleAsync }
event ServerManySync { from: Server, type: Reliable, call: ManySync }
event ServerManyAsync { from: Server, type: Reliable, call: ManyAsync }
event ServerPolling { from: Server, type: Reliable, call: Polling }

event BothSingleSync { from: Both, type: Reliable, call: SingleSync }
event BothSingleAsync { from: Both, type: Reliable, call: SingleAsync }
event BothManySync { from: Both, type: Reliable, call: ManySync }
event BothManyAsync { from: Both, type: Reliable, call: ManyAsync }
event BothPolling { from: Both, type: Reliable, call: Polling }

namespace Ns {
	function Ask {
		data: u8,
		return: u8,
	}
}
