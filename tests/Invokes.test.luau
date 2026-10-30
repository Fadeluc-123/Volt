--[[
    Proves the server's calls to one client: the client's handler, which
    hears the values alone, the deadline, the slots kept per player and
    their ceiling, the replies the server refuses, a player who leaves
    mid-call, no player, edit mode and whether a handler is connected
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Promise: any = require("./Promise")
local Volt = require("@volt")
local Config = require("@volt/Config/Runtime")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Schema = Volt.Schema
type Transport = Volt.Transport

type Report = { player: any, kind: string, detail: string } -- One failure a runtime reported

-- A server and Alice's client over one mock with one function the server calls, whose call doubles a byte
type Harness = {
	mock: Mock,
	server: Runtime,
	client: Runtime,
	alice: any,
	failures: { server: { Report }, client: { Report } },
	slots: { number }, -- The slot each call was written with
	write: (slot: number, value: number) -> (), -- The call's writer, into the state the server's send points at
	reply: (slot: number, status: number, value: number?) -> (), -- The reply's writer, into the client's one state
}

-- The results of a call once its reply is back, as one line, or pending until then
type Box = { line: string }

local ID: number = 1 -- The one function's id in both directions
local STATUS = Config.status
local UNKNOWN: number = 7 -- A status no reply carries

-- The options the runtime reads, at the compiler's defaults
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

-- A schema table with one message on one side
local function schema(side: string, message: any): Schema
	return {
		version = Volt.version,
		hash = 0,
		scope = "Test",
		side = side,
		idBytes = 1,
		options = OPTIONS,
		messages = { [ID] = message },
		outgoing = {},
	}
end

-- A list that records every failure a runtime reports, with the player it names
local function recorded(runtime: Runtime): { Report }
	local failures: { Report } = {}

	runtime:onFailure(function (player: any, kind: string, detail: string)
		table.insert(failures, { player = player, kind = kind, detail = detail })
	end)

	return failures
end

-- Every value a call returned, as one line
local function line(...: any): string
	local parts: { string } = {}

	for index: number = 1, select("#", ...) do
		table.insert(parts, tostring((select(index, ...))))
	end

	return table.concat(parts, " ")
end

--[[
    A server and Alice's client over a mock with one function the server
    calls: the call carries a byte after its slot and the reply a byte
    after its status, written and read by hand as a generated module
    would. Alice's handshake is read before it returns
--]]

local function setup(timeout: number?, promise: any?, inert: boolean?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport: Transport = mock:join("Alice")
	local slots: { number } = {}
	local server: Runtime, client: Runtime

	local function writeCall(slot: number, value: number)
		local offset: number, out: buffer = server.reliable.begin(4)

		table.insert(slots, slot)
		buffer.writeu8(out, offset, ID)
		buffer.writeu16(out, offset + 1, slot)
		buffer.writeu8(out, offset + 3, value)
	end

	local function readCall(from: any, packet: buffer, cursor: number, _, sideCursor: number, _: number)
		local slot: number = buffer.readu16(packet, cursor)
		return client:call(ID, from, slot, cursor + 3, sideCursor, buffer.readu8(packet, cursor + 2))
	end

	local function writeReply(slot: number, status: number, value: number?)
		local offset: number, out: buffer = client.reliable.begin(value and 5 or 4)

		buffer.writeu8(out, offset, ID)
		buffer.writeu16(out, offset + 1, slot)
		buffer.writeu8(out, offset + 3, status)

		if value then
			buffer.writeu8(out, offset + 4, value)
		end
	end

	local function readReply(from: any, packet: buffer, cursor: number, _, sideCursor: number, length: number)
		local slot: number = buffer.readu16(packet, cursor)
		local status: number = buffer.readu8(packet, cursor + 2)
		cursor += 3

		if status ~= STATUS.ok then
			return server:refused(ID, from, slot, status, packet, cursor, sideCursor, length)
		end

		return server:reply(ID, from, slot, cursor + 1, sideCursor, buffer.readu8(packet, cursor))
	end

	-- The server hears the function's reply and the client its call
	local serverRow = { name = "Double", kind = "reply", timeout = timeout or 10, promise = promise, read = readReply }
	local clientRow = { name = "Double", kind = "call", read = readCall, reply = writeReply }
	local live: Transport = table.clone(mock.server)

	live.inert = inert
	server = Volt.start(schema("server", serverRow), live)
	client = Volt.start(schema("client", clientRow), transport)

	-- One step sends Alice's handshake and the next reads it, so a call after it goes out at the next flush
	mock:step()
	mock:step()

	return {
		mock = mock,
		server = server,
		client = client,
		alice = alice,
		failures = { server = recorded(server), client = recorded(client) },
		slots = slots,
		write = writeCall,
		reply = writeReply,
	}
end

-- Makes one call on a thread of its own, since a coroutine call yields, and renders what it returned once it is back
local function call(harness: Harness, player: any, value: number): Box
	local box: Box = { line = "pending" }

	task.spawn(function ()
		box.line = line(harness.server:invoke(ID, harness.write, player, value))
	end)

	return box
end

-- A handler that parks every call on its thread until the test resumes it, then returns the value
local function parking(parked: { thread }): (number) -> number
	return function (value: number): number
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

describe("Invokes", function ()
	test("a call reaches the client's handler with the values alone and comes back as ok and the returns", function ()
		local harness: Harness = setup()
		local heard: string? = nil

		harness.client:handle(ID, function (value: number, extra: any): number
			heard = `{value} {extra}`
			return value * 2
		end)

		local box: Box = call(harness, harness.alice, 5)
		roundTrip(harness.mock)

		expect(`{heard} {box.line}`).is("5 nil true 10")
		expect(#harness.failures.server + #harness.failures.client).is(0)
	end)

	test("a client handler's error is a handler failure with no player, and the call gets its first line", function ()
		local harness: Harness = setup()

		harness.client:handle(ID, function ()
			error("boom")
		end)

		local box: Box = call(harness, harness.alice, 5)
		roundTrip(harness.mock)

		local report: Report = harness.failures.client[1]

		expect(`{box.line} {#harness.failures.client} {report.player} {report.kind}`).is("false boom 1 nil handler")
		expect((report.detail:find("Double: ", 1, true))).is(1)
	end)

	test("a client with no handler answers no handler at once", function ()
		local harness: Harness = setup()
		local box: Box = call(harness, harness.alice, 5)

		roundTrip(harness.mock)

		expect(box.line).is("false no handler")
	end)

	test("fails a call past its deadline at the flush and holds its slot until the late reply frees it", function ()
		local harness: Harness = setup(0)
		local parked: { thread } = {}

		harness.client:handle(ID, parking(parked))

		local first: Box = call(harness, harness.alice, 1)
		harness.mock:step()
		expect(first.line).is("false timeout")

		local second: Box = call(harness, harness.alice, 2)
		harness.mock:step()
		expect(second.line).is("false timeout")

		-- The first call's handler answers now, long after the server gave up
		task.spawn(parked[1])
		harness.mock:step()
		harness.mock:step()

		call(harness, harness.alice, 3)

		expect(table.concat(harness.slots, ",")).is("1,2,1")
		expect(#harness.failures.server).is(0)
	end)

	test("stops at playerSlots calls in flight to one player, writing nothing, while another's goes out", function ()
		local harness: Harness = setup(nil, Promise)
		local bob: any = harness.mock:join("Bob")
		local server: Runtime = harness.server

		for _ = 1, Config.playerSlots do
			server:invoke(ID, harness.write, harness.alice, 1)
		end

		local written: number = server:stats(harness.alice).messagesOut
		local last: Promise.Promise = server:invoke(ID, harness.write, harness.alice, 1)
		local toBob: Promise.Promise = server:invoke(ID, harness.write, bob, 1)
		local settled = assert(last.settled, "the last call never settled")

		expect(`{settled[1]} {settled[2]}`).is("false too many calls")
		expect(server:stats(harness.alice).messagesOut - written).is(0)
		expect(`{toBob.settled} {server:stats(bob).messagesOut}`).is("nil 1")
	end)

	test("a reply for a slot never given, or for a call already answered, is a decode failure on the server", function ()
		local harness: Harness = setup()

		harness.client:handle(ID, function (value: number): number
			return value
		end)

		harness.reply(9, STATUS.ok, 1)
		roundTrip(harness.mock)

		local box: Box = call(harness, harness.alice, 5)
		roundTrip(harness.mock)

		harness.reply(1, STATUS.ok, 1)
		roundTrip(harness.mock)

		local failures: { Report } = harness.failures.server

		expect(`{box.line} {#failures} {failures[1].kind} {failures[2].kind}`).is("true 5 2 decode decode")
		expect(`{failures[1].detail}, {failures[2].detail}`).is("Double: no call in slot 9, Double: no call in slot 1")
	end)

	test("a reply with a status no reply carries is a decode failure on the server", function ()
		local harness: Harness = setup()

		harness.reply(1, UNKNOWN)
		roundTrip(harness.mock)

		local report: Report = harness.failures.server[1]
		expect(`{report.kind}: {report.detail}`).is(`decode: Double: unknown status {UNKNOWN}`)
	end)

	test("a player who leaves fails every call in flight to them, reporting nothing, and a call again fails", function ()
		local harness: Harness = setup()
		local first: Box = call(harness, harness.alice, 1)
		local second: Box = { line = "pending" }
		local again: Box = { line = "pending" }

		task.spawn(function ()
			second.line = line(harness.server:invoke(ID, harness.write, harness.alice, 2))
			again.line = line(harness.server:invoke(ID, harness.write, harness.alice, 3))
		end)

		harness.mock:leave(harness.alice)

		local report: Report = harness.failures.server[1]

		expect(`{first.line}, {second.line}, {again.line}`).is("false departed, false departed, false departed")
		expect(`{#harness.failures.server} {report.kind}`).is("1 departed")
	end)

	test("a call at a player who has left fails at once, after its one departed failure", function ()
		local harness: Harness = setup()

		harness.mock:leave(harness.alice)

		local ok: boolean, reason: any = harness.server:invoke(ID, harness.write, harness.alice, 1)

		expect(`{ok} {reason} {#harness.failures.server}`).is("false departed 1")
		expect(#harness.slots).is(0)
	end)

	test("a call at no player raises and writes nothing", function ()
		local harness: Harness = setup()
		local ok: boolean, message: any = pcall(harness.server.invoke, harness.server, ID, harness.write, nil, 1)

		expect(`{ok} {#harness.slots}`).is("false 0")
		expect(tostring(message):find("Volt: a message for one player was sent to none", 1, true) ~= nil).is(true)
	end)

	test("fails at once in edit mode, on the thread and on a promise, writing nothing", function ()
		local plain: Harness = setup(nil, nil, true)
		local promised: Harness = setup(nil, Promise, true)
		local returned: string = line(plain.server:invoke(ID, plain.write, plain.alice, 5))
		local promise: Promise.Promise = promised.server:invoke(ID, promised.write, promised.alice, 5)
		local settled = assert(promise.settled, "the promise never settled")

		expect(returned).is("false edit mode")
		expect(`{settled[1]} {settled[2]}`).is("false edit mode")
		expect(#plain.slots + #promised.slots).is(0)
	end)

	test("handled reads whether the client's handler is connected, before, during and after", function ()
		local harness: Harness = setup()
		local before: boolean = harness.client:handled(ID)
		local disconnect: () -> () = harness.client:handle(ID, function () end)
		local during: boolean = harness.client:handled(ID)

		disconnect()

		expect(`{before} {during} {harness.client:handled(ID)}`).is("false true false")
	end)
end)
