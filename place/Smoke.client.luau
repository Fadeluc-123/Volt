--[[
    The client half of the Studio smoke test: fires every event Smoke.volt
    lets a client fire, invokes its function, listens for the server's
    answers, and prints Volt smoke: pass once every answer has arrived
    with the value expected, or the first thing that went wrong
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local net = require(ReplicatedStorage:WaitForChild("Net"))

local DEADLINE: number = 10 -- Seconds to wait for the server's answers before reporting what never came
local PING: number = 7
local MOVE_X: number = 1.5 -- Exact in f32, so what comes back compares equal
local MOVE_Y: number = -2.5
local WORD: string = "volt"

local waiting: { [string]: boolean } = { Pong = true, Moved = true, Echo = true } -- The answers still to arrive
local failed: string? = nil

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

net.onFailure(function (_, kind: string, detail: string)
	fail(`{kind}: {detail}`)
end)

net.Pong.on(function (value: number)
	arrived("Pong", value == PING + 1, tostring(value))
end)

net.Moved.on(function (x: number, y: number)
	arrived("Moved", x == MOVE_X and y == MOVE_Y, `{x}, {y}`)
end)

net.Ping.fire(PING)
net.Move.fire(MOVE_X, MOVE_Y)
net.Mark.fire(workspace)

-- The call yields this script until the server replies or the function's timeout passes
local ok: boolean, echoed: string = net.Echo.invoke(WORD)
arrived("Echo", ok and echoed == WORD:upper(), echoed)

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
