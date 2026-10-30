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
		"NumberRange",
		"Promise",
		"QUATERNION_RANGE",
		"Ray",
		"Rect",
		"Region3",
		"UDim2",
		"Vector2",
		"Vector3",
		"Volt",
		"alignedIndex",
		"allocate",
		"allocateReliable",
		"allocateUnreliable",
		"assert",
		"axisAngle",
		"before",
		"begin",
		"beginReliable",
		"beginUnreliable",
		"bit32",
		"buffer",
		"cframe",
		"cursor",
		"debug",
		"deliver",
		"depth",
		"dictionaryEntries",
		"enumItem",
		"error",
		"instanceById",
		"instanceId",
		"internDictionary",
		"length",
		"markUnreliable",
		"mask",
		"math",
		"packQuaternion",
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
		"unpackQuaternion",
		"utf8",
		"writef16",
	} :: { string },

	-- In camel casing; the schema's casing is applied before a name is checked
	api = {
		"budget",
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
		"serverTime", -- A stamped client's alone, refused in every schema so one schema means one name space
		"stats",
		"traffic",
		"version",
	} :: { string },

	-- The types every generated module declares or names, Luau's own, the player and the Roblox classes its annotations
	-- spell among them, which a top-level named type or a type parameter would collide with or shadow
	types = {
		"any",
		"boolean",
		"buffer",
		"number",
		"string",
		"Bot",
		"BrickColor",
		"CFrame",
		"ClientEvent",
		"ClientFunction",
		"ClientHandler",
		"ClientListener",
		"ClientPolling",
		"ClientPromise",
		"Color3",
		"DateTime",
		"EnumItem",
		"Exported",
		"Instance",
		"NumberRange",
		"Player",
		"Ray",
		"Rect",
		"Region3",
		"ServerEvent",
		"ServerFunction",
		"ServerInvoke",
		"ServerListener",
		"ServerPolling",
		"ServerPromise",
		"UDim2",
		"Vector2",
		"Vector3",
	} :: { string },
}

for word: string in LUAU_WORDS:gmatch("%a+") do
	Reserved.luau[word] = true
end

return Reserved
