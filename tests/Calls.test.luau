--[[
    Proves the calls: a slot per call in flight that the reply frees, the
    ceiling, the deadline swept at flush with the slot held for the late
    reply, the reply and the refusals a caller sees on its thread or its
    promise, edit mode, the one handler, its error, and the caller who
    left
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Promise = require("./Promise")
local Volt = require("@volt")
local Config = require("@volt/Config/Runtime")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Schema = Volt.Schema
type Transport = Volt.Transport

type Report = { kind: string, detail: string } -- One failure a runtime reported

-- A server and a client runtime over one mock with one function, whose call doubles a byte
type Harness = {
	mock: Mock,
	server: Runtime,
	client: Runtime,
	player: any,
	failures: { server: { Report }, client: { Report } },
	slots: { number }, -- The slot each call was written with
	write: (slot: number, value: number) -> (), -- The call's writer
	reply: (slot: number, status: number, value: number?) -> (), -- The reply's writer
}

-- The results of a call once its reply is back, as one line, or pending until then
type Box = { line: string }

local ID: number = 1 -- The one function's id in both directions
local STATUS = Config.status

-- A schema table with one message on one side
local function schema(side: string, message: any): Schema
	return {
		version = Volt.version,
		hash = 0,
		scope = "Test",
		side = side,
		idBytes = 1,
		options = { flush = 1, manualReplication = false, unreliableBudget = 900 },
		messages = { [ID] = message },
		outgoing = {},
	}
end

-- A list that records every failure a runtime reports
local function recorded(runtime: Runtime): { Report }
	local failures: { Report } = {}

	runtime:onFailure(function (_, kind: string, detail: string)
		table.insert(failures, { kind = kind, detail = detail })
	end)

	return failures
end

--[[
    A server and a client over a mock with one function: the call carries
    a byte after its slot and the reply a byte after its status, written
    and read by hand as a generated module would
--]]

local function setup(timeout: number?, promise: any?, inert: boolean?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local player: any, transport: Transport = mock:join("Alice")
	local slots: { number } = {}
	local server: Runtime, client: Runtime

	local function readCall(from: any, packet: buffer, cursor: number, _, sideCursor: number, _: number)
		local slot: number = buffer.readu16(packet, cursor)
		return server:call(ID, from, slot, cursor + 3, sideCursor, buffer.readu8(packet, cursor + 2))
	end

	local function writeReply(slot: number, status: number, value: number?)
		local offset: number, out: buffer = server.reliable.allocate(value and 5 or 4)

		buffer.writeu8(out, offset, ID)
		buffer.writeu16(out, offset + 1, slot)
		buffer.writeu8(out, offset + 3, status)

		if value then
			buffer.writeu8(out, offset + 4, value)
		end
	end

	local function writeCall(slot: number, value: number)
		local offset: number, out: buffer = client.reliable.allocate(4)

		table.insert(slots, slot)
		buffer.writeu8(out, offset, ID)
		buffer.writeu16(out, offset + 1, slot)
		buffer.writeu8(out, offset + 3, value)
	end

	local function readReply(_, packet: buffer, cursor: number, _, sideCursor: number, length: number)
		local slot: number = buffer.readu16(packet, cursor)
		local status: number = buffer.readu8(packet, cursor + 2)
		cursor += 3

		if status ~= STATUS.ok then
			return client:refused(ID, slot, packet, cursor, sideCursor, length)
		end

		return client:reply(ID, slot, cursor + 1, sideCursor, buffer.readu8(packet, cursor))
	end

	local live: Transport = table.clone(transport)
	live.inert = inert

	server = Volt.start(
		schema("server", { name = "Double", kind = "call", read = readCall, reply = writeReply }),
		mock.server
	)
	client = Volt.start(
		schema(
			"client",
			{ name = "Double", kind = "reply", timeout = timeout or 10, promise = promise, read = readReply }
		),
		live
	)

	return {
		mock = mock,
		server = server,
		client = client,
		player = player,
		failures = { server = recorded(server), client = recorded(client) },
		slots = slots,
		write = writeCall,
		reply = writeReply,
	}
end

-- Makes one call on a thread of its own, since a coroutine call yields, and renders what it returned once it is back
local function call(harness: Harness, ...: any): Box
	local box: Box = { line = "pending" }

	task.spawn(function (...: any)
		local results = table.pack(harness.client:invoke(ID, harness.write, ...))
		local parts: { string } = {}

		for index: number = 1, results.n do
			table.insert(parts, tostring(results[index]))
		end

		box.line = table.concat(parts, " ")
	end, ...)

	return box
end

-- A handler that parks every call on its thread until the test resumes it, then returns the value
local function parking(parked: { thread }): (any, number) -> number
	return function (_, value: number): number
		table.insert(parked, coroutine.running())
		coroutine.yield()
		return value
	end
end

-- One step flushes the call, the next delivers it and flushes the reply, the last delivers the reply
local function roundTrip(mock: Mock)
	mock:step()
	mock:step()
	mock:step()
end

describe("Calls", function ()
	test("a call reaches the handler with the player first and comes back as ok and the returns", function ()
		local harness: Harness = setup()
		local heard: string? = nil

		harness.server:handle(ID, function (player: any, value: number): number
			heard = `{player.Name} {value}`
			return value * 2
		end)

		local box: Box = call(harness, 5)
		roundTrip(harness.mock)

		expect(heard).is("Alice 5")
		expect(box.line).is("true 10")
		expect(#harness.failures.client).is(0)
	end)

	test("refuses a call with no handler at once", function ()
		local harness: Harness = setup()
		local box: Box = call(harness, 5)

		roundTrip(harness.mock)

		expect(box.line).is("false no handler")
	end)

	test("reports a handler's error as a handler failure and refuses the call with its first line", function ()
		local harness: Harness = setup()

		harness.server:handle(ID, function ()
			error("boom")
		end)

		local box: Box = call(harness, 5)
		roundTrip(harness.mock)

		expect((box.line:find("false ", 1, true))).is(1)
		expect(box.line:find("boom", 1, true) ~= nil).is(true)
		expect((box.line:find("\n", 1, true))).is(nil)
		expect(#harness.failures.server).is(1)
		expect(harness.failures.server[1].kind).is("handler")
		expect((harness.failures.server[1].detail:find("Double: ", 1, true))).is(1)
	end)

	test("fails a call past its deadline at the flush and holds its slot until the late reply frees it", function ()
		local harness: Harness = setup(0)
		local parked: { thread } = {}

		harness.server:handle(ID, parking(parked))

		local first: Box = call(harness, 1)
		harness.mock:step()
		expect(first.line).is("false timeout")

		local second: Box = call(harness, 2)
		harness.mock:step()
		expect(second.line).is("false timeout")

		-- The first call's handler answers now, long after the caller gave up
		task.spawn(parked[1])
		harness.mock:step()
		harness.mock:step()

		call(harness, 3)

		expect(table.concat(harness.slots, ",")).is("1,2,1")
		expect(#harness.failures.client).is(0)
	end)

	test("a reply for a slot no call is in is a decode failure", function ()
		local harness: Harness = setup()

		harness.server:target(harness.player)
		harness.reply(9, STATUS.ok, 1)
		harness.mock:step()
		harness.mock:step()

		expect(#harness.failures.client).is(1)
		expect(harness.failures.client[1].kind).is("decode")
		expect(harness.failures.client[1].detail).is("Double: no call in slot 9")
	end)

	test("a reason that runs past the packet is a decode failure", function ()
		local harness: Harness = setup()
		local box: Box = call(harness, 5)

		harness.server:target(harness.player)
		harness.reply(1, STATUS.failed)

		local offset: number, out: buffer = harness.server.reliable.allocate(2)
		buffer.writeu16(out, offset, 300)

		-- Two steps deliver the bad reply; a third would deliver the server's own refusal of the unhandled call
		harness.mock:step()
		harness.mock:step()

		expect(box.line).is("pending")
		expect(harness.failures.client[1].detail).is("Double: truncated")
	end)

	test("cuts a long reason to what a refusal carries", function ()
		local harness: Harness = setup()

		harness.server:handle(ID, function ()
			error(string.rep("x", 300))
		end)

		local box: Box = call(harness, 5)
		roundTrip(harness.mock)

		expect(#box.line - #"false ").is(Config.messageBytes)
	end)

	test("resolves a promise with the returns and rejects it with the reason", function ()
		local harness: Harness = setup(nil, Promise)
		local rejected: Promise.Promise = harness.client:invoke(ID, harness.write, 5)

		roundTrip(harness.mock)

		harness.server:handle(ID, function (_, value: number): number
			return value * 2
		end)

		local resolved: Promise.Promise = harness.client:invoke(ID, harness.write, 5)
		roundTrip(harness.mock)

		local rejection = assert(rejected.settled, "the first call never settled")
		local resolution = assert(resolved.settled, "the second call never settled")

		expect(`{rejection[1]} {rejection[2]}`).is("false no handler")
		expect(`{resolution[1]} {resolution[2]}`).is("true 10")
	end)

	test("fails at once in edit mode, on the thread and on a promise, writing nothing", function ()
		local plain: Harness = setup(nil, nil, true)
		local promised: Harness = setup(nil, Promise, true)
		local ok: boolean, reason: any = plain.client:invoke(ID, plain.write, 5)
		local promise: Promise.Promise = promised.client:invoke(ID, promised.write, 5)
		local settled = assert(promise.settled, "the promise never settled")

		expect(`{ok} {reason}`).is("false edit mode")
		expect(`{settled[1]} {settled[2]}`).is("false edit mode")
		expect(#plain.slots + #promised.slots).is(0)
	end)

	test("fails the call past the ceiling of slots in flight", function ()
		local harness: Harness = setup(nil, Promise)
		local last: Promise.Promise

		for _ = 1, Config.slots + 1 do
			last = harness.client:invoke(ID, function () end)
		end

		local settled = assert(last.settled, "the last call never settled")
		expect(`{settled[1]} {settled[2]}`).is("false too many calls")
	end)

	test("sends no reply to a caller who has left, and counts it as departed", function ()
		local harness: Harness = setup()
		local parked: { thread } = {}

		harness.server:handle(ID, parking(parked))

		local box: Box = call(harness, 5)
		harness.mock:step()
		harness.mock:step()
		harness.mock:leave(harness.player)

		task.spawn(parked[1])
		harness.mock:step()

		expect(box.line).is("pending")
		expect(#harness.failures.server).is(1)
		expect(harness.failures.server[1].kind).is("departed")
	end)

	test("refuses a second handler until the first disconnects", function ()
		local harness: Harness = setup()
		local disconnect: () -> () = harness.server:handle(ID, function () end)
		local ok: boolean, message: any = pcall(harness.server.handle, harness.server, ID, function () end)

		expect(ok).is(false)
		expect(tostring(message):find("Double: a handler is already connected", 1, true) ~= nil).is(true)

		disconnect()
		harness.server:handle(ID, function () end)
	end)
end)
