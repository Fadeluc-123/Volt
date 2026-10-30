--[[
    Every attribute a declaration may carry, one row each: its name as
    written after the @, the declaration kinds it applies to and whether an
    exported type may carry it. The rows' order is the order the canonical
    form prints a declaration's attributes in
--]]

--!strict
export type Attribute = {
	name: string,
	kinds: { string }, -- A struct or enum declaration is a type
	exported: boolean,
}

local Attributes: { Attribute } = {
	{ name = "private", kinds = { "type" }, exported = false }, -- Keeps a named type out of what the modules export
	{ name = "delta", kinds = { "event" }, exported = false }, -- Sends a player only the fields that changed
	{ name = "dictionary", kinds = { "type" }, exported = false }, -- Sends a string as its dictionary id
}

return Attributes
