--[[
    The client half of the Studio smoke test: requires its module late, so
    the server's Late messages are held for it, fires and invokes all it
    can, checks every answer, Late's order, each listener's server time and
    the parts Placed names, and prints Volt smoke: pass, or the first fault
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOAD_DELAY: number = 10 -- Seconds before the module is required, while the server already fires Late at us
local DEADLINE: number = 20 -- Seconds to wait for the server's answers and the rest of Late before reporting
local LATE: number = 600 -- The Late numbers the server fires, each to arrive once and in order
local PING: number = 7
local MOVE_X: number = 1.5 -- Exact in f32, so what comes back compares equal
local MOVE_Y: number = -2.5
local WORD: string = "volt"
local SHOUT: string = "bulk"
local YAW: number = 3.2 -- Each an end of its q16 range, which comes back exact
local PITCH: number = -1.6
local CLOCK_SECONDS: number = 5 -- How far the stamp a listener reads may be from this client's own server clock

-- One of each value Shapes carries, every number exact in f32, so what comes back compares equal
local LAYOUT: UDim2 = UDim2.new(0.5, 10, 1, -20)
local RANGE: NumberRange = NumberRange.new(1, 2)
local RECT: Rect = Rect.new(0, 0, 10, 20)
local RAY: Ray = Ray.new(Vector3.new(0, 5, 0), Vector3.new(0, 0, -100))
local REGION: Region3 = Region3.new(Vector3.zero, Vector3.new(4, 2, 8))

task.wait(LOAD_DELAY)

local Network = require(ReplicatedStorage:WaitForChild("Network"))

-- The answers still to arrive, Placed 3 never among them: it names a part only the server has, so it times out
local waiting: { [string]: boolean } = {
	Pong = true,
	Moved = true,
	Echo = true,
	Late = true,
	Shout = true,
	Aim = true,
	Shapes = true,
	["Placed 1"] = true,
	["Placed 2"] = true,
	Resolve = true,
}

local failed: string? = nil
local late: number = 0 -- The last Late number heard
-- The latest server time a listener read on each remote, which the next on it may never be before; the engine orders
-- neither remote against the other
local newest: { [string]: number } = { Reliable = 0, Unreliable = 0 }

-- Keeps the first failure only, since everything after it is noise
local function fail(detail: string)
	failed = failed or detail
end

-- An answer arrived; a wrong one is a failure naming what came
local function arrived(name: string, right: boolean, got: string)
	if not right then
		fail(`{name}: got {got}`)
	end

	waiting[name] = nil
end

-- The stamp of the message a listener hears: near this client's clock, and never going back on its remote
local function stamped(name: string, remote: string)
	local time: number = Network.serverTime()
	local now: number = workspace:GetServerTimeNow()

	if math.abs(now - time) > CLOCK_SECONDS then
		fail(`{name}: serverTime {time} is far from {now}`)
	elseif time < newest[remote] then
		fail(`{name}: serverTime went back on {remote} from {newest[remote]} to {time}`)
	end

	newest[remote] = time
end

-- Placed 3's part never streams in, so its one resolve failure is expected; any other failure is a fault
Network.onFailure(function (_, kind: string, detail: string)
	if kind == "resolve" and detail:match("^(.-): ") == "Placed" and waiting.Resolve then
		waiting.Resolve = nil
		return
	end

	fail(`{kind}: {detail}`)
end)

Network.Pong.on(function (value: number)
	stamped("Pong", "Reliable")
	arrived("Pong", value == PING + 1, tostring(value))
end)

Network.Moved.on(function (x: number, y: number)
	stamped("Moved", "Unreliable")
	arrived("Moved", x == MOVE_X and y == MOVE_Y, `{x}, {y}`)
end)

Network.Shout.on(function (text: string)
	stamped("Shout", "Reliable")
	arrived("Shout", text == SHOUT, text)
end)

Network.Aim.on(function (yaw: number, pitch: number)
	stamped("Aim", "Unreliable")
	arrived("Aim", yaw == YAW and pitch == PITCH, `{yaw}, {pitch}`)
end)

-- Every number once and in order, the held ones first, then the rest as the server fires them
Network.Late.on(function (index: number)
	stamped("Late", "Reliable")

	if index ~= late + 1 then
		fail(`Late: got {index} after {late}`)
	end

	late = index

	if late == LATE then
		waiting.Late = nil
	end
end)

-- The region by its CFrame and Size, since Region3.new is the only way to build one
Network.Shapes.on(function (layout: UDim2, range: NumberRange, rect: Rect, ray: Ray, region: Region3)
	stamped("Shapes", "Reliable")

	local same: boolean = layout == LAYOUT
		and range.Min == RANGE.Min
		and range.Max == RANGE.Max
		and rect.Min == RECT.Min
		and rect.Max == RECT.Max
		and ray.Origin == RAY.Origin
		and ray.Direction == RAY.Direction
		and region.CFrame == REGION.CFrame
		and region.Size == REGION.Size

	arrived("Shapes", same, `{layout}; {range}; {rect}; {ray}; {region.CFrame}; {region.Size}`)
end)

-- Placed 1 and 2 each with its own part, Smoke2's once it streams in; a message that waited for its part is read
-- under the stamp of the packet it came in, behind later ones, so it takes no part in the order checks
Network.Placed.on(function (part: BasePart, index: number)
	local name: string = `Placed {index}`
	arrived(name, waiting[name] == true and part.Name == `Smoke{index}`, part:GetFullName())
end)

-- The server places the parts when it hears Ping, so every listener above is connected first
Network.Ping.fire(PING)
Network.Move.fire(MOVE_X, MOVE_Y)
Network.Mark.fire(workspace)

-- The call yields this script until the server replies or the function's timeout passes
local ok: boolean, echoed: string = Network.Echo.invoke(WORD)
arrived("Echo", ok and echoed == WORD:upper(), echoed)

-- Once the Echo is back the handshake has been read, so the unreliable Aim cannot reach the server before it
Network.Shout.fire(SHOUT)
Network.Aim.fire(YAW, PITCH)
Network.Shapes.fire(LAYOUT, RANGE, RECT, RAY, REGION)

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
