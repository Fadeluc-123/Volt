--[[
    What run-in-roblox runs inside Studio: it waits for the report the
    server leaves under the DataModel and prints it after a marker line,
    which is what tools/bench reads back. In edit mode it first asks for
    F5, and the report never arrives there, which holds the script open
    until Studio closes; the play session's copy of the script finds it
--]]

--!strict
local RunService = game:GetService("RunService")

local MARKER: string = "--VOLT BENCHMARK--"
local POLL: number = 1 -- Seconds between looks for the report

if not RunService:IsRunning() then
	print("Press F5 to start the benchmark")
end

local result: Instance? = game:FindFirstChild("Result")

while not result do
	task.wait(POLL)
	result = game:FindFirstChild("Result")
end

print(MARKER)
print((result :: StringValue).Value)
