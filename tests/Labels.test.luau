--[[
    Proves the runtime's profile labels over the mock, with a recording
    profiler in a hand-written schema table and readers written by hand
    as a module compiled with labels writes them: each packet and each
    Heartbeat is labelled, and every reader's label closes on every path
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local packet = require("./Packet")
local Volt = require("@volt")
local Types = require("@volt/Config/Types/Runtime")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Profiler = Types.Profiler
type Runtime = Volt.Runtime
type Transport = Volt.Transport

-- A client on Alice's side of a mock, with every label, close and failure in the order they came, and what it heard
type Harness = {
	runtime: Runtime,
	mock: Mock,
	alice: any,
	log: { string },
	open: { string }, -- The labels still open, the innermost last
	seen: { string },
	failures: { string },
}

local PING: number = 1 -- A byte, refused at zero
local AIM: number = 2 -- An ordered event: its sequence as a u16, then a byte
local VITALS: number = 3 -- A @delta event of one field: its mask, then the field's byte when the mask holds it
local SPAWNED: number = 4 -- An awaited instance's id as a u32

-- The options the runtime reads, at the compiler's defaults
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

--[[
    A client runtime of scope S over a mock, with a dictionary and four
    events read by hand as a module compiled with labels reads them,
    each reader opening its label first and closing it after its tail;
    unlabelled, the table carries no profiler and the readers open none
--]]

local function setup(labelled: boolean): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport: Transport = mock:join("Alice")
	local log: { string }, open: { string }, seen: { string }, failures: { string } = {}, {}, {}, {}
	local runtime: Runtime

	-- Keeps what is open as the MicroProfiler's stack does, so a label closed twice or never shows in the log
	local profiler: Profiler = {
		profilebegin = function (label: string)
			table.insert(open, label)
			table.insert(log, label)
		end,

		profileend = function ()
			table.insert(log, table.remove(open) and "end" or "end of nothing")
		end,
	}

	local function begin(name: string)
		if labelled then
			profiler.profilebegin(`Volt S {name}`)
		end
	end

	local function finish()
		if labelled then
			profiler.profileend()
		end
	end

	local function readPing(_: any, from: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
		begin("Ping")

		local value: number = buffer.readu8(from, cursor)
		if value == 0 then
			error("Ping.value: out of range")
		end

		cursor, sideCursor = runtime:deliver(PING, nil, cursor + 1, sideCursor, value)
		finish()

		return cursor, sideCursor
	end

	local function readAim(_: any, from: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
		begin("Aim")

		local sequence: number = buffer.readu16(from, cursor)
		local value: number = buffer.readu8(from, cursor + 2)

		cursor, sideCursor = runtime:ordered(AIM, sequence, nil, cursor + 3, sideCursor, value)
		finish()

		return cursor, sideCursor
	end

	local function readVitals(_: any, from: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
		begin("Vitals")

		local mask: number = buffer.readu8(from, cursor)
		local health: number? = nil
		cursor += 1

		if bit32.btest(mask, 1) then
			health = buffer.readu8(from, cursor)
			cursor += 1
		end

		cursor, sideCursor =
			runtime:deliver(VITALS, nil, cursor, sideCursor, runtime:merge(VITALS, mask, { health = health }))
		finish()

		return cursor, sideCursor
	end

	local function readSpawned(_: any, from: buffer, cursor: number, side: { any }, sideCursor: number, _: number)
		begin("Spawned")

		local model: any = runtime.instanceById(buffer.readu32(from, cursor))
		if model and model.ClassName ~= "Model" then
			error("Spawned.model: expected AwaitedInstance(Model)")
		end

		cursor, sideCursor = runtime:await(SPAWNED, from, cursor, cursor + 4, side, sideCursor, sideCursor, model)
		finish()

		return cursor, sideCursor
	end

	local messages: { [number]: any } = {
		[PING] = { name = "Ping", kind = "event", mode = "ManySync", queue = 4, read = readPing },
		[AIM] = { name = "Aim", kind = "event", mode = "ManySync", queue = 4, read = readAim },

		[VITALS] = {
			name = "Vitals",
			kind = "event",
			mode = "ManySync",
			queue = 4,
			fields = { "health" },
			read = readVitals,
		},

		[SPAWNED] = { name = "Spawned", kind = "event", mode = "ManySync", queue = 4, timeout = 10, read = readSpawned },
	}

	runtime = Volt.start({
		version = Volt.version,
		hash = 0,
		scope = "S",
		side = "client",
		idBytes = 1,
		dictionary = 1,
		profiler = labelled and profiler or nil,
		options = OPTIONS,
		messages = messages,
		outgoing = {},
	}, transport)

	-- In the log too, so a test sees whether a reader's label closed before its failure was reported
	runtime:onFailure(function (_: any, kind: string, detail: string)
		table.insert(log, kind)
		table.insert(failures, `{kind} {detail}`)
	end)

	runtime:on(PING, function (value: number)
		table.insert(seen, `Ping {value}`)
	end)

	runtime:on(AIM, function (value: number)
		table.insert(seen, `Aim {value}`)
	end)

	runtime:on(SPAWNED, function (model: any)
		table.insert(seen, `Spawned {model.Name}`)
	end)

	return {
		runtime = runtime,
		mock = mock,
		alice = alice,
		log = log,
		open = open,
		seen = seen,
		failures = failures,
	}
end

-- Steps the mock and returns that step's log, starting the next one empty
local function step(harness: Harness): string
	harness.mock:step()

	local logged: string = table.concat(harness.log, ",")
	table.clear(harness.log)

	return logged
end

-- Sends Alice one packet from the server and returns the log of the step that delivers it
local function send(harness: Harness, bytes: { number }): string
	harness.mock.server.reliable(harness.alice, packet(bytes))
	return step(harness)
end

describe("Labels", function ()
	test("labels a packet around its readers' own labels, and a Heartbeat around its flush", function ()
		local harness: Harness = setup(true)

		expect(send(harness, { PING, 1, PING, 2 })).is(
			"Volt S receive,Volt S Ping,end,Volt S Ping,end,end,Volt S flush,end"
		)
		expect(table.concat(harness.seen, ",")).is("Ping 1,Ping 2")
		expect(step(harness)).is("Volt S flush,end")
	end)

	test("closes the label of a reader that raises before its decode failure, which keeps its detail", function ()
		local harness: Harness = setup(true)

		expect(send(harness, { PING, 1, PING, 0 })).is(
			"Volt S receive,Volt S Ping,end,Volt S Ping,end,decode,end,Volt S flush,end"
		)
		expect(#harness.open).is(0)
		expect(harness.failures[1]).is("decode Ping: Ping.value: out of range")
	end)

	test("a schema table with no profiler is never labelled, on the failure branch either", function ()
		local harness: Harness = setup(false)

		expect(send(harness, { PING, 1, PING, 0 })).is("decode")
		expect(harness.failures[1]).is("decode Ping: Ping.value: out of range")
		expect(table.concat(harness.seen, ",")).is("Ping 1")
	end)

	test("closes no reader's label for an id that names no message, after one that was read", function ()
		local harness: Harness = setup(true)

		expect(send(harness, { PING, 1, 9 })).is("Volt S receive,Volt S Ping,end,packet,end,Volt S flush,end")
		expect(harness.failures[1]).is("packet unknown message 9")
	end)

	test("closes an ordered event's reader's label when it drops a stale message", function ()
		local harness: Harness = setup(true)

		expect(send(harness, { AIM, 5, 0, 1, AIM, 4, 0, 2 })).is(
			"Volt S receive,Volt S Aim,end,Volt S Aim,end,end,Volt S flush,end"
		)
		expect(table.concat(harness.seen, ",")).is("Aim 1")
	end)

	test("closes a @delta reader's label when its merge finds no baseline, before the failure", function ()
		local harness: Harness = setup(true)

		expect(send(harness, { VITALS, 0 })).is("Volt S receive,Volt S Vitals,end,decode,end,Volt S flush,end")
		expect(harness.failures[1]).is("decode Vitals: no baseline")
	end)

	test("closes the label of a message that waits, and its replay opens only its reader's", function ()
		local harness: Harness = setup(true)
		local model: any = { Name = "A", ClassName = "Model" }
		local id: number = assert(harness.mock.server.reference, "the mock's server gives instances ids")(model)

		harness.mock:hide(model)

		expect(send(harness, { SPAWNED, id, 0, 0, 0 })).is("Volt S receive,Volt S Spawned,end,end,Volt S flush,end")

		harness.mock:reveal(model)

		expect(step(harness)).is("Volt S Spawned,end,Volt S flush,end")
		expect(table.concat(harness.seen, ",")).is("Spawned A")
	end)

	test("closes the label of a replay whose reader raises, before its decode failure", function ()
		local harness: Harness = setup(true)
		local part: any = { Name = "P", ClassName = "Part" }
		local id: number = assert(harness.mock.server.reference, "the mock's server gives instances ids")(part)

		harness.mock:hide(part)
		send(harness, { SPAWNED, id, 0, 0, 0 })
		harness.mock:reveal(part)

		expect(step(harness)).is("Volt S Spawned,end,decode,Volt S flush,end")
		expect(#harness.open).is(0)
		expect(harness.failures[1]).is("decode Spawned: Spawned.model: expected AwaitedInstance(Model)")
	end)

	test("closes no label when the dictionary message, which the runtime reads itself, fails", function ()
		local harness: Harness = setup(true)

		expect(send(harness, { 0, 2, 0, 1, 0, 1, 65 })).is("Volt S receive,decode,end,Volt S flush,end")
		expect(harness.failures[1]).is("decode Volt.dictionary: out of order")
	end)
end)
