--[[
    The runtime's tunables, one row each: how a send buffer starts and
    grows, where the remotes live, how long the client waits for them, how
    many calls a function may have in flight, how much of a reason a refusal
    carries, what a reply's status says, how often the default handler
    warns, what an error's position looks like and how traffic is counted
--]]

--!strict
local Runtime = {
	initialBytes = 64, -- What a send buffer starts at; it grows to fit the first frame that needs more
	growth = 1.5, -- How much a send buffer grows by when a frame overflows it
	folder = "Volt", -- The folder under ReplicatedStorage every scope's remotes sit in
	reliable = "Reliable", -- The RemoteEvent's name inside a scope
	unreliable = "Unreliable", -- The UnreliableRemoteEvent's name inside a scope
	waitSeconds = 10, -- How long the client waits for a remote before warning and waiting again
	slots = 65535, -- Calls one function may have in flight, as many as a two-byte slot can name
	messageBytes = 256, -- The most of a reason a refusal carries to the caller
	handshakeBytes = 5, -- The handshake's id as one byte, then the schema hash as a u32; the compiler's Wire row must agree
	status = { ok = 0, failed = 1, unhandled = 2, limited = 3 }, -- A reply's status: the returns follow, the handler erred, none is connected, the caller is over the rate
	warnSeconds = 60, -- How long the default failure handler stays quiet about one kind from one player after warning
	position = "^.-:%d+: ", -- Luau's source position before an error's text, cut from what a failure or a fire reports
	trafficSeconds = 1, -- How far back a player's count of the bytes sent to them reaches
	trafficSlices = 10, -- How many slices that time is kept in, so the count moves on every slice rather than every second
}

return Runtime
