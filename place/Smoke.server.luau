--[[
    The server half of the Studio smoke test: hears every event the client
    fires, serves its function and answers each, fires numbered Late
    messages at a joiner from its own PlayerAdded, and prints Volt smoke:
    pass once all of it is done with nothing reported, or the first fault
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local Network = require(ServerScriptService.Network)

local DEADLINE: number = 40 -- Seconds to wait for the client, which joins a while after the server and loads late
local LATE: number = 600 -- Late messages fired at a joiner, one a frame, while their client has yet to load its module

type Bot = Volt.Bot

-- What the client has yet to send, and the Late messages still to fire
local waiting: { [string]: boolean } = { Ping = true, Move = true, Mark = true, Echo = true, Late = true }
local failed: string? = nil

-- Keeps the first failure only, since everything after it is noise
local function fail(detail: string)
	failed = failed or detail
end

local function arrived(name: string)
	waiting[name] = nil
end

-- A departed here would mean a fire from the game's own PlayerAdded was dropped
Network.onFailure(function (player: (Player | Bot)?, kind: string, detail: string)
	fail(`{kind} from {player and player.Name or "nobody"}: {detail}`)
end)

Network.Ping.on(function (player: Player | Bot, value: number)
	arrived("Ping")
	Network.Pong.fire(player, value + 1)
end)

Network.Move.on(function (player: Player | Bot, x: number, y: number)
	arrived("Move")
	Network.Moved.fire(player, x, y)
end)

-- The one value the client cannot check from its side: an Instance through the side array
Network.Mark.on(function (_, instance: Instance)
	if instance ~= workspace then
		fail(`Mark: got {instance:GetFullName()}`)
	end

	arrived("Mark")
end)

Network.Echo.on(function (_, word: string): string
	arrived("Echo")
	return word:upper()
end)

-- Connected after the module, as a game's own is; the server lives as long as the place, so nothing disconnects it
Players.PlayerAdded:Connect(function (player: Player)
	for index: number = 1, LATE do
		Network.Late.fire(player, index)
		task.wait()
	end

	arrived("Late")
end)

local deadline: number = os.clock() + DEADLINE
while next(waiting) and not failed and os.clock() < deadline do
	task.wait()
end

local missing: string? = next(waiting)

if failed then
	warn(`Volt smoke: {failed}`)
elseif missing then
	warn(`Volt smoke: never heard {missing}`)
else
	print("Volt smoke: pass")
end
