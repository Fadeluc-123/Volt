--[[
    The server half of the benchmark: listens for every bench through
    every library, counting what arrives and when, checking the first
    payload of each against the client's, tapping every remote for its
    packets and bytes, stepping no faster than a live server, and leaving
    the finished report where the run script finds it
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Benchmark: Folder = ReplicatedStorage.Benchmark
local Benches = require(Benchmark.Benches)
local Modes = require(Benchmark.Modes)

local Sample: RemoteFunction = Benchmark.Sample
local Done: RemoteEvent = Benchmark.Done

local GAP: number = 1 -- Seconds without messages after which a busy frame opens a new receive window rather than extending one
local RATE: number = 60 -- Heartbeats a second a live server steps at; a quicker frame is spun out to its share of a second

local counts = { received = 0, packets = 0, bytes = 0, spanned = 0, receive = 0, frames = 0, seconds = 0 }
local frame = { count = 0, first = 0, last = 0, at = 0, since = 0, stepped = 0 } -- This frame's messages so far, when its first and last came, when the last busy Heartbeat was and the Heartbeats since it, and when the last Heartbeat's spin ended

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
			local now: number = os.clock()

			counts.received += 1
			frame.count += 1
			frame.last = now

			if frame.count == 1 then
				frame.first = now
			end

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

--[[
    Closes the frame: a frame that carried two or more messages adds
    them and the span from its first to its last, scaled up for the first
    one's own read, which the span misses, then the frames and seconds
    since the last such frame, idle frames between packets included, so
    the server's rate while a run's packets arrive is known however far
    past the client's window it runs. Then spins until a live server's
    frame has passed since the last one ended, so every library's server
    steps at one rate and takes one share of the machine the client shares
--]]

RunService.Heartbeat:Connect(function ()
	local count: number = frame.count
	local now: number = os.clock()

	frame.since += 1

	if count > 1 then
		counts.spanned += count
		counts.receive += (frame.last - frame.first) * count / (count - 1)

		if now - frame.at < GAP then
			counts.frames += frame.since
			counts.seconds += now - frame.at
		end

		frame.at = now
		frame.since = 0
	end

	frame.count = 0

	-- Measured from where the last spin ended, not from this Heartbeat, so the engine's work between frames counts
	local deadline: number = frame.stepped + 1 / RATE
	local spun: number = 0

	while os.clock() < deadline do
		spun += 1
	end

	frame.stepped = os.clock()
end)

-- The counts so far
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
