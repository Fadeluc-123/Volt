--[[
    Every option a schema file may set and every key an event or function
    record may carry, one row each: the shape its value must have, the
    names a fixed list allows, whether it must be present, the default the
    resolver fills, and whether a number may be fractional
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
}

local RATE: { string } = { "unlimited" }

-- Shapes are arrays so keys list, print and default in declaration order
local Options = {
	file = {
		{ key = "clientOutput", kind = "string", required = true },
		{ key = "serverOutput", kind = "string", required = true },
		{ key = "typesOutput", kind = "string" },
		{ key = "runtime", kind = "string", default = "ReplicatedStorage.Packages.Volt" },
		{ key = "scope", kind = "name" }, -- Defaults to the schema file's own name
		{ key = "casing", values = { "camel", "pascal", "snake" }, default = "camel" },
		{ key = "writeValidation", kind = "boolean", default = true },
		{ key = "manualReplication", kind = "boolean", default = false },
		{ key = "flush", kind = "number", default = 1 },
		{ key = "maxPacket", kind = "number", default = 8192 },
		{ key = "maxPacketsPerSecond", kind = "number", default = 240 },
		{ key = "unreliableBudget", kind = "number", default = 900 },
		{ key = "queue", kind = "number", default = 64 },
		{ key = "rate", kind = "number", values = RATE, default = 120 },
		{ key = "functionRate", kind = "number", values = RATE, default = 60 },
		{ key = "timeout", kind = "number", fractional = true, default = 10 },
		{ key = "yield", values = { "coroutine", "promise" }, default = "coroutine" },
		{ key = "promise", kind = "string" }, -- Required only when a yield asks for a promise
	} :: { Spec },

	event = {
		{ key = "from", values = { "Client", "Server", "Both" }, required = true },
		{ key = "type", values = { "Reliable", "Unreliable" }, required = true },
		{ key = "call", values = { "SingleSync", "SingleAsync", "ManySync", "ManyAsync", "Polling" }, required = true },
		{ key = "data", kind = "data" },
		{ key = "queue", kind = "number", option = "queue" },
		{ key = "rate", kind = "number", values = RATE, option = "rate" },
	} :: { Spec },

	["function"] = {
		{ key = "data", kind = "data" },
		{ key = "return", kind = "data" },
		{ key = "yield", values = { "Coroutine", "Promise" } }, -- Defaults from the file's yield, capitalised
		{ key = "timeout", kind = "number", fractional = true, option = "timeout" },
		{ key = "rate", kind = "number", values = RATE, option = "functionRate" },
	} :: { Spec },
}

return Options
