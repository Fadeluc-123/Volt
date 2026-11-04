option clientOutput = "../../place/Client.luau"
option serverOutput = "../../place/Server.luau"
option inspectorOutput = "../../place/RemoteName.profiler.luau"
option stamp = true

-- A stream of its own on the Reliable remote, which adds no remote to the scope's folder
channel Bulk

event Ping {
	from: Client, type: Reliable, call: SingleAsync,
	data: u8,
}

event Move {
	from: Client, type: Unreliable, call: SingleSync,
	data: (x: f32, y: f32),
}

event Mark {
	from: Client, type: Reliable, call: SingleAsync,
	data: Instance,
}

event Pong {
	from: Server, type: Reliable, call: SingleAsync,
	data: u8,
}

event Moved {
	from: Server, type: Unreliable, call: SingleSync,
	data: (x: f32, y: f32),
}

function Echo {
	data: string(0..32),
	return: string(0..32),
}

-- Fired at a joiner once a frame from the server's own PlayerAdded, before their client requires its module
event Late {
	from: Server, type: Reliable, call: SingleSync,
	data: u16,
}

-- Fired on the channel each way, the server sending back what it heard
event Shout {
	from: Both, type: Reliable, call: SingleAsync, channel: Bulk,
	data: string(0..32),
}

-- Carries a sequence each way, the server sending back what it heard
event Aim {
	from: Both, type: OrderedUnreliable, call: SingleSync,
	data: (yaw: q16(-3.2..3.2), pitch: q16(-1.6..1.6)),
}

-- Names a part the client may not have streamed in, which the message waits up to five seconds for
event Placed {
	from: Server, type: Reliable, call: SingleAsync, timeout: 5,
	data: (part: AwaitedInstance(BasePart), index: u8),
}

-- One of each GUI and geometry value, the server sending back what it heard
event Shapes {
	from: Both, type: Reliable, call: SingleAsync,
	data: (a: UDim2, b: NumberRange, c: Rect, d: Ray, e: Region3),
}

-- As deep as @depth allows, so its write and its read each run a thousand levels down the stack
@depth(1000) struct Chain { value: u8, next: Chain? }

-- The deepest Chain each way, the server sending back what it heard
event Deep {
	from: Both, type: Reliable, call: SingleAsync,
	data: Chain,
}

-- Asks for Reply and then the fifteen Lines, once the client has heard every echo
event Payloads {
	from: Client, type: Reliable, call: SingleAsync,
}

-- 16,391 bytes with its id, as large as Decree's largest run reply, alone in its packet
event Reply {
	from: Server, type: Reliable, call: SingleAsync,
	data: string(16390),
}

-- 16,388 bytes with its id, as large as Decree's largest line, fifteen of them to one packet
event Line {
	from: Server, type: Reliable, call: SingleSync,
	data: (index: u8, text: string(16386)),
}
