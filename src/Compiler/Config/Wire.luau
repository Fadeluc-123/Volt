--[[
    The numbers the wire format is built on that are choices rather than
    consequences: how far an undeclared length reaches, how long an enum's
    name may be, when message ids widen, how a colour channel is scaled
    and which primitives Roblox types are carried as when they name none
--]]

--!strict
local Wire = {
	defaultLength = 65535, -- As far as the u16 prefix reaches when a length has no bound
	longestEnumName = 255, -- What the u8 prefix of an EnumItem's type name can carry
	idsPerByte = 255, -- Messages per direction before ids widen to u16
	channelMax = 255, -- A Color3 channel on the wire
	component = "f32", -- What a vector or CFrame component is carried as when the type names none
	seconds = "f64", -- What a DateTime's timestamp is carried as
}

return Wire
