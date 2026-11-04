--[[
    The server half of the Studio smoke test: checks the scope's remotes,
    answers all the client sends, fires Late, Placed and the largest payloads
    at the player, and prints Volt smoke: pass, or the first fault
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local Network = require(ServerScriptService.Network)

local JOIN_SECONDS: number = 300 -- Seconds to wait for a join, as Studio can start the player's window long after us
local DEADLINE: number = 60 -- Seconds from the player's join to wait for the client, which loads late
local LATE: number = 600 -- Late messages fired at a joiner, one a frame, while their client has yet to load its module
local REMOTES: string = "Reliable Unreliable" -- Every remote the scope's folder may hold, sorted, a channel adding none
local NEAR: Vector3 = Vector3.new(0, 4, 12) -- Beside the spawn at the origin, well inside any streaming radius
local FAR: Vector3 = Vector3.new(5000, 4, 12) -- Past any streaming radius, so the client has nothing there
local GAP: Vector3 = Vector3.new(6, 0, 0) -- Between Smoke1 and where Smoke2 moves to, so the two stand apart
local MOVE_SECONDS: number = 1 -- How long Smoke2 stays far away before it moves beside the spawn and streams in
local REPLY_TEXT: number = 16390 -- Reply's text, which with its id is as large as Decree's largest run reply
local REPLY_FILL: string = "r" -- Every byte of Reply's text
local LINES: number = 15 -- The Lines fired in one frame, numbered from 1, which go as one packet
local LINE_TEXT: number = 16386 -- Each Line's text, which with its id and number is as large as Decree's largest line
local FLUSH_SECONDS: number = 5 -- How long the server waits for the flush that sends Reply, due at the next Heartbeat

type Bot = Volt.Bot
type Chain = Network.Chain

-- What the client has yet to send, and the Late messages still to fire
local waiting: { [string]: boolean } = {
	Ping = true,
	Move = true,
	Mark = true,
	Echo = true,
	Late = true,
	Shout = true,
	Aim = true,
	Shapes = true,
	Deep = true,
	Payloads = true,
}
local failed: string? = nil
local joined: number? = nil -- When the player joined, from which DEADLINE counts

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

-- Sent back as the server read it, so the deepest chain is read and written on both sides
Network.Deep.on(function (player: Player | Bot, value: Chain)
	arrived("Deep")
	Network.Deep.fire(player, value)
end)

--[[
    Fires Reply, the only message the player is sent that frame, then,
    once its flush has sent it, the fifteen Lines in one later frame, each
    its number and that number repeated, so each packet holds only them;
    a flush that never comes is the failure, and no Line is fired
--]]

Network.Payloads.on(function (player: Player | Bot)
	local sent: number = Network.stats(player).packetsOut
	local texts: { string } = {}

	-- Built before any fire, so the fifteen go in one run with nothing built between them
	for index: number = 1, LINES do
		texts[index] = string.rep(string.char(index), LINE_TEXT)
	end

	Network.Reply.fire(player, string.rep(REPLY_FILL, REPLY_TEXT))

	-- A player who left reads fresh counters at zero, so only a count past the one before Reply means it went
	local deadline: number = os.clock() + FLUSH_SECONDS
	while Network.stats(player).packetsOut <= sent and not failed and os.clock() < deadline do
		task.wait()
	end

	if Network.stats(player).packetsOut <= sent then
		return fail("Payloads: Reply's flush never came")
	end

	for index: number = 1, LINES do
		Network.Line.fire(player, index, texts[index])
	end

	arrived("Payloads")
end)

-- Connected after the module, as a game's own is; the server lives as long as the place, so nothing disconnects it
Players.PlayerAdded:Connect(function (player: Player)
	joined = joined or os.clock()

	for index: number = 1, LATE do
		Network.Late.fire(player, index)
		task.wait()
	end

	arrived("Late")
end)

-- Waits JOIN_SECONDS from the start for the player to join, then DEADLINE from their join
local started: number = os.clock()
while next(waiting) and not failed and os.clock() < (joined and joined + DEADLINE or started + JOIN_SECONDS) do
	task.wait()
end

-- Every message still missing, sorted so the line names them all in one order
local missing: { string } = {}

for name: string in waiting do
	table.insert(missing, name)
end

table.sort(missing)

if failed then
	warn(`Volt smoke: {failed}`)
elseif not joined then
	warn(`Volt smoke: no player joined within {JOIN_SECONDS} seconds`)
elseif #missing > 0 then
	warn(`Volt smoke: never heard {table.concat(missing, ", ")}`)
else
	print("Volt smoke: pass")
end
