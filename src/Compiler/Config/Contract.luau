--[[
    The parameters the generated functions take, which is the contract
    between the generated modules and the runtime: what a shared type's
    writer takes before its value, and what every reader takes
--]]

--!strict
export type Parameter = { name: string, type: string }

local Contract = {
	write = {
		{ name = "allocate", type = "(number) -> (number, buffer)" },
		{ name = "slot", type = "(any) -> ()" },
	} :: { Parameter },

	read = {
		{ name = "packet", type = "buffer" },
		{ name = "cursor", type = "number" },
		{ name = "side", type = "{ any }" },
		{ name = "sideCursor", type = "number" },
		{ name = "length", type = "number" },
	} :: { Parameter },
}

return Contract
