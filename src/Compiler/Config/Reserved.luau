--[[
    The names nothing in a schema or a generated function may take: Luau's
    reserved words, which cannot name anything the generated code spells
    out, the names the generated code reaches for, every global it calls
    among them, which no local it declares may shadow, and the members the
    generated API has of its own, which no top-level declaration may take
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
		"Network",
		"Promise",
		"Vector2",
		"Vector3",
		"Volt",
		"alignedIndex",
		"allocate",
		"allocateReliable",
		"allocateUnreliable",
		"axisAngle",
		"before",
		"begin",
		"beginReliable",
		"beginUnreliable",
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
		"packet",
		"player",
		"players",
		"readf16",
		"refuse",
		"refuseReliable",
		"refuseUnreliable",
		"require",
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
		"trimReliable",
		"trimUnreliable",
		"type",
		"typeof",
		"utf8",
		"writef16",
	} :: { string },

	-- In camel casing; the schema's casing is applied before a name is checked
	api = {
		"events",
		"exports",
		"flush",
		"functions",
		"hooks",
		"isBot",
		"onFailure",
		"onHandshake",
		"onJoin",
		"onLeave",
		"rate",
		"stats",
		"traffic",
		"version",
	} :: { string },

	-- The types every generated module declares or names, the player and the Roblox classes its annotations spell
	-- among them, which a top-level named type would collide with or shadow
	types = {
		"Bot",
		"BrickColor",
		"CFrame",
		"ClientEvent",
		"ClientFunction",
		"ClientListener",
		"ClientPolling",
		"ClientPromise",
		"Color3",
		"DateTime",
		"EnumItem",
		"Exported",
		"Instance",
		"Player",
		"ServerEvent",
		"ServerFunction",
		"ServerListener",
		"ServerPolling",
		"Vector2",
		"Vector3",
	} :: { string },
}

for word: string in LUAU_WORDS:gmatch("%a+") do
	Reserved.luau[word] = true
end

return Reserved
