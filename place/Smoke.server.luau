--[[
    The server half of the Studio smoke test: checks the scope's folder
    holds its two remotes and no other, hears and answers every event the
    client fires, serves its function, fires Late at a joiner and Placed
    naming three parts, and prints Volt smoke: pass, or the first fault
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local Network = require(ServerScriptService.Network)

local DEADLINE: number = 40 -- Seconds to wait for the client, which joins a while after the server and loads late
local LATE: number = 600 -- Late messages fired at a joiner, one a frame, while their client has yet to load its module
local REMOTES: string = "Reliable Unreliable" -- Every remote the scope's folder may hold, sorted, a channel adding none
local NEAR: Vector3 = Vector3.new(0, 4, 12) -- Beside the spawn at the origin, well inside any streaming radius
local FAR: Vector3 = Vector3.new(5000, 4, 12) -- Past any streaming radius, so the client has nothing there
local GAP: Vector3 = Vector3.new(6, 0, 0) -- Between Smoke1 and where Smoke2 moves to, so the two stand apart
local MOVE_SECONDS: number = 1 -- How long Smoke2 stays far away before it moves beside the spawn and streams in

type Bot = Volt.Bot

-- What the client has yet to send, and the Late messages still to fire
local waiting: { [string]: boolean } =
	{ Ping = true, Move = true, Mark = true, Echo = true, Late = true, Shout = true, Aim = true, Shapes = true }
local failed: string? = nil

-- Keeps the first failure only, since everything after it is noise
local function fail(detail: string)
	failed = failed or detail
end

-- Bulk rides Reliable and the References folder is a Folder, so neither adds a remote to the scope's folder
local function remotesOnly()
	local remotes: { string } = {}

	for _, child: Instance in ReplicatedStorage.Volt.Smoke:GetChildren() do
		if child:IsA("BaseRemoteEvent") then
			table.insert(remotes, child.Name)
		end
	end

	table.sort(remotes)

	if table.concat(remotes, " ") ~= REMOTES then
		fail(`the scope's folder holds the remotes {table.concat(remotes, " ")}`)
	end
end

-- The require above made the scope's folder without waiting
remotesOnly()

local function arrived(name: string)
	waiting[name] = nil
end

-- An anchored part, so it stays where it is put
local function part(name: string, position: Vector3, parent: Instance): BasePart
	local made: Part = Instance.new("Part")

	made.Name = name
	made.Anchored = true
	made.Position = position
	made.Parent = parent

	return made
end

--[[
    Fires Placed three times in one frame: Smoke1 beside the spawn, which
    streams in at once; Smoke2 far away, whose message waits until it
    moves beside the spawn a second later; and a part kept in
    ServerStorage, which never reaches the client and times out
--]]

local function place(player: Player | Bot)
	local near: BasePart = part("Smoke1", NEAR, workspace)
	local far: BasePart = part("Smoke2", FAR, workspace)

	Network.Placed.fire(player, near, 1)
	Network.Placed.fire(player, far, 2)
	Network.Placed.fire(player, part("Smoke3", NEAR, ServerStorage), 3)

	task.delay(MOVE_SECONDS, function ()
		far.Position = NEAR + GAP
	end)

	-- The first fire made the References folder beside the remotes
	local references: Instance? = ReplicatedStorage.Volt.Smoke:FindFirstChild("References")

	if not (references and references:IsA("Folder")) then
		fail("the scope's folder holds no References folder")
	end

	remotesOnly()
end

-- A departed here would mean a fire from the game's own PlayerAdded was dropped
Network.onFailure(function (player: (Player | Bot)?, kind: string, detail: string)
	fail(`{kind} from {player and player.Name or "nobody"}: {detail}`)
end)

-- The client's first fire, once its module is loaded and its listeners are connected
Network.Ping.on(function (player: Player | Bot, value: number)
	arrived("Ping")
	Network.Pong.fire(player, value + 1)
	place(player)
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

-- Sent back on the channel it came on
Network.Shout.on(function (player: Player | Bot, text: string)
	arrived("Shout")
	Network.Shout.fire(player, text)
end)

-- Sent back with the server's own next sequence for the player
Network.Aim.on(function (player: Player | Bot, yaw: number, pitch: number)
	arrived("Aim")
	Network.Aim.fire(player, yaw, pitch)
end)

-- Sent back as the server read them, so the client checks what Roblox's own constructors rebuilt on both sides
Network.Shapes.on(
	function (player: Player | Bot, layout: UDim2, range: NumberRange, rect: Rect, ray: Ray, region: Region3)
		arrived("Shapes")
		Network.Shapes.fire(player, layout, range, rect, ray, region)
	end
)

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
