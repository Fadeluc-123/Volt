--[[
    The numbers the wire format is built on that are choices rather than
    consequences: how far an undeclared length reaches, how long an enum's
    name may be, when message ids widen, how a call, its reply, the
    handshake, a packet and a dictionary string are framed, how a colour
    channel is scaled and which primitives Roblox types are carried as
--]]

--!strict
local Wire = {
	defaultLength = 65535, -- As far as the u16 prefix reaches when a length has no bound
	longestEnumName = 255, -- What the u8 prefix of an EnumItem's type name can carry
	idsPerByte = 255, -- Messages per direction before ids widen to u16
	slotBytes = 2, -- A call's slot, which is what bounds the calls a function has in flight
	statusBytes = 1, -- A reply's status
	replyMessage = 256, -- The most of a reason a refusal carries; the runtime's row must agree
	handshakeBytes = 5, -- The id and the hash a client's first frame opens with; the runtime's must agree
	sequenceBytes = 2, -- An ordered unreliable message's sequence, after its id
	stampBytes = 8, -- The server's clock a stamped schema's server packets open with; the runtime's must agree
	channelBytes = 1, -- The stream every packet of a schema with a channel opens with; the runtime's must agree
	channels = 255, -- The most channels the channel byte numbers, 0 being the default stream
	dictionaryBytes = 2, -- A @dictionary string's id, which is all a message carries of it
	entryBytes = 255, -- The longest @dictionary string, which an entry's u8 length holds
	depth = 16, -- The level a recursive value may nest to when its type sets none
	channelMax = 255, -- A Color3 channel on the wire
	component = "f32", -- What a vector or CFrame component is carried as when the type names none
	seconds = "f64", -- What a DateTime's timestamp is carried as
}

return Wire
