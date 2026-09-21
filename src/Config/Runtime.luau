--[[
    The runtime's tunables, one row each: how a send buffer starts and
    grows, where the remotes live under ReplicatedStorage and what they
    are called, and how long the client waits for them before it warns
--]]

--!strict
local Runtime = {
	initialBytes = 64, -- What a send buffer starts at; it grows to fit the first frame that needs more
	growth = 1.5, -- How much a send buffer grows by when a frame overflows it
	folder = "Volt", -- The folder under ReplicatedStorage every scope's remotes sit in
	reliable = "Reliable", -- The RemoteEvent's name inside a scope
	unreliable = "Unreliable", -- The UnreliableRemoteEvent's name inside a scope
	waitSeconds = 10, -- How long the client waits for a remote before warning and waiting again
}

return Runtime
