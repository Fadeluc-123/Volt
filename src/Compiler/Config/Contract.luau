--[[
    The contract between the generated modules and the runtime: the
    version every schema table is stamped with, what a message's writer
    begins and trims with and when it reserves, what a shared type's
    writer takes before its value, what every reader takes and the player
    a message reader takes first, and the options the schema table carries
--]]

--!strict
export type Parameter = { name: string, type: string }

local Contract = {
	version = "0.1.0", -- Stamped into every schema table; the runtime refuses another major or minor

	begin = { name = "begin", type = "(number) -> (number, buffer)" } :: Parameter, -- Takes a message's first bytes
	trim = { name = "trim", type = "(number) -> ()" } :: Parameter, -- Ends a reserving writer where its bytes did
	reserveBytes = 8192, -- The largest size a varying message's writer takes whole with begin, then trims

	write = {
		{ name = "allocate", type = "(number) -> (number, buffer)" },
		{ name = "slot", type = "(any) -> ()" },
		{ name = "refuse", type = "(string) -> never" }, -- Never returns, so a refused branch is known to end there
	} :: { Parameter },

	read = {
		{ name = "packet", type = "buffer" },
		{ name = "cursor", type = "number" },
		{ name = "side", type = "{ any }" },
		{ name = "sideCursor", type = "number" },
		{ name = "length", type = "number" },
	} :: { Parameter },

	message = {
		{ name = "player", type = "(Player | Bot)?" }, -- Nil on the client, which is how the runtime tells the sides apart
	} :: { Parameter },

	-- What the runtime reads
	options = {
		"flush",
		"manualReplication",
		"maxOutgoing",
		"maxPacket",
		"maxPacketsPerSecond",
		"unreliableBudget",
		"writeValidation",
	},
}

-- A message reader takes the player, then everything a shared type's reader takes
table.move(Contract.read, 1, #Contract.read, 2, Contract.message)

return Contract
