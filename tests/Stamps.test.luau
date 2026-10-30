--[[
    Proves the server-time stamp end to end, over the modules of
    Streams.volt and the mock: a listener hears its value alone and reads
    the stamp through serverTime; a queued message keeps its packet's
    stamp inside iter; an unreliable split leaves room for the byte and the
    stamp; and serverTime is on a stamped client alone, in every casing
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Streamed = require("./Streamed")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local compiled = Streamed.compiled
local connected = Streamed.connected
local steps = Streamed.steps

type Fired = Streamed.Fired
type Harness = Streamed.Harness
type Mock = Volt.Mock
type Modules = Streamed.Modules
type Transport = Volt.Transport

local STAMP: number = 1761700000.25 -- The server time of the design's worked example
local TICKS: number = 400 -- Tick fires of three bytes in one frame, more than one packet of the budget holds

-- The accessor's name in each casing
local CASINGS: { [string]: string } = { camel = "serverTime", pascal = "ServerTime", snake = "server_time" }

-- Both modules of a schema over a mock of their own, whose failure handler a casing renames
local function loaded(modules: Modules): (any, any)
	local mock: Mock = Volt.mock(task.spawn)
	local _, transport: Transport = mock:join("Alice")

	return (Generated.module("Server", modules.server, mock.server)),
		(Generated.module("Client", modules.client, transport))
end

describe("Stamps", function ()
	test("a Notice listener hears its value alone and reads the flush's time from serverTime", function ()
		local harness: Harness = connected()
		local heard: string = "nothing"

		harness.client.Notice.on(function (...: any)
			heard = `{select("#", ...)} {(...)} {harness.client.serverTime()}`
		end)

		harness.mock.time = STAMP
		harness.server.Notice.fire(harness.alice, 3)
		steps(harness, 2)

		expect(heard).is(`1 3 {STAMP}`)
	end)

	test("two Ticks from flushes at 10 and 20 read 10 then 20 inside iter, and 20 after it", function ()
		local harness: Harness = connected()
		local times: { string } = {}

		harness.mock.time = 10
		harness.server.Tick.fire(harness.alice, 1)
		harness.mock:step()

		harness.mock.time = 20
		harness.server.Tick.fire(harness.alice, 2)
		steps(harness, 2)

		for _, value: number in harness.client.Tick.iter() do
			table.insert(times, `{value} at {harness.client.serverTime()}`)
		end

		table.insert(times, `after at {harness.client.serverTime()}`)

		expect(table.concat(times, ",")).is("1 at 10,2 at 20,after at 20")
	end)

	test("a frame of Ticks past the budget splits into packets that fit it, byte and stamp included", function ()
		local harness: Harness = connected()
		local sizes: { number } = {}

		for value: number = 1, TICKS do
			harness.server.Tick.fire(harness.alice, value)
		end

		steps(harness, 2)

		for _, entry: Fired in harness.fired.server do
			table.insert(sizes, buffer.len(entry.packet))
		end

		-- 297 Ticks fill the 891 bytes the budget leaves after the byte and the stamp, and 103 follow
		expect(table.concat(sizes, " ")).is("900 318")
		expect(harness.client.stats().messagesIn).is(TICKS)
	end)

	test(
		"serverTime is a function on Streams' client in each casing, and on neither its server nor Surface's",
		function ()
			for casing: string, name: string in CASINGS do
				local option: string = `option casing = {casing}`
				local server: any, client: any = loaded(compiled(option))
				local plainServer: any, plainClient: any = loaded(compiled(option, "Surface")) -- A schema with no stamp

				expect(type(client[name])).is("function")
				expect(`{server[name]} {plainServer[name]} {plainClient[name]}`).is("nil nil nil")
			end
		end
	)
end)
