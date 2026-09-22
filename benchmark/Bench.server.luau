--[[
    The server half of the benchmark: listens for every bench through
    every library, counting what arrives and checking the first payload
    of each against the one the client builds first, taps every remote
    under ReplicatedStorage for packets and bytes, answers the client's
    samples, and leaves the finished report where the run script finds it
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Benchmark: Folder = ReplicatedStorage.Benchmark
local Benches = require(Benchmark.Benches)
local Modes = require(Benchmark.Modes)

local Sample: RemoteFunction = Benchmark.Sample
local Done: RemoteEvent = Benchmark.Done

local counts = { received = 0, packets = 0, bytes = 0 }

-- Whether two payloads are the same value, table by table
local function same(a: any, b: any): boolean
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return a == b
	end

	for key, value in a do
		if not same(value, b[key]) then
			return false
		end
	end

	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

-- Every remote under ReplicatedStorage, whichever library made it, counts its packets and the bytes of any buffer they carry
local function tap(instance: Instance)
	if not instance:IsA("RemoteEvent") and not instance:IsA("UnreliableRemoteEvent") then
		return
	end

	(instance :: any).OnServerEvent:Connect(function (_, first: any)
		counts.packets += 1

		if typeof(first) == "buffer" then
			counts.bytes += buffer.len(first)
		end
	end)
end

for _, descendant: Instance in ReplicatedStorage:GetDescendants() do
	tap(descendant)
end

ReplicatedStorage.DescendantAdded:Connect(tap)

for _, bench in Benches.list do
	local expected: any = Benches.pool(bench, 1)[1]

	for _, mode in Modes.list do
		local checked: boolean = false

		mode.on(bench.name, function (_, data: any)
			counts.received += 1

			if checked then
				return
			end

			checked = true

			if same(expected, data) then
				print(`{mode.name} passed {bench.name}`)
			else
				warn(`{mode.name} received the wrong {bench.name}`)
			end
		end)
	end
end

Sample.OnServerInvoke = function ()
	return counts
end

-- The run script under run-in-roblox waits for this value and prints it
Done.OnServerEvent:Connect(function (_, text: string)
	local result: StringValue = Instance.new("StringValue")
	result.Name = "Result"
	result.Value = text
	result.Parent = game

	print(text)
end)
