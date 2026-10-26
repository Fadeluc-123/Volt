--[[
    The client half of the Studio smoke test: requires its module late, so
    the server's Late messages are held for it, fires every event, invokes
    the function, checks every answer and every Late number in order, and
    prints Volt smoke: pass once all of it arrived, or the first fault
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

task.wait(LOAD_DELAY)

local Network = require(ReplicatedStorage:WaitForChild("Network"))

local waiting: { [string]: boolean } = { Pong = true, Moved = true, Echo = true, Late = true } -- The answers still to arrive
local failed: string? = nil
local late: number = 0 -- The last Late number heard

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

Network.onFailure(function (_, kind: string, detail: string)
	fail(`{kind}: {detail}`)
end)

Network.Pong.on(function (value: number)
	arrived("Pong", value == PING + 1, tostring(value))
end)

Network.Moved.on(function (x: number, y: number)
	arrived("Moved", x == MOVE_X and y == MOVE_Y, `{x}, {y}`)
end)

-- Every number once and in order, the held ones first, then the rest as the server fires them
Network.Late.on(function (index: number)
	if index ~= late + 1 then
		fail(`Late: got {index} after {late}`)
	end

	late = index

	if late == LATE then
		waiting.Late = nil
	end
end)

Network.Ping.fire(PING)
Network.Move.fire(MOVE_X, MOVE_Y)
Network.Mark.fire(workspace)

-- The call yields this script until the server replies or the function's timeout passes
local ok: boolean, echoed: string = Network.Echo.invoke(WORD)
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
