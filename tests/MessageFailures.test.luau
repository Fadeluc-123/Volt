--[[
    Proves the failure detail contract for a failure of one message, over
    the generated modules on the server and on the client: its detail
    begins with the message's registry name and a colon exactly once, and
    a handler's error reaches its caller as exactly its text
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Failures = require("./Failures")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local packet = Failures.packet
local setup = Failures.setup
local steps = Failures.steps

type Harness = Failures.Harness
type Mock = Volt.Mock
type Report = Failures.Report

local QUEUE: number = 64 -- The queue every event here keeps, the schema's default
local LONG_REASON: number = 200 -- Past the 128 bytes Example's Inventory.Transfer allows its reason
local OUT_OF_RANGE: number = 1000 -- Past the 999 a Stack's quantity allows
local WRONG_DIR: number = 9 -- Past the 8 Input's dir allows
local NOT_TEXT: { number } = { 0xC3, 0x28 } -- A two-byte sequence whose second byte does not continue it
local LINE: number = 1 -- The id Console's line reaches the client with

-- Runs one step on a thread of its own, so a listener that yields in it is resumed only after a frame has passed
local function across(mock: Mock)
	local thread: thread = coroutine.create(function ()
		mock:step()
	end)

	coroutine.resume(thread)
	mock:step()
	coroutine.resume(thread)
end

-- A failure of a message names it once: the text before the first colon is its registry name, never twice over
local function named(report: Report?, kind: string, name: string)
	local found: Report = assert(report, `no {kind} failure was reported`)

	expect(found.kind).is(kind)
	expect(found.detail:match("^(.-): ")).is(name)
	expect(found.detail:sub(1, 2 * #name + 4)).never_is(`{name}: {name}: `)
end

describe("Failures", function ()
	describe("on the server", function ()
		test("a rate on an event and on a function names the message", function ()
			local exports: Harness = setup("Exports")
			local functions: Harness = setup("Functions")
			local results: { string } = {}

			exports.server.rate("Ping", 1)
			exports.client.Ping.fire()
			exports.client.Ping.fire()
			steps(exports.mock)

			functions.server.Echo.on(function (_, value: number): number
				return value
			end)
			functions.server.rate("Echo", 1)

			for index: number = 1, 2 do
				task.spawn(function ()
					local ok: boolean, value: any = functions.client.Echo.invoke(index)
					table.insert(results, `{ok} {value}`)
				end)
			end

			steps(functions.mock)

			named(exports.failures.server[1], "rate", "Ping")
			named(functions.failures.server[1], "rate", "Echo")
			expect(table.concat(results, ",")).is("true 1,false rate limited")
		end)

		test("a decode inline and inside a shared pair names the message once", function ()
			local events: Harness = setup("Events")
			local records: Harness = setup("Records")
			local stack: { [string]: any } = { item = "a", quantity = OUT_OF_RANGE }

			events.client.Input.fire(WRONG_DIR, true)
			records.client.Records.fire({ x = 1, y = "", z = true }, {}, stack, { version = 1, stacks = {} })
			steps(events.mock)
			steps(records.mock)

			named(events.failures.server[1], "decode", "Input")
			named(records.failures.server[1], "decode", "Records")
			expect(events.failures.server[1].detail).is("Input: Input.dir: out of range")
			expect(records.failures.server[1].detail).is("Records: Stack.quantity: out of range")
		end)

		test("a decode of text that is not UTF-8 names the function", function ()
			local harness: Harness = setup("Console")

			-- The client's module checks nothing it writes, so the text reaches the server's reader
			harness.client.Decree.run.invoke(string.char(table.unpack(NOT_TEXT)))
			steps(harness.mock)

			named(harness.failures.server[1], "decode", "Decree.run")
			expect(harness.failures.server[1].detail).is("Decree.run: Decree.run.text: invalid UTF-8")
		end)

		test("a listener's error and its yield name the event", function ()
			local harness: Harness = setup("Events")

			-- An error that names its own event already is passed on as it is, never named a second time
			harness.server.Ready.on(function ()
				error("Ready: boom", 0)
			end)
			harness.server.Sync.on(function ()
				coroutine.yield()
			end)

			harness.client.Ready.fire()
			harness.client.Sync.fire(1)
			harness.mock:step()
			across(harness.mock)

			named(harness.failures.server[1], "listener", "Ready")
			named(harness.failures.server[2], "listener", "Sync")
			expect(harness.failures.server[2].detail).is("Sync: a sync listener yielded")
		end)

		test("a handler's error names the function, and its caller gets exactly its text in either mode", function ()
			local harness: Harness = setup("Functions")
			local results: { string } = {}

			harness.server.Echo.on(function ()
				error("boom")
			end)
			harness.server.Inventory.Transfer.on(function ()
				error("boom", 0)
			end)

			task.spawn(function ()
				local ok: boolean, reason: any = harness.client.Echo.invoke(1)
				table.insert(results, `{ok} {reason}`)
			end)

			local promise = harness.client.Inventory.Transfer.invoke(1, 2, 3)
			steps(harness.mock)

			named(harness.failures.server[1], "handler", "Echo")
			named(harness.failures.server[2], "handler", "Inventory.Transfer")
			expect(table.concat(results, ",")).is("false boom")
			expect(`{promise.settled[1]} {promise.settled[2]}`).is("false boom")
		end)

		test("a refused structured return names the function, and its caller gets the refusal alone", function ()
			local harness: Harness = setup("Example")

			harness.server.Inventory.Transfer.on(function (): (boolean, string?)
				return true, string.rep("x", LONG_REASON)
			end)

			local promise = harness.client.Inventory.Transfer.invoke("bag", "chest", 1, 1)
			steps(harness.mock)

			named(harness.failures.server[1], "handler", "Inventory.Transfer")
			expect(harness.failures.server[1].detail).is(
				"Inventory.Transfer: Inventory.Transfer.reason: length out of range"
			)
			expect(promise.settled[2]).is("Inventory.Transfer.reason: length out of range")
		end)

		test("a queue overflow names the event", function ()
			local harness: Harness = setup("Events")

			for _ = 1, QUEUE + 1 do
				harness.client.Ready.fire()
			end

			steps(harness.mock)

			named(harness.failures.server[1], "queue", "Ready")
		end)
	end)

	describe("on the client", function ()
		test("a decode named once by its reader, one named by a reply's field and one inside a shared pair", function ()
			local events: Harness = setup("Events")
			local reply: Harness = setup("Example")
			local patch: Harness = setup("Example")
			local stack: { [string]: any } = { item = "a", quantity = OUT_OF_RANGE }

			-- A Sync with no value after its id, then a reply to slot 1 whose reason is too long, both straight from the server
			events.mock.server.reliable(events.player, packet({ 1 }))
			reply.mock.server.reliable(reply.player, packet({ 2, 1, 0, 0, 2, LONG_REASON }))
			patch.server.Inventory.Patch.fire(patch.player, { version = 1, set = { [1] = stack }, cleared = {} })

			for _, harness: Harness in { events, reply, patch } do
				steps(harness.mock)
			end

			expect(events.failures.client[1].detail).is("Sync: truncated")
			expect(reply.failures.client[1].detail).is(
				"Inventory.Transfer: Inventory.Transfer.reason: length out of range"
			)
			expect(patch.failures.client[1].detail).is("Inventory.Patch: Stack.quantity: out of range")
			named(reply.failures.client[1], "decode", "Inventory.Transfer")
			named(patch.failures.client[1], "decode", "Inventory.Patch")
		end)

		test("a decode of text that is not UTF-8 inside a shared pair names the event", function ()
			local harness: Harness = setup("Console")
			local length: number = #NOT_TEXT

			-- Built by hand, since the server's pair checks the text in every build: the id, Line's u16 length and
			-- its bytes, then Kind's flag byte
			harness.mock.server.reliable(harness.player, packet({ LINE, length, 0, NOT_TEXT[1], NOT_TEXT[2], 0 }))
			steps(harness.mock)

			named(harness.failures.client[1], "decode", "Decree.line")
			expect(harness.failures.client[1].detail).is("Decree.line: Decree.Line: invalid UTF-8")
		end)

		test("a listener's error and its yield, and a queue overflow, name the event", function ()
			local harness: Harness = setup("Events")
			local queued: Harness = setup("Events")

			harness.client.Sync.on(function (value: number)
				if value == 1 then
					error("boom")
				end

				coroutine.yield()
			end)

			harness.server.Sync.fire(harness.player, 1)
			harness.server.Sync.fire(harness.player, 2)
			harness.mock:step()
			harness.mock:step()
			across(harness.mock)

			for value: number = 1, QUEUE + 1 do
				queued.server.Sync.fire(queued.player, value)
			end

			steps(queued.mock)

			named(harness.failures.client[1], "listener", "Sync")
			named(harness.failures.client[2], "listener", "Sync")
			named(queued.failures.client[1], "queue", "Sync")
			expect(harness.failures.client[2].detail).is("Sync: a sync listener yielded")
		end)
	end)
end)
