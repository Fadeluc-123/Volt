--[[
    The runtime's tunables, one row each: how a send buffer starts and
    grows, where the remotes and instance ids live, the calls a function
    may have in flight, a reply's status, what opens a packet, an ordered
    sequence's wrap, the dictionary's capacity, the default handler's
    warnings and how traffic counts
--]]

--!strict
local Runtime = {
	initialBytes = 64, -- What a send buffer starts at; it grows to fit the first frame that needs more
	growth = 1.5, -- How much a send buffer grows by when a frame overflows it
	folder = "Volt", -- The folder under ReplicatedStorage every scope's remotes sit in
	reliable = "Reliable", -- The RemoteEvent's name inside a scope
	unreliable = "Unreliable", -- The UnreliableRemoteEvent's name inside a scope
	references = "References", -- The Folder beside them holding an ObjectValue per awaited instance, named by its id
	counter = "Next", -- That folder's attribute holding the next id, so a second server VM never gives one twice
	waitSeconds = 10, -- How long the client waits for a remote before warning and waiting again
	slots = 65535, -- Calls one function may have in flight on the client, as many as a two-byte slot can name
	playerSlots = 256, -- Calls the server may have in flight to one player through one function
	messageBytes = 256, -- The most of a reason a refusal carries to the caller
	prefixBytes = 2, -- The u16 a refusal's reason's length is carried in, as far as messageBytes reaches
	handshakeBytes = 5, -- The handshake's id as one byte, then the schema hash as a u32; the compiler's Wire row must agree
	channelBytes = 1, -- The byte naming its stream every packet opens with in a schema with a channel; Wire's row must agree
	stampBytes = 8, -- The f64 server time a stamped server's packet opens with, after any channel byte; Wire's row must agree
	sequences = 65536, -- How many values an ordered event's u16 sequence takes before it wraps to 0
	dictionaryEntries = 4096, -- The most strings a scope's dictionary holds; a write that would add one past it is refused
	status = { ok = 0, failed = 1, unhandled = 2, limited = 3 }, -- A reply's status: the returns follow, the handler erred, none is connected, the caller is over the rate
	warnSeconds = 60, -- How long the default failure handler stays quiet about one kind from one player after warning
	position = "^.-:%d+: ", -- Luau's source position before an error's text, cut from what a failure or a fire reports
	trafficSeconds = 1, -- How far back a player's count of the bytes sent to them reaches
	trafficSlices = 10, -- How many slices that time is kept in, so the count moves on every slice rather than every second
}

return Runtime
