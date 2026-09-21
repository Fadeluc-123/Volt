--[[
    The names nothing in a schema or a generated function may take: Luau's
    reserved words, which cannot name anything the generated code spells
    out, and the names the generated code already reaches for, which no
    local it declares may shadow
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
		"Vector2",
		"Vector3",
		"alignedIndex",
		"allocate",
		"axisAngle",
		"bit32",
		"buffer",
		"cframe",
		"cursor",
		"deliver",
		"enumItem",
		"error",
		"length",
		"math",
		"net",
		"packet",
		"player",
		"readf16",
		"side",
		"sideCursor",
		"slot",
		"string",
		"table",
		"tostring",
		"typeof",
		"writef16",
	} :: { string },
}

for word: string in LUAU_WORDS:gmatch("%a+") do
	Reserved.luau[word] = true
end

return Reserved
