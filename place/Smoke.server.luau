--[[
    The server half of the Studio smoke test: listens for every event
    Smoke.volt lets a client fire, serves its function, answers each with
    the event the server fires back, and prints Volt smoke: pass once
    everything the client sends has arrived, or the first thing that
    went wrong
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local net = require(ServerScriptService.Net)

local DEADLINE: number = 30 -- Seconds to wait for the client, which joins a while after the server starts

local waiting: { [string]: boolean } = { Ping = true, Move = true, Mark = true, Echo = true } -- What the client has yet to send
local failed: string? = nil

-- Keeps the first failure only, since everything after it is noise
local function fail(detail: string)
	failed = failed or detail
end

local function arrived(name: string)
	waiting[name] = nil
end

net.onFailure(function (player: Player?, kind: string, detail: string)
	fail(`{kind} from {player and player.Name or "nobody"}: {detail}`)
end)

net.Ping.on(function (player: Player, value: number)
	arrived("Ping")
	net.Pong.fire(player, value + 1)
end)

net.Move.on(function (player: Player, x: number, y: number)
	arrived("Move")
	net.Moved.fire(player, x, y)
end)

-- The one value the client cannot check from its side: an Instance through the side array
net.Mark.on(function (_, instance: Instance)
	if instance ~= workspace then
		fail(`Mark: got {instance:GetFullName()}`)
	end

	arrived("Mark")
end)

net.Echo.on(function (_, word: string): string
	arrived("Echo")
	return word:upper()
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
