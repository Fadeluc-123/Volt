--[[
    The client half of the benchmark: for every bench and every library,
    fires the bench's event a fixed number of times a frame for a fixed
    time, keeping the frame rate and the cost of the fires and the flush,
    asks the server what arrived in that window and what receiving it
    cost, and hands it the report to print and keep
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Benchmark = ReplicatedStorage:WaitForChild("Benchmark")
local Benches = require(Benchmark.Benches)
local Dispatch = require(Benchmark.Dispatch)
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
type Counts = {
	received: number,
	packets: number,
	bytes: number,
	spanned: number,
	receive: number,
	frames: number,
	seconds: number,
}

type Run = {
	fps: { number },
	cost: { number },
	flush: { number },
	sent: number,
	received: number,
	packets: number,
	bytes: number,
	spanned: number, -- Messages that arrived in server frames carrying two or more, whose spans are timed
	receive: number, -- Seconds the server spent from the first to the last message of those frames
	frames: number, -- Server frames while the run's packets arrived, idle ones between packets included
	seconds: number, -- Seconds those frames took, so the server's frame rate under the run is frames over this
	lag: number, -- Seconds the first sample after the run took, which is what the server still had to read through
}

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

-- A millisecond figure as the report prints it
local function ms(value: number): string
	return string.format("%.3f", value)
end

-- The frames of each second for some seconds, with a body run every PostSimulation frame
local function frames(seconds: number, body: () -> ()): { number }
	local fps: { number } = {}
	local count: number = 0
	local elapsed: number = 0

	local connection = RunService.PostSimulation:Connect(function (delta: number)
		count += 1
		elapsed += delta

		if elapsed >= 1 then
			table.insert(fps, count)
			count = 0
			elapsed -= 1
		end

		body()
	end)

	task.wait(seconds)
	connection:Disconnect()

	return fps
end

--[[
    Fires one bench through one library for SECONDS, keeping the frames
    of each second, the milliseconds a thousand fires took each frame and
    the milliseconds the library's flush took, then reads what the server
    counted in that window and how long it spent receiving it
--]]

local function run(mode: Mode, bench: Bench): Run
	local fire = mode.fire(bench.name)
	local flush = mode.flush
	local pool: { any } = Benches.pool(bench, POOL)
	local before: Counts = Sample:InvokeServer()

	local cost: { number } = {}
	local flushes: { number } = {}
	local sent: number = 0

	local fps: { number } = frames(SECONDS, function ()
		local started: number = os.clock()

		for _ = 1, bench.perFrame do
			fire(pool[sent % POOL + 1])
			sent += 1
		end

		local fired: number = os.clock()

		-- Flushed here so the flush is timed on its own; the library's own Heartbeat flush then finds nothing to send
		if flush then
			flush()
		end

		table.insert(cost, (fired - started) * THOUSAND * THOUSAND / bench.perFrame)
		table.insert(flushes, (os.clock() - fired) * THOUSAND)
	end)

	-- The first sample waits behind whatever the server has still to read, so its round trip is that backlog
	local asked: number = os.clock()
	Sample:InvokeServer()
	local lag: number = os.clock() - asked

	settle()

	local after: Counts = Sample:InvokeServer()

	return {
		fps = fps,
		cost = cost,
		flush = flushes,
		sent = sent,
		received = after.received - before.received,
		packets = after.packets - before.packets,
		bytes = after.bytes - before.bytes,
		spanned = after.spanned - before.spanned,
		receive = after.receive - before.receive,
		frames = after.frames - before.frames,
		seconds = after.seconds - before.seconds,
		lag = lag,
	}
end

-- The report as markdown, two tables per bench with a row per library: the comparison, then where a frame goes
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
			local packets: number = result.packets // SECONDS

			table.insert(
				lines,
				`| {mode.name} | {median(result.fps)} | {math.min(table.unpack(result.fps))} | {ms(median(result.cost))} | {bytes} | {packets} | {string.format(
					"%.0f",
					loss
				)}% |`
			)
		end

		table.insert(
			lines,
			"\nWhere a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.\n"
		)
		table.insert(lines, "| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |")
		table.insert(lines, "|---|---|---|---|---|---|---|---|")

		for _, mode in Modes.list do
			local result: Run = results[bench.name][mode.name]
			local frame: number = THOUSAND / median(result.fps)
			local fires: number = median(result.cost) * bench.perFrame / THOUSAND
			local flush: number = mode.flush and median(result.flush) or 0
			local other: number = frame - fires - flush
			local receive: number = result.spanned > 0 and result.receive / result.spanned * THOUSAND * THOUSAND or 0
			local server: number = result.seconds > 0 and result.frames // result.seconds or 0

			table.insert(
				lines,
				`| {mode.name} | {ms(frame)} | {ms(fires)} | {mode.flush and ms(flush) or "-"} | {ms(other)} | {ms(
					receive
				)} | {server} | {ms(result.lag)} |`
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

local text: string = `{report(results)}\n{Dispatch.run(frames)}`

print(text)
Done:FireServer(text)
