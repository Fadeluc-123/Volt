--[[
    Times the two ways an async listener can be started: on a thread of
    its own from task.spawn for every call, or on a runner that waits
    between listeners and is resumed for each. Runs every scenario through
    both on the client and returns the table the coroutine pool's gates read
--]]

--!strict
--!native
local Players = game:GetService("Players")

local MESSAGES: number = 1000 -- Messages a frame, as the harness's busiest benches fire
local SECONDS: number = 5 -- How long each run dispatches for
local GAP: number = 1 -- Seconds after each run, in which its parked listeners finish
local RUNS: number = 2 -- Runs of each dispatcher a scenario, whose mean a gate reads
local THOUSAND: number = 1000 -- The cost is reported per thousand listener calls, in milliseconds
local PAYLOAD: { number } = { 1, 2, 3 } -- The second value every message carries, beside its index

-- Each dispatcher runs first and last in turn, so a drift across a scenario's runs falls on both alike
local ORDER: { string } = { "spawned", "pooled", "pooled", "spawned" }

-- Each scenario's listeners, how often each yields, and the gate pooled over spawned is held to there
local SCENARIOS: { Scenario } = {
	{ name = "1 listener, no yields", listeners = 1, gate = "G2", most = 1 },
	{ name = "4 listeners, no yields", listeners = 4, gate = "G1", most = 0.67, saves = 0.18 },
	{ name = "4 listeners, 1 in 100 calls yields", listeners = 4, every = 100, gate = "G2", most = 1 },
	{ name = "4 listeners, every call yields", listeners = 4, every = 1, gate = "G3", most = 1.5 },
}

type Frames = (seconds: number, body: () -> ()) -> { number }
type Runtime = {
	_runner: thread?, -- The runner waiting for the next listener, if one is
	_spawn: (callback: (...any) -> (), ...any) -> ...any, -- The transport's scheduler, which is task.spawn
}

type Dispatcher = (self: Runtime, listener: (...any) -> (), player: any, ...any) -> ()
type Scenario = {
	name: string,
	listeners: number,
	every: number?, -- Each listener waits a frame on its every-th call
	gate: string,
	most: number, -- The most pooled over spawned may be
	saves: number?, -- The least spawned less pooled must be, in milliseconds per thousand calls
}

local Dispatch = {}

-- Calls a listener with the player first on the server and with the values alone on the client
local function invoke(listener: (...any) -> (), player: any, ...: any)
	if player == nil then
		return listener(...)
	end
	return listener(player, ...)
end

-- Runs one async listener on the runner resuming it; true when that runner waits for the next
local function serve(self: Runtime, listener: (...any) -> (), player: any, ...: any): boolean
	local thread: thread? = self._runner -- Only the waiting runner is ever resumed, so this is the one running
	self._runner = nil -- Taken: a listener that yields keeps it, and the next listener gets another

	invoke(listener, player, ...)

	if self._runner then
		return false -- Another runner began waiting while this listener ran or yielded, so this one ends
	end

	self._runner = thread
	return true
end

-- Waits between listeners, so listeners that never yield all run on one thread
local function runner(self: Runtime)
	local waiting: boolean = true

	while waiting do
		waiting = serve(self, coroutine.yield())
	end
end

-- The pool's async branch: the waiting runner takes the listener, or a new one when every runner is held by a yield
local function pooled(self: Runtime, listener: (...any) -> (), player: any, ...: any)
	local thread: thread? = self._runner
	if not thread then
		thread = self._spawn(runner, self) -- Runs to its first yield and returns the thread waiting there
		self._runner = thread
	end

	self._spawn(thread :: any, listener, player, ...)
end

-- The runtime's async branch: every listener on a thread of its own
local function spawned(self: Runtime, listener: (...any) -> (), player: any, ...: any)
	self._spawn(invoke, listener, player, ...)
end

-- The middle value of a list
local function median(values: { number }): number
	local sorted: { number } = table.clone(values)
	table.sort(sorted)

	return sorted[math.max(1, #sorted // 2)]
end

-- A figure as the report prints it
local function figure(value: number): string
	return string.format("%.3f", value)
end

--[[
    Dispatches MESSAGES a frame to the scenario's listeners for SECONDS,
    then waits out the gap. Returns the median of the milliseconds a
    thousand listener calls took each frame and the median frame rate
--]]

local function measure(frames: Frames, dispatch: Dispatcher, scenario: Scenario, player: Player): (number, number)
	local state: Runtime = { _runner = nil, _spawn = task.spawn }
	local every: number? = scenario.every
	local counts: { number } = table.create(scenario.listeners, 0)
	local listeners: { (...any) -> () } = {}
	local calls: number = MESSAGES * scenario.listeners
	local costs: { number } = {}

	-- Each listener counts its own calls, which also says when it is due to yield
	for index = 1, scenario.listeners do
		listeners[index] = function (_: Player, _: number, _: { number })
			local count: number = counts[index] + 1
			counts[index] = count

			if every and count % every == 0 then
				task.wait()
			end
		end
	end

	local fps: { number } = frames(SECONDS, function ()
		local started: number = os.clock()

		for message = 1, MESSAGES do
			for _, listener in listeners do
				dispatch(state, listener, player, message, PAYLOAD)
			end
		end

		table.insert(costs, (os.clock() - started) * THOUSAND * THOUSAND / calls)
	end)

	task.wait(GAP)

	-- Every call made must have reached its listener, or the run timed something other than dispatch
	local reached: number = 0
	local made: number = #costs * calls

	for _, count: number in counts do
		reached += count
	end

	if reached ~= made then
		warn(`{scenario.name}: {reached} of {made} listener calls ran`)
	end

	return median(costs), median(fps)
end

--[[
    Runs every scenario through both dispatchers in ORDER and returns the
    report: a row per run, then each scenario's pooled cost over its
    spawned cost, each the mean of its runs, beside the gate it is held to
--]]

function Dispatch.run(frames: Frames): string
	local player: Player = Players.LocalPlayer
	local lines: { string } = {
		`\n## Dispatch ({MESSAGES} messages a frame, {SECONDS} s per run)\n`,
		"| Scenario | Run | ms per 1000 calls | FPS median |",
		"|---|---|---|---|",
	}
	
	local gates: { string } = {
		`\nPooled against spawned, each the mean of its {RUNS} runs, beside the gate it is held to.\n`,
		"| Gate | Scenario | Spawned ms | Pooled ms | Pooled / spawned | Spawned - pooled ms | Needs | Holds |",
		"|---|---|---|---|---|---|---|---|",
	}

	for _, scenario: Scenario in SCENARIOS do
		local means: { [string]: number } = { spawned = 0, pooled = 0 }

		for _, kind: string in ORDER do
			print(`Dispatching {scenario.name} {kind}`)

			local cost: number, fps: number = measure(frames, kind == "pooled" and pooled or spawned, scenario, player)

			means[kind] += cost / RUNS
			table.insert(lines, `| {scenario.name} | {kind} | {figure(cost)} | {fps} |`)
		end

		local ratio: number = means.pooled / means.spawned
		local saved: number = means.spawned - means.pooled
		local saves: number? = scenario.saves
		local holds: boolean = ratio <= scenario.most and (saves == nil or saved >= saves)
		local needs: string = `pooled / spawned <= {figure(scenario.most)}`

		if saves then
			needs = `{needs} and spawned - pooled >= {figure(saves)} ms`
		end

		local measured: string = `{figure(means.spawned)} | {figure(means.pooled)} | {figure(ratio)} | {figure(saved)}`

		table.insert(gates, `| {scenario.gate} | {scenario.name} | {measured} | {needs} | {holds and "yes" or "no"} |`)
	end

	table.move(gates, 1, #gates, #lines + 1, lines)

	return table.concat(lines, "\n")
end

return Dispatch
