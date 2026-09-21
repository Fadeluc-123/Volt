--[[
    The runtime's tunables, one row each: how a send buffer starts, grows
    and is capped, where the remotes live and what they are called, how
    long the client waits for them, how many calls a function may have in
    flight, how much of a reason a refusal carries, what a reply's status
    says and how often the default failure handler warns
--]]

--!strict
local Runtime = {
	initialBytes = 64, -- What a send buffer starts at; it grows to fit the first frame that needs more
	growth = 1.5, -- How much a send buffer grows by when a frame overflows it
	maxOutgoing = 262144, -- The most one target's frame may hold; the message that takes it past this is dropped
	folder = "Volt", -- The folder under ReplicatedStorage every scope's remotes sit in
	reliable = "Reliable", -- The RemoteEvent's name inside a scope
	unreliable = "Unreliable", -- The UnreliableRemoteEvent's name inside a scope
	waitSeconds = 10, -- How long the client waits for a remote before warning and waiting again
	slots = 65535, -- Calls one function may have in flight, as many as a two-byte slot can name
	messageBytes = 256, -- The most of a reason a refusal carries to the caller
	status = { ok = 0, failed = 1, unhandled = 2, limited = 3 }, -- A reply's status: the returns follow, the handler erred, none is connected, the caller is over the rate
	warnSeconds = 60, -- How long the default failure handler stays quiet about one kind from one player after warning
}

return Runtime
