--[[
    Every attribute a declaration may carry, one row each: its name as
    written after the @, the declaration kinds it applies to, whether an
    exported type may carry it and whether it takes a number in parentheses.
    The rows' order is the order the canonical form prints a declaration's
    attributes in
--]]

--!strict
export type Attribute = {
	name: string,
	kinds: { string }, -- A struct or enum declaration is a type
	exported: boolean,
	argument: boolean?, -- Takes a whole number from 1 up, written straight after its name
	most: number?, -- The most that number may be
}

local Attributes: { Attribute } = {
	{ name = "private", kinds = { "type" }, exported = false }, -- Keeps a named type out of what the modules export
	{ name = "delta", kinds = { "event" }, exported = false }, -- Sends a player only the fields that changed
	{ name = "dictionary", kinds = { "type" }, exported = false }, -- Sends a string as its dictionary id

	-- The deepest level a recursive value may sit at, far below Luau's 20,000 nested calls at its most
	{ name = "depth", kinds = { "type" }, exported = true, argument = true, most = 1000 },
}

return Attributes
