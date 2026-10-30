--[[
    What the compiler writes and how the command runs: how many
    module-level locals one generated file may declare, the word a shard's
    file name takes before its number, and how often watch mode reads the
    schema files
--]]

--!strict
local Output = {
	fileLocals = 150, -- Luau's 200 locals a function, less the margin its documentation asks for near a limit
	shard = "Shard", -- Between an entry's file name and a shard's number: Server.luau's first is ServerShard1.luau
	watchSeconds = 0.25, -- Between two reads of the watched files' modification times
}

return Output
