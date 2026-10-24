--[[
    The libraries the benchmark drives, one row each, and the three things
    the harness does with any of them: get the function that fires a
    bench's event on the client, the one that flushes a frame's fires, and
    listen for the event on the server. A generated library is reached by
    the folder its compiler wrote into; the raw remote is the baseline
--]]

--!strict
local RunService = game:GetService("RunService")

local Benches = require(script.Parent.Benches)

export type Mode = {
	name: string,
	fire: (bench: string) -> (data: any) -> (),
	on: (bench: string, callback: (player: Player, data: any) -> ()) -> (),
	flush: (() -> ())?, -- Sends what the frame's fires wrote; the raw remote has none, since each fire is its own packet
}

type Row = { name: string, folder: string, fire: string, on: string, flush: string }

-- Each generated library, its folder under Generated, and what it calls fire, listen and flush
local ROWS: { Row } = {
	{ name = "blink", folder = "Blink", fire = "Fire", on = "On", flush = "StepReplication" },
	{ name = "zap", folder = "Zap", fire = "Fire", on = "SetCallback", flush = "SendEvents" },
	{ name = "zapUnchecked", folder = "ZapUnchecked", fire = "Fire", on = "SetCallback", flush = "SendEvents" },
	{ name = "volt", folder = "Volt", fire = "fire", on = "on", flush = "flush" },
	{ name = "voltUnchecked", folder = "VoltUnchecked", fire = "fire", on = "on", flush = "flush" },
}

local isServer: boolean = RunService:IsServer()
local Benchmark: Instance = script.Parent
local Generated: Instance = Benchmark.Generated

local Modes = { list = {} :: { Mode } }

-- One raw remote per bench, made here on the server and awaited on the client
local remotes: { [string]: any } = {}

for _, bench in Benches.list do
	if isServer then
		local remote: Instance = Instance.new(bench.unreliable and "UnreliableRemoteEvent" or "RemoteEvent")
		remote.Name = bench.name
		remote.Parent = Benchmark
		remotes[bench.name] = remote
	else
		remotes[bench.name] = Benchmark:WaitForChild(bench.name)
	end
end

table.insert(Modes.list, {
	name = "roblox",
	fire = function (bench: string)
		local remote = remotes[bench]

		return function (data: any)
			remote:FireServer(data)
		end
	end,
	on = function (bench: string, callback)
		remotes[bench].OnServerEvent:Connect(callback)
	end,
})

for _, row in ROWS do
	local module = require(Generated[row.folder][isServer and "Server" or "Client"])

	table.insert(Modes.list, {
		name = row.name,
		fire = function (bench: string)
			return module[bench][row.fire]
		end,
		on = function (bench: string, callback)
			module[bench][row.on](callback)
		end,
		flush = module[row.flush],
	})
end

return Modes
