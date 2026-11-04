--[[
    Proves a client's time-paced flush over Events.volt's modules and the
    mock: no faster than its pace at any frame rate, no burst after a hitch,
    and frames counted as before without a clock and on the server
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Transport = Volt.Transport

-- A server and a client over a mock, the client's packets counted on each remote, and what the server heard
type Harness = {
	mock: Mock,
	client: any,
	time: number, -- What the client's clock reads, when it has one
	reliable: number, -- The packets the client has sent on each remote
	unreliable: number,
	heard: { number }, -- Every Sync the server heard, in the order heard
	inputs: number, -- How many Inputs it heard
}

local EVENTS: string = fs.readFile("tests/Schemas/Events.volt")

local FAST: number = 1 / 240 -- A 240 FPS client's frame
local STEADY: number = 1 / 60
local SLOW: number = 1 / 30
local JITTER: number = 0.002 -- How far either way a frame at STEADY wanders
local HITCH: number = 0.5 -- How far one frame's clock jumps
local SECOND: number = 240 -- A second of frames at FAST, whose Syncs number 1 to 240, all within its u8
local MOST: number = 61 -- What that second sends at most on each remote: a flush an interval and the first frame's
local EVERY: number = 2 -- The flush of the case that sends every second interval
local PAIRED: number = 120 -- Frames at STEADY under it, sixty of its intervals
local STEPS: number = 16 -- How long each other case runs
local BURST: number = 5 -- The most flushes STEPS frames at FAST make after a hitch: four intervals' and the hitch's
local LIFTED: number = 1000 -- A rate no case reaches, since the mock's steps take no real time to refill a bucket in
local BELOW: number = 1 -- A flushBytes below one message's size, so any fire reaches it
local DIRECTION: number, JUMPING: boolean = 1, false -- What every Input carries

-- Both modules of Events.volt with the options given put before its text, the client's transport clocked when asked
local function setup(options: string, clocked: boolean): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local _, transport = mock:join("Alice")
	local counted: Transport = table.clone(transport)
	local client: string, server: string = Generated.modules("Events", `{options}{EVENTS}`)
	local harness: Harness = {
		mock = mock,
		client = nil,
		time = 0,
		reliable = 0,
		unreliable = 0,
		heard = {},
		inputs = 0,
	}

	counted.reliable = function (target: any, packet: buffer, side: { any }?)
		harness.reliable += 1
		transport.reliable(target, packet, side)
	end

	counted.unreliable = function (target: any, packet: buffer, side: { any }?)
		harness.unreliable += 1
		transport.unreliable(target, packet, side)
	end

	if clocked then
		counted.clock = function (): number
			return harness.time
		end
	end

	local network: any = Generated.module("Server", server, mock.server)

	network.rate("Sync", LIFTED)
	network.rate("Input", LIFTED)

	network.Sync.on(function (_, value: number)
		table.insert(harness.heard, value)
	end)

	network.Input.on(function ()
		harness.inputs += 1
	end)

	harness.client = Generated.module("Client", client, counted)

	return harness
end

-- Fires a Sync numbered by its step and an Input, moves the clock on a frame and steps, as many times as asked; a
-- jitter moves each frame's time that far, late on the even steps and early on the odd
local function run(harness: Harness, steps: number, frame: number, jitter: number?)
	local start: number = harness.time
	local wobble: number = jitter or 0

	for index: number = 1, steps do
		harness.client.Sync.fire(index)
		harness.client.Input.fire(DIRECTION, JUMPING)
		harness.time = start + index * frame + (index % 2 == 0 and wobble or -wobble)
		harness.mock:step()
	end

	harness.time = start + steps * frame
end

describe("Paced", function ()
	test("240 FPS frames for a second send at most 61 packets on each remote, every message heard", function ()
		local harness: Harness = setup("", true)
		local order: { number } = {}

		for value: number = 1, SECOND do
			order[value] = value
		end

		run(harness, SECOND, FAST)

		local reliable: number, unreliable: number = harness.reliable, harness.unreliable

		-- What the last frames fired goes out by hand and arrives on one more step
		harness.client.flush()
		harness.mock:step()

		-- One short of the most is the floor, so a pace that never flushes fails too
		expect(reliable >= MOST - 1 and reliable <= MOST).is(true)
		expect(unreliable >= MOST - 1 and unreliable <= MOST).is(true)
		expect(table.concat(harness.heard, ",")).is(table.concat(order, ","))
		expect(harness.inputs).is(SECOND)
	end)

	test("frames at 60 FPS that jitter 2 ms either way, and frames at 30 FPS, flush on every step", function ()
		local jittered: Harness = setup("", true)
		local slow: Harness = setup("", true)

		run(jittered, STEPS, STEADY, JITTER)
		run(slow, STEPS, SLOW)

		expect(`{jittered.reliable} {slow.reliable}`).is(`{STEPS} {STEPS}`)
	end)

	test("with flush = 2, 120 frames at 60 FPS send 60 or 61 reliable packets", function ()
		local harness: Harness = setup(`option flush = {EVERY}\n`, true)
		local intervals: number = PAIRED / EVERY

		run(harness, PAIRED, STEADY)

		expect(harness.reliable >= intervals and harness.reliable <= intervals + 1).is(true)
	end)

	test("after a hitch of half a second, the next 16 frames at 240 FPS flush at most 5 times", function ()
		local harness: Harness = setup("", true)

		run(harness, STEPS, FAST)

		local before: number = harness.reliable

		harness.time += HITCH
		run(harness, STEPS, FAST)

		expect(harness.reliable - before <= BURST).is(true)
	end)

	test("a flushBytes below one message's size flushes on every step that fires", function ()
		local harness: Harness = setup(`option flushBytes = {BELOW}\n`, true)

		run(harness, STEPS, FAST)

		expect(harness.reliable).is(STEPS)
	end)

	test("under manualReplication nothing is sent until Network.flush()", function ()
		local harness: Harness = setup("option manualReplication = true\n", true)

		run(harness, STEPS, FAST)

		expect(`{harness.reliable} {harness.unreliable}`).is("0 0")

		harness.client.flush()

		expect(`{harness.reliable} {harness.unreliable}`).is("1 1")
	end)

	test("a server handed a clock still flushes every flush-th step", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice, transport = mock:join("Alice")
		local clocked: Transport = table.clone(mock.server)
		local client: string, server: string = Generated.modules("Events", EVENTS)
		local sent: number = 0
		local now: number = 0

		clocked.clock = function (): number
			return now
		end

		clocked.reliable = function (target: any, packet: buffer, side: { any }?)
			sent += 1
			mock.server.reliable(target, packet, side)
		end

		local network: any = Generated.module("Server", server, clocked)

		Generated.module("Client", client, transport)

		-- One step flushes the client's handshake and the next reads it
		mock:step()
		mock:step()

		for value: number = 1, STEPS do
			network.Sync.fire(alice, value)
			now += FAST
			mock:step()
		end

		expect(sent).is(STEPS)
	end)

	test("a client with no clock flushes on every step at flush = 1, as every other suite's clients do", function ()
		local harness: Harness = setup("", false)

		run(harness, STEPS, FAST)

		expect(harness.reliable).is(STEPS)
	end)
end)
