--[[
    Every option a schema file may set and every key an event or function
    record may carry, one row each: its value's shape, the names a fixed
    list allows, whether it is required, the default the resolver fills,
    whether a number may be fractional and whether it is a build option
--]]

--!strict
export type Spec = {
	key: string,
	kind: string?, -- number, string, name, boolean or data; a number must be positive
	values: { string }?, -- The names a fixed list allows, alone or beside a kind
	required: boolean?, -- Reported when missing
	fractional: boolean?, -- A number that need not be whole
	default: any?, -- What the resolver fills when the key is not set
	option: string?, -- The file option a message key defaults from
	build: boolean?, -- Changes what the compiler writes and nothing on the wire, so the canonical form leaves it out
}

local RATE: { string } = { "unlimited" }

-- Shapes are arrays so keys list, print and default in declaration order
local Options = {
	file = {
		{ key = "clientOutput", kind = "string", required = true },
		{ key = "serverOutput", kind = "string", required = true },
		{ key = "typesOutput", kind = "string" },
		{ key = "runtime", kind = "string", default = "ReplicatedStorage.Packages.Volt" },
		{ key = "scope", kind = "name" }, -- Defaults to the options file's own name
		{ key = "casing", values = { "camel", "pascal", "snake" }, default = "camel" },
		{ key = "writeValidation", kind = "boolean", default = true },
		{ key = "manualReplication", kind = "boolean", default = false },
		{ key = "flush", kind = "number", default = 1 },
		{ key = "flushBytes", kind = "number" }, -- No default: unset, the canonical form leaves it out
		{ key = "maxPacket", kind = "number", default = 8192 },
		{ key = "maxPacketsPerSecond", kind = "number", default = 240 },
		{ key = "maxOutgoing", kind = "number", default = 262144 },
		{ key = "unreliableBudget", kind = "number", default = 900 },
		{ key = "stamp", kind = "boolean" }, -- No default: off, nothing is stamped and the canonical form leaves it out
		{ key = "queue", kind = "number", default = 64 },
		{ key = "rate", kind = "number", values = RATE, default = 120 },
		{ key = "functionRate", kind = "number", values = RATE, default = 60 },
		{ key = "timeout", kind = "number", fractional = true, default = 10 },
		{ key = "yield", values = { "coroutine", "promise" }, default = "coroutine" },
		{ key = "promise", kind = "string" }, -- Required only when a yield asks for a promise
		{ key = "inspectorOutput", kind = "string", build = true }, -- No default: the inspector is written only when asked
		{ key = "shardSize", kind = "number", build = true }, -- No default: a side shards only past the local limit
		{ key = "profileLabels", kind = "boolean", default = false, build = true }, -- MicroProfiler labels
	} :: { Spec },

	event = {
		{ key = "from", values = { "Client", "Server", "Both" }, required = true },
		{ key = "type", values = { "Reliable", "Unreliable", "OrderedUnreliable" }, required = true },
		{ key = "call", values = { "SingleSync", "SingleAsync", "ManySync", "ManyAsync", "Polling" }, required = true },
		{ key = "data", kind = "data" },
		{ key = "queue", kind = "number", option = "queue" },
		{ key = "rate", kind = "number", values = RATE, option = "rate" },
		{ key = "timeout", kind = "number", fractional = true }, -- No default: an awaited reader takes the file's
		{ key = "channel", kind = "name" }, -- A channel's plain name; absent, the event rides the default stream
	} :: { Spec },

	["function"] = {
		{ key = "from", values = { "Client", "Server" } }, -- No default: a function without it is a client's call
		{ key = "data", kind = "data" },
		{ key = "return", kind = "data" },
		{ key = "yield", values = { "Coroutine", "Promise" } }, -- Defaults from the file's yield, capitalised
		{ key = "timeout", kind = "number", fractional = true, option = "timeout" },
		{ key = "rate", kind = "number", values = RATE, option = "functionRate" },
	} :: { Spec },
}

return Options
