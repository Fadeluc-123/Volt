--[[
    The contract between the generated modules and the runtime: the
    version every schema table is stamped with, what a message's writer
    begins with, what a shared type's writer takes before its value, what
    every reader takes and the player a message reader takes first, and
    the file options the schema table carries to the runtime
--]]

--!strict
export type Parameter = { name: string, type: string }

local Contract = {
	version = "0.1.0", -- Stamped into every schema table; the runtime refuses another major or minor

	begin = { name = "begin", type = "(number) -> (number, buffer)" } :: Parameter, -- Takes a message's first bytes

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
		{ name = "player", type = "Player?" }, -- Nil on the client, which is how the runtime tells the sides apart
	} :: { Parameter },

	options = { "flush", "manualReplication", "maxPacket", "maxPacketsPerSecond", "unreliableBudget" }, -- What the runtime reads
}

-- A message reader takes the player, then everything a shared type's reader takes
table.move(Contract.read, 1, #Contract.read, 2, Contract.message)

return Contract
