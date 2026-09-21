--[[
    The names nothing in a schema or a generated function may take: Luau's
    reserved words, which cannot name anything the generated code spells
    out, the names the generated code already reaches for, which no local
    it declares may shadow, and the members the generated API has of its
    own, which no top-level declaration may take
--]]

--!strict
local LUAU_WORDS: string =
	"and break do else elseif end false for function if in local nil not or repeat return then true until while"

local Reserved = {
	luau = {} :: { [string]: boolean },

	generated = {
		"ALIGNED",
		"BrickColor",
		"CFrame",
		"Color3",
		"DateTime",
		"ENUMS",
		"Enum",
		"Instance",
		"Promise",
		"Vector2",
		"Vector3",
		"Volt",
		"alignedIndex",
		"allocate",
		"allocateReliable",
		"allocateUnreliable",
		"axisAngle",
		"bit32",
		"buffer",
		"cframe",
		"cursor",
		"deliver",
		"enumItem",
		"error",
		"length",
		"markUnreliable",
		"math",
		"net",
		"packet",
		"player",
		"players",
		"readf16",
		"runtime",
		"side",
		"sideCursor",
		"slot",
		"slotReliable",
		"slotUnreliable",
		"status",
		"string",
		"table",
		"tostring",
		"typeof",
		"writef16",
	} :: { string },

	api = { "flush", "onFailure" } :: { string }, -- In camel casing; the schema's casing is applied before a name is checked
}

for word: string in LUAU_WORDS:gmatch("%a+") do
	Reserved.luau[word] = true
end

return Reserved
