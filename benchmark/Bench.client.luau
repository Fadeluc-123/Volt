--[[
    The client half of the benchmark: for every bench and every library,
    fires the bench's event a fixed number of times a frame for a fixed
    time, keeping the frame rate and the cost of the fires, asks the
    server what arrived in that window, and hands it the report to print
    and keep
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Benchmark: Folder = ReplicatedStorage:WaitForChild("Benchmark")
local Benches = require(Benchmark.Benches)
local Modes = require(Benchmark.Modes)

local Sample: RemoteFunction = Benchmark.Sample
local Done: RemoteEvent = Benchmark.Done

local SECONDS: number = 10 -- How long each run fires for
local POOL: number = 32 -- Payloads built up front and cycled through, so consecutive fires never send the same bytes
local IDLE_KBPS: number = 0.5 -- Outgoing traffic below this means the last run's packets have gone
local REST: number = 5 -- Seconds of quiet between runs
local THOUSAND: number = 1000 -- The fire cost is reported per thousand fires, in milliseconds
local PERCENT: number = 100
local NARROW: number = 1 -- A field of view that renders nothing, so the frame rate is the fires' cost

type Bench = Benches.Bench
type Mode = Modes.Mode
type Counts = { received: number, packets: number, bytes: number }
type Run = { fps: { number }, cost: { number }, sent: number, received: number, packets: number, bytes: number }
type Results = { [string]: { [string]: Run } }

-- Waits until the last run's packets have left, then rests, so one run's traffic never lands in the next one's window
local function settle()
	while Stats.DataSendKbps > IDLE_KBPS do
		RunService.Heartbeat:Wait()
	end

	task.wait(REST)
end

-- The middle value of a list
local function median(values: { number }): number
	local sorted: { number } = table.clone(values)
	table.sort(sorted)

	return sorted[math.max(1, #sorted // 2)]
end

--[[
    Fires one bench through one library for SECONDS, keeping the frames
    of each second and the milliseconds a thousand fires took each frame,
    then reads what the server counted in that window
--]]

local function run(mode: Mode, bench: Bench): Run
	local fire = mode.fire(bench.name)
	local pool: { any } = Benches.pool(bench, POOL)
	local before: Counts = Sample:InvokeServer()

	local fps: { number } = {}
	local cost: { number } = {}
	local frames: number = 0
	local elapsed: number = 0
	local sent: number = 0

	local connection = RunService.PostSimulation:Connect(function (delta: number)
		frames += 1
		elapsed += delta

		if elapsed >= 1 then
			table.insert(fps, frames)
			frames = 0
			elapsed -= 1
		end

		local started: number = os.clock()

		for _ = 1, bench.perFrame do
			fire(pool[sent % POOL + 1])
			sent += 1
		end

		table.insert(cost, (os.clock() - started) * THOUSAND * THOUSAND / bench.perFrame)
	end)

	task.wait(SECONDS)
	connection:Disconnect()
	settle()

	local after: Counts = Sample:InvokeServer()

	return {
		fps = fps,
		cost = cost,
		sent = sent,
		received = after.received - before.received,
		packets = after.packets - before.packets,
		bytes = after.bytes - before.bytes,
	}
end

-- The report as markdown, a table per bench with a row per library
local function report(results: Results): string
	-- selene: allow(undefined_variable)
	local lines: { string } = { `Studio {version()}, {SECONDS} s per run, {POOL} payloads cycled.` }

	for _, bench in Benches.list do
		table.insert(lines, `\n## {bench.name} ({bench.perFrame} fires a frame)\n`)
		table.insert(
			lines,
			"| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |"
		)
		table.insert(lines, "|---|---|---|---|---|---|---|")

		for _, mode in Modes.list do
			local result: Run = results[bench.name][mode.name]
			local received: number = result.received
			local bytes: string = received > 0 and result.bytes > 0 and string.format("%.1f", result.bytes / received)
				or "-"
			local loss: number = (1 - received / result.sent) * PERCENT
			local cost: string = string.format("%.3f", median(result.cost))
			local packets: number = result.packets // SECONDS

			table.insert(
				lines,
				`| {mode.name} | {median(result.fps)} | {math.min(table.unpack(result.fps))} | {cost} | {bytes} | {packets} | {string.format(
					"%.0f",
					loss
				)}% |`
			)
		end
	end

	return table.concat(lines, "\n")
end

workspace.CurrentCamera.FieldOfView = NARROW

settle()

local results: Results = {}

for _, bench in Benches.list do
	results[bench.name] = {}

	for _, mode in Modes.list do
		print(`Running {bench.name} through {mode.name}`)
		results[bench.name][mode.name] = run(mode, bench)
	end
end

local text: string = report(results)

print(text)
Done:FireServer(text)
